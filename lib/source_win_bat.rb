#!/usr/bin/ruby

require 'securerandom'
require 'tmpdir'
require_relative 'unixcompatenv'

class SourceWindowsBatch
  
  VERSION = "0.3.0"

  def main(argv)
    options = parse_args!(argv)

    unless [:cygwin, :msys, :wsl].include? UnixCompatEnv.compat_env
      raise "You're in an unsupported UNIX compatible environment"
    end

    env = prepare_env_vars
    env_tmp_file_in = mk_tmpname(".env")
    macro_tmp_file_in = mk_tmpname(".doskey")
    cwd_tmp_file_in = mk_tmpname(".cwd")
    win_cmd = argv[3..-1].map {|v| "#{v}"}.join(" ")
    win_cmd += " & call set SW_EXITSTATUS=%^ERRORLEVEL% "
    win_cmd = concat_envdump(win_cmd, env_tmp_file_in)
    win_cmd = concat_macrodump(win_cmd, macro_tmp_file_in)
    win_cmd = concat_cwddump(win_cmd, cwd_tmp_file_in)
    win_cmd += " & call exit %^SW_EXITSTATUS%"
    if options[:show_cmd]
      STDERR.puts "SW: " + win_cmd
    end
    Signal.trap(:INT, "SIG_IGN")
    if UnixCompatEnv.compat_env == :wsl
      # * Skip winpty, assuming the system's WSL supports ConPTY
      # * Use an absolute path since SWB overwrites PATH with Windows-style PATH in WSL
      pid = Process.spawn(env,
                          UnixCompatEnv.to_compat_path('C:\\Windows\\System32\\cmd.exe'),
                          '/C', win_cmd, :in => 0, :out => 1, :err => 2)
    elsif !STDOUT.isatty
      pid = Process.spawn(env, 'cmd.exe', '/C', win_cmd, :in => 0, :out => 1, :err => 2)
    else
      pid = Process.spawn(env, 'winpty', '--', 'cmd.exe', '/C', win_cmd, :in => 0, :out => 1, :err => 2)
    end
    Signal.trap(:INT) do
      Process.signal("-KILL", pid)
    end
    status = nil
    loop do
      _, status = Process.wait2(pid)
      break if status.exited?
    end
    
    begin
      codepage = detect_ansi_codepage
      conv_setenv_stmts(env_tmp_file_in, argv[0], :bash, codepage)
      conv_doskey_stmts(macro_tmp_file_in, argv[1], :bash, codepage)
      gen_chdir_cmds(cwd_tmp_file_in, argv[2], :bash, codepage)
      if !options[:preserve_dump]
        [env_tmp_file_in, macro_tmp_file_in, cwd_tmp_file_in].each do |f|
          File.delete f
        end
      end
    rescue Errno::ENOENT
      # ignore
    end

    exit(status.exitstatus)
  end

  private

  def parse_args!(argv)
    options = {}
    while argv.length > 0 && argv[0].start_with?("-")
      arg = argv.shift
      case arg 
      when "--"
        next
      when "--show-cmd"
        options[:show_cmd] = true
      when "--preserve-dump"
        options[:preserve_dump] = true
      when "--debug"
        options[:show_cmd] = true
        options[:preserve_dump] = true
      when "--help", "-h"
        puts help
        exit
      when "--version", "-v"
        STDERR.puts "SourceWinBat Version #{VERSION}"
        exit
      else
        STDERR.puts "Unknown option '#{arg}'"
        exit 1
      end
    end
    if argv.length < 4 || argv[3].chomp.empty?
      STDERR.puts "Error: No Windows command is given\n---"
      STDERR.puts help
      exit 1
    end

    options
  end

  def help
    <<EOS
sw, or SourceWinBat, is a utility to run Windows batch files from WSL /
MSYS2 / Cygwin and sync environment variables, and working directories 
between batch files and their UNIX Bash shell.

  Usage:
    sw [ [sw_options] -- ] win_bat_file [args...]

  Sw options:
    -h --help           Show this help message
    -v --version        Show the version information
    --preserve-dump     Preserve the environment dump files of cmd.exe for
                        debugging
    --show-cmd          Show the command executed in cmd.exe for debugging
    --debug             Enable '--preserve-dump' and '--show-cmd' options

  Examples:
    sw echo test
    sw somebat.bat

You can control some behavior of SourceWinBat by defining following environment
variables.

  Blacklisting and Whitelisting Environment Variable Not to be Synced:

    SWB_BLACKLIST       Define comma-separated environment variable names with 
                        regular expressions. All environment variables included
                        in this list will not be synced by SourceWinBat.

    SWB_WHITELIST       Define variable names in the same manner as that of 
                        SWB_BLACKLIST. All environment variables that are NOT
                        included in the list will NOT be synced by SourceWinBat.

    Examples:

      export SWB_BLACKLIST="foo:bar:baz_.*"

        "foo", "bar", and any variables name of which start with "baz_" will not
        be synced

      export SWB_BLACKLIST="sync_taboo"
      export SWB_WHITELIST="sync_.*"

        Only variables name of which start with "sync_" will be synced,
        except "sync_taboo".
EOS
  end

  def detect_ansi_codepage
    if !STDOUT.isatty && UnixCompatEnv.compat_env == :wsl
      # cmd.exe seems to use UTF-8 when Stdout is redirected in WSL. TODO: Is it always fixed?
      return "65001"  # CP65001 is UTF-8
    end

    posh_cmd = <<-EOS
      Get-WinSystemLocale | Select-Object Name, DisplayName,
                                          @{ n='OEMCP'; e={ $_.TextInfo.OemCodePage } },
                                          @{ n='ACP';   e={ $_.TextInfo.AnsiCodePage } }
    EOS
    posh_res = `powershell.exe "#{posh_cmd.gsub("$", "\\$")}"`
    locale = posh_res.lines.select {|line| !(line =~ /^\s*$/)}[-1].chomp
    ansi_cp = locale.split(" ")[-1]
    ansi_cp
  end

  def serialize_wslenvs(wslenvs)
    wslenvs.map {|varname, opt| "#{varname}#{opt.empty? ? "" : "/#{opt}"}"}.join(":")
  end

  def parse_wslenv(wslenv_str)
    wslenvs = Hash[]
    wslenv_str.split(":").each do |wslenvvar|
      envvar_name, envvar_opt = wslenvvar.split('/')
      wslenvs[envvar_name] = envvar_opt || ""
    end
    wslenvs
  end

  def whitelist_block?(envvar_name)
    return false if !ENV["SWB_WHITELIST"]
    ENV["SWB_WHITELIST"].split(":").each do |name_regexp|
      return false if Regexp.new(name_regexp) =~ envvar_name
    end
    true
  end

  def blacklist_block?(envvar_name)
    return false if !ENV["SWB_BLACKLIST"]
    ENV["SWB_BLACKLIST"].split(":").each do |name_regexp|
      return true if Regexp.new(name_regexp) =~ envvar_name
    end
    false
  end

  def prepare_env_vars
    return {} if UnixCompatEnv.compat_env != :wsl

    wslenvs = Hash[]
    ENV.each do |envvar_name, _|
      next if whitelist_block?(envvar_name) || blacklist_block?(envvar_name)
      wslenvs[envvar_name] = ""
    end
    wslenvs.merge!(parse_wslenv(ENV['WSLENV'])) if ENV['WSLENV']
    # We don't use '/l' option, but convert paths by ourselves instead.
    # See the comment that starts with 'How PATH in WSLENV is handled'
    wslenvs['PATH'] = ""
    var_wslenv = serialize_wslenvs(wslenvs)

    paths = []
    ENV['PATH'].split(":").each do |path|
      begin
        rpath = File.realpath(path)
        if rpath.start_with?(UnixCompatEnv.win_root_in_compat)
          path = UnixCompatEnv.to_win_path(rpath)
        end
      rescue Errno::ENOENT
      end
      paths.push(path)
    end
    var_path = paths.join(';')

    {"WSLENV" => var_wslenv, "PATH" => var_path}
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

  def to_compat_pathlist(path, shell)
    raise "Unsupporeted" unless shell == :bash
    path.split(";")
      .map {|p| UnixCompatEnv.to_compat_path(p)}
      .join(":")
  end

  def to_env_stmt(set_stmt, shell)
    raise "Unsupporeted" unless shell == :bash
    var, val = /([^=]*)=(.*)$/.match(set_stmt)[1..2]

    is_var_valid = /^[a-zA-Z_][_0-9a-zA-Z]*$/ =~ var
    return nil unless is_var_valid

    if var == "PATH" && UnixCompatEnv.compat_env != :wsl
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

  def conv_setenv_stmts(setenvfile, outfile, shell, codepage)
    raise "Unsupporeted" if shell != :bash

    File.open(outfile, "w") do |f_out|
      envs = []
      File.read(setenvfile, encoding: "CP#{codepage}:UTF-8").lines.each do |set_stmt|
        var, val = /([^=]*)=(.*)$/.match(set_stmt)[1..2]

        is_var_valid = /^[a-zA-Z_][_0-9a-zA-Z]*$/ =~ var
        next if !is_var_valid
        next if whitelist_block?(var) || blacklist_block?(var)

        if var == "PATH"
          val = to_compat_pathlist(val, shell)
        end

        envs.push(var)
        f_out.puts("export #{var}='#{escape_singlequote(val.chomp)}'")
      end
      if UnixCompatEnv.compat_env == :wsl
        # How PATH in WSLENV is handled:
        # SWB configures PATH's WSLENV flag as follows
        #   A. When SWB internally launches a Windows bat file
        #     Set the PATH's flag to '' (nothing) since SWB converts each Unix 
        #     path to a corresponding Windows path.
        #   B. When SWB syncs environment variables with the result of a bat file
        #     Leave the PATH's WSLENV flag as is
        wslenvs = Hash[*envs.flat_map {|env| [env, ""]}]
        wslenvs.delete('PATH')
        wslenvs.merge!(parse_wslenv(ENV['WSLENV'])) if ENV['WSLENV']

        if wslenvs.length > 0
          f_out.puts("export WSLENV='#{serialize_wslenvs(wslenvs)}'")
        end
      end
    end
  end

  def conv_doskey_stmts(doskeyfile, outfile, shell, codepage)
    raise "Unsupporeted" unless shell == :bash

    File.open(outfile, "w") do |f_out|
      File.open(doskeyfile, encoding: "CP#{codepage}:UTF-8") do |f_in|
       f_in.each_line do |doskey_stmt|
          key, body = /([^=]*)=(.*)$/.match(doskey_stmt)[1..2]

          is_key_valid = /^[a-zA-Z][0-9a-zA-Z]*$/ =~ key
          next if !is_key_valid

          body_substituted = escape_singlequote(body.chomp)
            .gsub(/(?<param>\$[1-9]|\$\$|\$\*)/, '\'"\k<param>"\'')

          f_out.puts <<-"EOS"
          #{key} () {
            sw '#{body_substituted}'
          }
          EOS
        end
      end
    end
  end

  def gen_chdir_cmds(dirs, outfile, shell, codepage)
    raise "Unsupporeted" unless shell == :bash
    return unless File.exist?(dirs)

    lines = File.read(dirs, encoding:"CP#{codepage}:UTF-8").lines.select {|line| !line.empty?}
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

end
