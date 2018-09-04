#!/usr/bin/ruby

require 'securerandom'
require 'tmpdir'
require 'pathname'

def main
  if ARGV.length < 4 || ARGV[3].chomp.empty?
    STDERR.puts <<-EOS
Usage: ec windows_cmd_or_batch [options_for_the_cmd]

Internal Ruby command Usage:
#{File.basename(__FILE__)} env_out macro_out cwd_out windows_cmd_or_batch [options_for_the_cmd]
    EOS
    exit
  end

  host_env = {
    shell: :bash,
    compat: detect_hostenv,
    comproot: detect_compat_root_in_win,
    winroot: detect_win_root_in_compat
  }
  unless [:cygwin, :msys, :wsl].include? host_env[:compat] 
    raise "You're in an unsupported UNIX compatible environment"
  end

  env_tmp_file_in = mk_tmpname(".env", host_env)
  macro_tmp_file_in = mk_tmpname(".doskey", host_env)
  cwd_tmp_file_in = mk_tmpname(".cwd", host_env)
  win_cmd = concat_envdump(ARGV[3], env_tmp_file_in, host_env)
  win_cmd = concat_macrodump(win_cmd, macro_tmp_file_in, host_env)
  win_cmd = concat_cwddump(win_cmd, cwd_tmp_file_in, host_env)
  # puts win_cmd
  Signal.trap(:INT, "SIG_IGN")
  pid = Process.spawn('winpty', '--', 'cmd.exe', '/C', win_cmd, :in => 0, :out => 1, :err => 2)
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
  
  [env_tmp_file_in, macro_tmp_file_in, cwd_tmp_file_in].each do |f|
    begin
      File.delete f
    rescue Errno::ENOENT
      # ignore
    end
  end
end

def detect_hostenv()
  case RUBY_PLATFORM
  when /msys/
    return :msys
  when /linux/
    return :wsl
  when /cygwin/
    return :cygwin
  else
    return :win
  end
end

def detect_compat_root_in_win()
  case detect_hostenv
  when :msys, :cygwin
    path = `cygpath -w /`.chomp
    if !path.end_with?('/')  # msys2 does not output the trailing '/'
      path += '/'
    end
  when :wsl
    return nil
  end
end

def detect_win_root_in_compat()
  case detect_hostenv
  when :msys, :cygwin
    root = `cygpath -u c:/`.chomp
  when :wsl
    root = `wslpath c:/`.chomp
  end
  raise "unexpected win root path" unless root.end_with?("c/")
  root[0...-2]
end

def mk_tmpname(suffix, env)
  "#{env[:winroot]}c/Users/#{ENV['USER']}/AppData/Local/Temp/#{SecureRandom.uuid + suffix}"
end

def concat_envdump(cmd, tmpfile, env)
  cmd + " & set > #{dq_win_path(to_win_path(tmpfile, env))}"
end

def concat_macrodump(cmd, tmpfile, env)
  #TODO: escape
  cmd + " & doskey /macros > #{dq_win_path(to_win_path(tmpfile, env))}"
end

def concat_cwddump(cmd, tmpfile, env)
  #TODO: escape
  winpath = dq_win_path(to_win_path(tmpfile, env))
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

def to_win_path(path, env)
  path = Pathname.new(path).cleanpath.to_s
  raise "Abs path is expected" if path[0] != "/"

  if path.start_with?(env[:winroot])
    drive = path[env[:winroot].length]
    "#{drive.upcase}:\\" + (path[(env[:winroot].length + 2)..-1] || '').gsub('/', '\\')
  elsif env[:compat] == :wsl
    raise "A WSL path which cannot be accessed from Windows: #{path}"
  else
    # [0...-1] trims trailing '/'
    env[:comproot][0...-1] + path.gsub('/', '\\')
  end
end

def to_compat_path(path, env)
  if !env[:comproot].nil? && path.start_with?(env[:comproot])
    path = path[env[:comproot].length..-1]
  end
  if /^[a-zA-Z]:/ =~ path
    drive = path[0]
    path = env[:winroot] + drive.downcase + (path[2..-1] || "")
  end
  path.gsub('\\', '/')
end

def to_compat_pathenv(path, env)
  raise "Unsupporeted" unless env[:shell] == :bash
  paths = path.split(";")
  imported = paths.map {|p| to_compat_path(p, env)}.join(":")
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
  return unless File.exist?(dirs)

  lines = File.read(dirs).lines.select {|line| !line.empty?}
  cwd = lines[0]
  dirs = lines[1..-1]
  
  res = []
  dirs.reverse.each do |dir|
    res.push "cd '#{escape_singlequote(to_compat_path(dir.chomp, env))}'"
    res.push "pushd . > /dev/null"
  end
  res.push "cd '#{escape_singlequote(to_compat_path(cwd.chomp, env))}'"
  File.write(outfile, res.join("\n"))
end

main
