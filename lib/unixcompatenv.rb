require 'pathname'

module UnixCompatEnv

  @@compat_env = nil
  @@compat_root = nil
  @@win_root = nil
  @@win_tmp = nil

  def self.detect_installed_compat_envs
    res = {}

    default_paths = {
      wsl: "/c/Windows/System32/bash.exe",
      msys: "/c/tools/msys64/usr/bin/bash.exe",
      cygwin: "/c/tools/cygwin/bin/bash.exe"
    }

    default_paths.each do |env, path|
      path = win_root_in_compat[0..-2] + path
      if File.exists?(path)
        res[env] = path
      end
    end

    res
  end

  def self.compat_env
    @@compat_env ||=
      case RUBY_PLATFORM
      when /msys/
        :msys
      when /linux/
        :wsl
      when /cygwin/
        :cygwin
      else
        :win
      end
  end

  def self.compat_root_in_win
    return @@compat_root if @@compat_root || compat_env == :wsl  # @@compat_root should be nil for :wsl
    case compat_env
    when :msys, :cygwin
      path = `cygpath -w /`.chomp
      if !path.end_with?("\\")
        path += "\\"
      end
      @@compat_root = path
    when :wsl
      @@compat_root = nil
    end
    @@compat_root
  end

  def self.win_root_in_compat
    return @@win_root if @@win_root
    case compat_env
    when :msys, :cygwin
      root = `cygpath -u c:/`.chomp
    when :wsl
      root = `wslpath c:/`.chomp
    end
    raise "unexpected win root path" unless root.end_with?("c/")
    @@win_root = root[0...-2]
  end

  def self.win_tmp_in_compat
    return @@win_tmp if @@win_tmp
    case compat_env
    when :wsl, :cygwin
      @@win_tmp = to_compat_path(`cmd.exe /C "echo %TEMP%"`.chomp) + '/'
    when :msys
      @@win_tmp = to_compat_path(ENV['temp'])
    end
    @@win_tmp
  end

  def self.to_win_path(path)
    path = Pathname.new(path).cleanpath.to_s
    raise "Abs path is expected: #{path}" if path[0] != "/"

    if path.start_with?(win_root_in_compat)
      drive = path[win_root_in_compat.length]
      "#{drive.upcase}:\\" + (path[(win_root_in_compat.length + 2)..-1] || '').gsub('/', '\\')
    elsif compat_env == :wsl
      raise "A WSL path which cannot be accessed from Windows: #{path}"
    else
      # [0...-1] trims trailing '/'
      compat_root_in_win[0...-1] + path.gsub('/', '\\')
    end
  end

  def self.to_compat_path(path)
    if !compat_root_in_win.nil? && path.start_with?(compat_root_in_win)
      path = path[compat_root_in_win.length - 1 .. -1]
    end
    if /^[a-zA-Z]:/ =~ path
      drive = path[0]
      path = win_root_in_compat + drive.downcase + (path[2..-1] || "")
    end
    path.gsub('\\', '/')
  end

end
