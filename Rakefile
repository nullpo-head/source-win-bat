require_relative './lib/unixcompatenv'

task default: %w[test]

task :test do

  # Get all compatibility environments to test
  all_compat_envs = [:wsl, :msys, :cygwin]
  installed_compat_envs = UnixCompatEnv.detect_installed_compat_envs
  ignored_compat_envs = (ENV['IGNORED_COMPATENV'] || '').split(',')
                                                        .map(&:chomp)
  env_to_readablestr = {wsl: "WSL", msys: "MSYS2", cygwin: "Cygwin"}

  compat_envs = {}
  all_compat_envs.each do |env|
    next if ignored_compat_envs.include?(env_to_readablestr[env])
    if installed_compat_envs.has_key?(env)
      compat_envs[env] = installed_compat_envs[env]
      next
    end
    path_env_name = "#{env_to_readablestr[env].upcase}_BASH_PATH"
    if ENV[path_env_name] and File.exists?(ENV[path_env_name])
      compat_envs[env] = ENV[path_env_name]
      next
    end
    STDERR.puts "#{env_to_readablestr[env]} is not found. Set #{path_env_name} or add #{env_to_readablestr[env]} to IGNORED_COMPATENV environment variable. (Comma sepearated values)"
    exit 1
  end

  # Test
  unix_double_quote = -> str {
    '"' + str.gsub('\\') {|_| '\\\\'}.gsub('"') {|_| '\\"'}.gsub('$') {|_| '\\$'} + '"'
  }
  cmd_double_quote = -> str {
    '"' + str.gsub('\\') {|_| '\\\\'}.gsub('"') {|_| '\\"'} + '"'
  }
  ok_results = {}
  succeeded = true
  tests_winpath = UnixCompatEnv.to_win_path(File.realpath("./test"))
  lib_winpath = UnixCompatEnv.to_win_path(File.realpath("./lib"))
  compat_envs.each do |env, path|
    case env
    when :wsl
      convpath_win2compat = "wslpath"
    when :msys, :cygwin
      convpath_win2compat = "cygpath -u"
    end
    cd2test = "cd \"$(#{convpath_win2compat} '#{tests_winpath}')\"; "
    rubylib = "RUBYLIB=\"$(#{convpath_win2compat} '#{lib_winpath}')\" "
    if ENV['TEST']
      testcases = ENV['TEST']
    else
      testcases = "test_*.bash"
    end
    prove = "prove -e /bin/bash -j4 #{testcases}; "

    cmd_in_env = cd2test + rubylib + prove
    if env == UnixCompatEnv.compat_env
      cmd = "bash -lc #{unix_double_quote.call(cmd_in_env)}"
    elsif [UnixCompatEnv.compat_env, env].include?(:wsl)
      cmd = "#{path} -lc #{unix_double_quote.call(cmd_in_env)}"
    else
      # Cygwin and MSYS2 cannot launch each other's applications directly due to DLL conflict.
      # Solve that by wrapping a command by cmd.exe.
      cmd_env_launch = "#{UnixCompatEnv.to_win_path(path)} -lc #{cmd_double_quote.call(cmd_in_env)}"
      cmd = "cmd.exe /C #{unix_double_quote.call(cmd_env_launch)}"
    end
    puts "\e[1m\e[33m===#{env_to_readablestr[env]}===\e[0m\e[22m"
    sh cmd do |ok, _|
      ok_results[env] = ok
      succeeded &&= ok
    end
  end
  
  puts "\e[1m\e[33m===Summary===\e[0m\e[22m"
  compat_envs.each do |env, _|
    puts "#{env_to_readablestr[env]}: #{ok_results[env] ? "PASSED" : "FAILED"}"
  end

  exit succeeded ? 0 : 1
end
