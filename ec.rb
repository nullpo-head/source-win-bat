#!/usr/bin/ruby

require 'securerandom'
require 'tmpdir'
require 'pathname'

def main
  if ARGV.length <4
    STDERR.puts "Usage: #{File.basename(__FILE__)} env_out macro_out cwd_out windows_cmd"
    exit
  end

  host_env = {shell: :bash, compat: detect_hostenv}

  env_tmp_file_in = mk_tmpname(".env", host_env)
  macro_tmp_file_in = mk_tmpname(".doskey", host_env)
  cwd_tmp_file_in = mk_tmpname(".cwd", host_env)
  tmp_wincmd_file = mk_tmpname(".cmd", host_env)
  win_cmd = concat_envdump(ARGV[3], env_tmp_file_in, host_env)
  win_cmd = concat_macrodump(win_cmd, macro_tmp_file_in, host_env)
  win_cmd = concat_cwddump(win_cmd, cwd_tmp_file_in, host_env)
  # puts win_cmd
  File.write(tmp_wincmd_file, win_cmd)
  winpty_launch_cmd = "winpty -- #{tmp_wincmd_file} "
  puts winpty_launch_cmd
  Signal.trap(:INT, "SIG_IGN")
  pid = Process.spawn('cmd.exe', '/C', winpty_launch_cmd, :in => 0, :out => 1, :err => 2)
  Signal.trap(:INT) do
    Process.signal("-KILL", pid)
  end
  Process.wait(pid)

  env_out = ARGV[0]
  conv_to_host_cmds(env_tmp_file_in, env_out, method(:to_env_stmt), host_env)
  macro_out = ARGV[1]
  conv_to_host_cmds(macro_tmp_file_in, macro_out, method(:to_macro_stmt), host_env)
  cwd_out = ARGV[2]
  gen_chdir_cmds(cwd_tmp_file_in, cwd_out, host_env)
  
  File.delete(env_tmp_file_in, macro_tmp_file_in, cwd_tmp_file_in, tmp_wincmd_file)
end

def detect_hostenv()
  case RUBY_PLATFORM
  when /msys/
    return :msys
  when /linux/
    return :wsl
  else
    return :win
  end
end

def mk_tmpname(suffix, env)
  if env[:compat] == :wsl
    tmpdir = "/mnt/c/Users/tasaeki/AppData/Local/Temp"
  elsif env[:compat] == :msys
    tmpdir = "/c/Users/tasaeki/AppData/Local/Temp"
  else
    tmpdir = Dir.tmpdir
  end
  tmpdir + "/" + SecureRandom.uuid + suffix
end

def concat_envdump(cmd, tmpfile, env)
  cmd + " & set > #{dq_win_path(to_win_path(tmpfile, env[:compat]))}"
end

def concat_macrodump(cmd, tmpfile, env)
  #TODO: escape
  cmd + " & doskey /macros > #{dq_win_path(to_win_path(tmpfile, env[:compat]))}"
end

def concat_cwddump(cmd, tmpfile, env)
  #TODO: escape
  winpath = dq_win_path(to_win_path(tmpfile, env[:compat]))
  cmd + " & cd > #{winpath} & pushd >> #{winpath}"
end

def dq_win_path(str)
  str.gsub(/\//, '\\')
     .split("\\")
     .map {|dir| dir.include?(" ") ? "\"#{dir}\"" : dir}
     .join("\\")
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

def to_win_path(path, compat)
  path = Pathname.new(path).cleanpath.to_s
  conv_funcs = {
    wsl: -> wsl_path {
      return nil unless wsl_path.start_with?(/\/mnt\/[a-z]/)
      wsl_path.gsub(/\//, "\\")
              .gsub(/^\\mnt\\([a-z])/) {|drive|
                drive[5].upcase + ":"
              }
    },
    msys: -> msys_path {
      msys_path.gsub(/\//, "\\")
               .gsub(/^\\([a-zA-Z])\\/, '\1:\\')
    }
  }
  raise "Unsupporeted" if conv_funcs[compat].nil?
  conv_funcs[compat].call(path)
end

def to_compat_path(path, compat)
  # TODO: canonicalize
  conv_funcs = {
    wsl: -> win_path {
      win_path.gsub(/\\/, "/")
              .gsub(/([a-zA-Z]):/) {|drive|
                "/mnt/" + drive[0].downcase
              }
    },
    msys: -> win_path {
      win_path.gsub(/\\/, "/")
              .gsub(/([a-zA-Z]):/) {|drive|
                "/" + drive[0].downcase
              }
              .gsub(/\/c\/tools\/msys64\//, '/')
    }
  }
  raise "Unsupporeted" if conv_funcs[compat].nil?
  conv_funcs[compat].call(path)
end

def to_compat_pathenv(path, env)
  raise "Unsupporeted" unless env[:shell] == :bash
  paths = path.split(";")
  imported = paths.map {|p| to_compat_path(p, env[:compat])}.join(":")
  if env[:compat] == :wsl
    imported = ENV["PATH"] + ":" + imported
  end
  imported
end

def to_env_stmt(set_stmt, env)
  raise "Unsupporeted" unless env[:shell] == :bash
  var, val = /([^=]*)=(.*)$/.match(set_stmt)[1..2]

  is_var_valid = /^[a-zA-Z_][_0-9a-zA-Z]*$/ =~ var
  return nil unless is_var_valid

  if var == "PATH"
      val = to_compat_pathenv(val, env)
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
  source '#{escape_singlequote File.realpath(__FILE__)[0...-3]}' '#{body_substituted}'
}
  EOS

end

def gen_chdir_cmds(dirs, outfile, env)
  raise "Unsupporeted" unless env[:shell] == :bash

  lines = File.read(dirs).lines
  cwd = lines[0]
  dirs = lines[1..-1]
  
  res = []
  dirs.reverse.each do |dir|
    res.push "cd '#{escape_singlequote(to_compat_path(dir.chomp, env[:compat]))}'"
    res.push "pushd . > /dev/null"
  end
  res.push "cd '#{escape_singlequote(to_compat_path(cwd.chomp, env[:compat]))}'"
  File.write(outfile, res.join("\n"))
end

main
