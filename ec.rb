#!/usr/bin/ruby

require 'securerandom'

COMPAT_ENV = {shell: :bash, compat: :msys}

def main
  if ARGV.empty?
    STDERR.puts "Usage: #{File.basename(__FILE__)} env_out macro_out windows_cmd"
    exit
  end

  env_tmp_file_in = mk_tmpname(".env")
  macro_tmp_file_in = mk_tmpname(".doskey")
  win_cmd = concat_envdump(ARGV[2], env_tmp_file_in)
  win_cmd = concat_macrodump(win_cmd, macro_tmp_file_in)
  pid = Process.spawn('cmd.exe', '/C', win_cmd, :in => 0, :out => 1, :err => 2)
  Process.wait(pid)

  env_out = ARGV[0]
  conv_to_host_cmds(env_tmp_file_in, env_out, method(:to_env_stmt), COMPAT_ENV)
  macro_out = ARGV[1]
  conv_to_host_cmds(macro_tmp_file_in, macro_out, method(:to_macro_stmt), COMPAT_ENV)
  
  File.delete(env_tmp_file_in, macro_tmp_file_in)
end

def mk_tmpname(suffix)
  SecureRandom.uuid + suffix
end

def concat_envdump(cmd, tmpfile)
  #TODO: escape
  cmd + " & set > #{tmpfile}"
end

def concat_macrodump(cmd, tmpfile)
  #TODO: escape
  cmd + " & doskey /macros > #{tmpfile}"
end

def escape_singlequote(str)
  str.gsub(/'/, '"\'"')
end

def conv_to_host_cmds(in_file, out_file, conv_method, env)
  File.open(out_file, "w") do |out|
    if File.exist?(in_file)
      File.open(in_file) do |f|
        f.each_line do |line|
          converted = conv_method.call(line, env)
          out.puts converted if converted
        end
      end
    end
  end
end

def conv_path_env(path, env)
  raise "Unsupporeted" unless env[:shell] == :bash

  conv_path = {
    wsl: -> win_path {
      win_path.gsub(/\\/, "/")
              .gsub(/([a-zA-Z]):/) {|drive|
                "/" + drive[0].downcase
              }
              .gsub(/\/mnt\/c\//, '/')
    },
    msys: -> win_path {
      win_path.gsub(/\\/, "/")
              .gsub(/([a-zA-Z]):/) {|drive|
                "/" + drive[0].downcase
              }
              .gsub(/\/c\/tools\/msys64\//, '/')
    }
  }
  raise "Unsupporeted" if conv_path[env[:compat]].nil?

  paths = path.split(";")
  paths.map(&conv_path[env[:compat]]).join(":")
end

def to_env_stmt(set_stmt, env)
  raise "Unsupporeted" unless env[:shell] == :bash
  var, val = /([^=]*)=(.*)$/.match(set_stmt)[1..2]

  is_var_valid = /^[a-zA-Z_][_0-9a-zA-Z]*$/ =~ var
  return nil unless is_var_valid

  if var == "PATH"
      val = conv_path_env(val, env)
  end

  "export #{var}='#{escape_singlequote(val.chomp)}'"
end

def to_macro_stmt(doskey_stmt, env)
  raise "Unsupporeted" unless env[:shell] == :bash
  key, body = /([^=]*)=(.*)$/.match(doskey_stmt)[1..2]
  
  is_key_valid = /^[a-zA-Z][0-9a-zA-Z]*$/ =~ key
  return nil unless is_key_valid

  body_substituted = escape_singlequote(body.chomp)
                     .gsub(/(?<param>\$[1-9]|\$\$|\$\*)/, '\'"\k<param>"\'')
  
  <<-"EOS"
#{key} () {
  source '#{escape_singlequote __FILE__[0...-3]}' '#{body_substituted}'
}
  EOS

end

main
