require_relative 'unixcompatenv'

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
  succeeded = true
  tests_winpath = UnixCompatEnv.to_win_path(File.realpath("./tests"))
  compat_envs.each do |env, path|
    case env
    when :wsl
      cmd = "cd \\\"\\$(wslpath '#{tests_winpath}')\\\"; "
    when :msys, :cygwin
      cmd = "cd \\\"\\$(cygpath -u '#{tests_winpath}')\\\"; "
    end
    cmd += "prove -e /bin/bash -j4 test_*.bash; "
    if env != UnixCompatEnv.compat_env
      cmd = "#{path} -lc \"#{cmd}\""
    else
      cmd = "bash -lc \"#{cmd}\""
    end
    sh cmd do |ok, _|
      succeeded &&= ok
    end
  end
  
  exit succeeded ? 0 : 1
end