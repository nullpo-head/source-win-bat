#!/usr/bin/ruby

require 'securerandom'
require 'tmpdir'
require_relative 'unixcompatenv'

def main
  if ARGV.length < 4 || ARGV[3].chomp.empty?
    STDERR.puts <<-EOS
Usage: ec windows_cmd_or_batch [options_for_the_cmd]

Internal Ruby command Usage:
#{File.basename(__FILE__)} env_out macro_out cwd_out windows_cmd_or_batch [options_for_the_cmd]
    EOS
    exit
  end

  unless [:cygwin, :msys, :wsl].include? UnixCompatEnv.compat_env
    raise "You're in an unsupported UNIX compatible environment"
  end

  env_tmp_file_in = mk_tmpname(".env")
  macro_tmp_file_in = mk_tmpname(".doskey")
  cwd_tmp_file_in = mk_tmpname(".cwd")
  win_cmd = concat_envdump(ARGV[3], env_tmp_file_in)
  win_cmd = concat_macrodump(win_cmd, macro_tmp_file_in)
  win_cmd = concat_cwddump(win_cmd, cwd_tmp_file_in)
  # puts win_cmd
  Signal.trap(:INT, "SIG_IGN")
  if UnixCompatEnv.compat_env == :wsl || !STDOUT.isatty
    # Assume the system's WSL supports ConPTY
    pid = Process.spawn('cmd.exe', '/C', win_cmd, :in => 0, :out => 1, :err => 2)
  else
    pid = Process.spawn('winpty', '--', 'cmd.exe', '/C', win_cmd, :in => 0, :out => 1, :err => 2)
  end
  Signal.trap(:INT) do
    Process.signal("-KILL", pid)
  end
  Process.wait(pid)

  env_out = ARGV[0]
  conv_to_host_cmds(env_tmp_file_in, env_out, method(:to_env_stmt), :bash)
  macro_out = ARGV[1]
  conv_to_host_cmds(macro_tmp_file_in, macro_out, method(:to_macro_stmt), :bash)
  cwd_out = ARGV[2]
  gen_chdir_cmds(cwd_tmp_file_in, cwd_out, :bash)
  
  [env_tmp_file_in, macro_tmp_file_in, cwd_tmp_file_in].each do |f|
    begin
      File.delete f
    rescue Errno::ENOENT
      # ignore
    end
  end
end

def mk_tmpname(suffix)
  "#{UnixCompatEnv.win_tmp_in_compat}#{SecureRandom.uuid + suffix}"
end

def concat_envdump(cmd, tmpfile)
  cmd + " & set > #{dq_win_path(UnixCompatEnv.to_win_path(tmpfile))}"
end

def concat_macrodump(cmd, tmpfile)
  #TODO: escape
  cmd + " & doskey /macros > #{dq_win_path(UnixCompatEnv.to_win_path(tmpfile))}"
end

def concat_cwddump(cmd, tmpfile)
  #TODO: escape
  winpath = dq_win_path(UnixCompatEnv.to_win_path(tmpfile))
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
  unless File.exist?(in_file)
    return
  end
  File.open(out_file, "w") do |out|
    File.open(in_file) do |f|
      f.each_line do |line|
        line.force_encoding("ASCII-8BIT")
        converted = conv_method.call(line, env)
        out.puts converted if converted
      end
    end
  end
end


def to_compat_pathlist(path, shell)
  raise "Unsupporeted" unless shell == :bash
  paths = path.split(";")
  imported = paths.map {|p| UnixCompatEnv.to_compat_path(p)}.join(":")
  if UnixCompatEnv.compat_env == :wsl
    imported = ENV["PATH"] + ":" + imported
  end
  imported
end

def to_env_stmt(set_stmt, shell)
  raise "Unsupporeted" unless shell == :bash
  var, val = /([^=]*)=(.*)$/.match(set_stmt)[1..2]

  is_var_valid = /^[a-zA-Z_][_0-9a-zA-Z]*$/ =~ var
  return nil unless is_var_valid

  if var == "PATH"
    val = to_compat_pathlist(val, :bash)
  end

  stmt = "export #{var}='#{escape_singlequote(val.chomp)}'"
  return stmt if UnixCompatEnv.compat_env != :wsl

  if var == "PATH"
    stmt += "\nexport WSLENV=PATH/l:${WSLENV:-__EC_DUMMY_ENV}"
  else
    stmt += "\nexport WSLENV=#{var}:${WSLENV:-__EC_DUMMY_ENV}"
  end
  stmt
end

def to_macro_stmt(doskey_stmt, shell)
  raise "Unsupporeted" unless shell == :bash
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

def gen_chdir_cmds(dirs, outfile, shell)
  raise "Unsupporeted" unless shell == :bash
  return unless File.exist?(dirs)

  lines = File.read(dirs).lines.select {|line| !line.empty?}
  cwd = lines[0]
  dirs = lines[1..-1]
  
  res = []
  dirs.reverse.each do |dir|
    res.push "cd '#{escape_singlequote(UnixCompatEnv.to_compat_path(dir.chomp))}'"
    res.push "pushd . > /dev/null"
  end
  res.push "cd '#{escape_singlequote(UnixCompatEnv.to_compat_path(cwd.chomp))}'"
  File.write(outfile, res.join("\n"))
end

main
