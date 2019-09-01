#!/usr/bin/ruby

require 'securerandom'
require 'tmpdir'
require_relative 'unixcompatenv'

class SourceWindowsBatch
  
  VERSION = "0.3.0"

  def main(argv)
    args = parse_args!(argv)
    args.merge!(parse_option_envs(ENV))

    unless [:cygwin, :msys, :wsl].include? UnixCompatEnv.compat_env
      raise "You're in an unsupported UNIX compatible environment"
    end

    win_cmd = args[:wincmd]
    win_cmd += " & call set SW_EXITSTATUS=%^ERRORLEVEL% "
    win_cmd, env_init_file, env = concat_envinit(win_cmd)
    win_cmd, env_windump_file   = concat_envdump(win_cmd)
    win_cmd, macro_windump_file = concat_macrodump(win_cmd)
    win_cmd, cwd_windump_file   = concat_cwddump(win_cmd)
    win_cmd += " & call exit %^SW_EXITSTATUS%"

    if args[:show_cmd]
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
      conv_setenv_stmts(env_windump_file, args[:env_sync_file], :bash, codepage)
      conv_doskey_stmts(macro_windump_file, args[:macro_sync_file], :bash, codepage)
      gen_chdir_cmds(cwd_windump_file, args[:cwd_sync_file], :bash, codepage)

      if !args[:preserve_dump]
        [env_windump_file, macro_windump_file, cwd_windump_file, env_init_file].each do |f|
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
    args = {}
    while argv.length > 0 && argv[0].start_with?("-")
      arg = argv.shift
      case arg 
      when "--"
        next
      when "--show-cmd"
        args[:show_cmd] = true
      when "--preserve-dump"
        args[:preserve_dump] = true
      when "--debug"
        args[:show_cmd] = true
        args[:preserve_dump] = true
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
    
    args[:env_sync_file] = argv[0] 
    args[:macro_sync_file] = argv[1]
    args[:cwd_sync_file] = argv[2]
    args[:wincmd] = argv[3..-1].join(" ")

    args
  end

  def parse_option_envs(env)
    options = {}
    if env["SWB_DEBUG"] == "1"
      options[:show_cmd] = true
      options[:preserve_dump] = true
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
      return false if Regexp.new(name_regexp, Regexp::IGNORECASE) =~ envvar_name
    end
    true
  end

  def blacklist_block?(envvar_name)
    return false if !ENV["SWB_BLACKLIST"]
    ENV["SWB_BLACKLIST"].split(":").each do |name_regexp|
      return true if Regexp.new(name_regexp, Regexp::IGNORECASE) =~ envvar_name
    end
    false
  end


  ###
  #  Handling of environment variable in WSL is tricky due to WSLENV's strange behavior.
  #  SWB has several rules to pass UNIX environment variables to Windows.
  #  1. Normally, pass a variable by running initialization batch script before 
  #     executing the target user batch file. The initialization script contains
  #     `set` statements generated by SWB.
  #
  #  2. If a variable contains characters that need escaping, such as '|', '>',
  #     pass it by WSLENV.
  #     Why not passing all variables by WSLENV?
  #     a. It's because WSLENV has strange bahavior about case-sensitiveness.
  #     WSLENV syncs variables in a case-sensitive manner, even though Windows
  #     apps handle environment variables do not.
  #     For example, PATH variable is sometimes 'Path' in Windows. So, WSLENV fails
  #     to sync Path with Unix's PATH. Syncing by running initialization batch script
  #     in Windows environment can avoid this. 
  #     b. However, I couldn't find a complete way to escape a value of a variable.
  #     Without escaping, set statements gets crazy like `set hoge=foo | bar`, when
  #     variable `hoge` has a value of `foo | bar`. So, we cannot fully depend on
  #     initialization batch script. That's why SWB uses combination of initialization
  #     script and WSLENV.
  #
  #  3. If a variable exists in WSLENV in the first place, sync it by WSLENV.
  #     A user may set some flags in WSLENV.
  #
  #  Additionally, after completing execution of the target user batch file, if SWB
  #  finds some variables the names of which differ only in case, SWB shows warning.
  #  
  #  Handling of environment variable in MSYS2 and Cygwin is simple.
  #  They sync environment variables without any effort.
  ###
  def prepare_env_vars
    env = Hash[ENV]
    return [{}, env] if UnixCompatEnv.compat_env != :wsl

    chars_to_escape = /[><|&^%]/
    vars = Hash[]
    wslenvs = parse_wslenv(ENV['WSLENV'] || "")
    ENV.each do |envvar_name, val|
      next if whitelist_block?(envvar_name) || blacklist_block?(envvar_name)
      next if wslenvs.has_key?(envvar_name)
      if chars_to_escape =~ val
	wslenvs[envvar_name] = ""
      else
	vars[envvar_name] = val
      end
    end
    # We don't use WSLENV for Path, but convert paths by ourselves instead.
    # So, set it to empty. WSLENV is restored to the original value in Windows
    # environment by the initialization script
    wslenvs['PATH'] = "" if wslenvs['PATH']
    env['WSLENV'] = serialize_wslenvs(wslenvs) if !wslenvs.empty?

    paths = []
    ENV['PATH'].split(':').each do |path|
      begin
        rpath = File.realpath(path)
        if rpath.start_with?(UnixCompatEnv.win_root_in_compat)
          path = UnixCompatEnv.to_win_path(rpath)
        end
      rescue Errno::ENOENT
      end
      paths.push(path)
    end
    vars['PATH'] = paths.join(';')

    [vars, env]
  end

  def mk_tmpname(suffix)
    "#{UnixCompatEnv.win_tmp_in_compat}#{SecureRandom.uuid + suffix}"
  end

  def concat_envinit(cmd)
    vars_to_sync, proc_env = prepare_env_vars

    env_init_file = mk_tmpname(".cmd")
    File.write(env_init_file, vars_to_sync.map {|var, val| "set #{var}=#{val}"}.join("\r\n"))

    # Make variable expansion delayed
    expansion = /(^|[^^])%([^0-9][^ :]*[^ ]*)%/
    cmd = "call " + cmd.gsub(expansion, '\1%^\2%')

    new_cmd = "#{dq_win_path(UnixCompatEnv.to_win_path(env_init_file))} > nul & #{cmd}"

    [new_cmd, env_init_file, proc_env]
  end

  def concat_envdump(cmd)
    env_windump_file = mk_tmpname(".env")
    new_cmd = cmd + " & set > #{dq_win_path(UnixCompatEnv.to_win_path(env_windump_file))}"

    [new_cmd, env_windump_file]
  end

  def concat_macrodump(cmd)
    macro_windump_file = mk_tmpname(".doskey")
    #TODO: escape
    new_cmd = cmd + " & doskey /macros > #{dq_win_path(UnixCompatEnv.to_win_path(macro_windump_file))}"

    [new_cmd, macro_windump_file]
  end

  def concat_cwddump(cmd)
    cwd_windump_file = mk_tmpname(".cwd")
    #TODO: escape
    winpath = dq_win_path(UnixCompatEnv.to_win_path(cwd_windump_file))
    new_cmd = cmd + " & cd > #{winpath} & pushd >> #{winpath}"

    [new_cmd, cwd_windump_file]
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

  def conv_setenv_stmts(setenvfile, outfile, shell, codepage)
    raise "Unsupporeted" if shell != :bash

    envs_casemap = Hash[ENV.keys.map {|k| [k.upcase, k]}]
    File.open(outfile, "w") do |f_out|
      File.read(setenvfile, encoding: "CP#{codepage}:UTF-8").lines.each do |set_stmt|
        var, val = /([^=]*)=(.*)$/.match(set_stmt)[1..2]

        is_var_valid = /^[a-zA-Z_][_0-9a-zA-Z]*$/ =~ var
        next if !is_var_valid
        next if whitelist_block?(var) || blacklist_block?(var)

	if var.upcase == "PATH"
          val = to_compat_pathlist(val, shell)
        end

	var = envs_casemap[var] || var
        f_out.puts("export #{var}='#{escape_singlequote(val.chomp)}'")
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
