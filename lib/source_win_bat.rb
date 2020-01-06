#!/usr/bin/ruby

require 'securerandom'
require 'tmpdir'
require_relative 'unixcompatenv'

class CaseSensitiveVariableError < StandardError
end

class SourceWindowsBatch
  
  VERSION = "0.4.0"

  @args = nil
  @codepage = nil
  @file_enc_opts = {}

  def main(argv)
    @args = parse_args!(argv)
    @args.merge!(parse_option_envs())

    unless [:cygwin, :msys, :wsl].include? UnixCompatEnv.compat_env
      raise "You're in an unsupported UNIX compatible environment"
    end

    load_codepage()
    win_cmd, outfiles, proc_env = make_envsync_cmd(@args[:win_cmd])

    Signal.trap(:INT, "SIG_IGN")
    
    if UnixCompatEnv.compat_env == :wsl
      # * Skip winpty, assuming the system's WSL supports ConPTY
      # * Use an absolute path since SWB overwrites PATH with Windows-style PATH in WSL
      pid = Process.spawn(proc_env,
                          UnixCompatEnv.to_compat_path('C:\\Windows\\System32\\cmd.exe'),
                          '/C', win_cmd, :in => 0, :out => 1, :err => 2)
    elsif !STDOUT.isatty
      pid = Process.spawn(proc_env, 'cmd.exe', '/C', win_cmd, :in => 0, :out => 1, :err => 2)
    else
      pid = Process.spawn(prov_env, 'winpty', '--', 'cmd.exe', '/C', win_cmd, :in => 0, :out => 1, :err => 2)
    end

    Signal.trap(:INT) do
      Process.signal("-KILL", pid)
    end

    status = nil
    loop do
      _, status = Process.wait2(pid)
      break if status.exited?
    end
    
    conv_setenv_stmts(outfiles[:env_windump_file], @args[:env_sync_file])
    conv_doskey_stmts(outfiles[:macro_windump_file], @args[:macro_sync_file])
    gen_chdir_cmds(outfiles[:cwd_windump_file], @args[:cwd_sync_file])

    delete_tmpfiles(outfiles)

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
      when "--show-tmpfiles"
        args[:show_tmpfiles] = true
      when "--preserve-dump"
        args[:preserve_dump] = true
      when "--debug"
        args[:preserve_dump] = true
        args[:show_tmpfiles] = true
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
    args[:win_cmd] = argv[3..-1].join(" ")

    args
  end

  def parse_option_envs()
    options = {}
    if ENV["SWB_DEBUG"] == "1"
      options[:show_tmpfiles] = true
      options[:preserve_dump] = true
    end

    options
  end

  def detect_codepage
    if !STDOUT.isatty && UnixCompatEnv.compat_env == :wsl
      # cmd.exe seems to use UTF-8 when Stdout is redirected in WSL.
      # TODO: Is it always fixed?
      return "65001"  # CP65001 is UTF-8
    end

    return ENV['SWB_CODEPAGE_CACHE'] if ENV['SWB_CODEPAGE_CACHE']

    # You cannot detect the codepage by chcp because
    #   1. chcp always retuns 65001 if it's not in a tty
    #   2. you cannot get the output of a windows exe by Ruby's PTY module
    #      for some reason.
    # So, we use powershell instead here.
    posh_cmd = <<-EOS
      Get-WinSystemLocale | Select-Object Name, DisplayName,
                                          @{ n='OEMCP'; e={ $_.TextInfo.OemCodePage } },
                                          @{ n='ACP';   e={ $_.TextInfo.AnsiCodePage } }
    EOS
    posh_res = `powershell.exe "#{posh_cmd.gsub("$", "\\$")}"`
    locale = posh_res.lines.select {|line| !(line =~ /^\s*$/)}[-1].chomp
    ansi_cp = locale.split(" ")[-1]

    ENV['SWB_CODEPAGE_CACHE'] = ansi_cp

    ansi_cp
  end

  def load_codepage
    @codepage = detect_codepage()
    @file_enc_opts = {
       invalid: :replace,
       undef: :replace,
       replace: "?",
       encoding: "CP#{@codepage}:UTF-8"
    }
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

  def reg_exact_match(reg, str)
      m = Regexp.new(reg).match(str)
      return false if m.nil?
      m[0] == str
  end

  def whitelist_block?(envvar_name)
    return false if !ENV["SWB_WHITELIST"]
    ENV["SWB_WHITELIST"].split(":").each do |name_regexp|
      return false if reg_exact_match(name_regexp, envvar_name)
    end
    true
  end

  def blacklist_block?(envvar_name)
    return false if !ENV["SWB_BLACKLIST"]
    ENV["SWB_BLACKLIST"].split(":").each do |name_regexp|
      return true if reg_exact_match(name_regexp, envvar_name)
    end
    false
  end

  def detect_diffcase_vars(var_hash)
    same_names = Hash[]
    var_hash.each do |name, val|
      same_names[name.upcase] ||= []
      same_names[name.upcase].push(name)
    end
    same_names.select! {|name, val| val.length > 1}
    
    same_names
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

    if !(same_names = detect_diffcase_vars(vars.merge(wslenvs))).empty?
      error_mes = <<-EOS
SWB Error:
  You have environment variables the names of which differ only in case.
  SWB cannot preserve and restore them due to case insensitiveness of Windows.
  Please undefine them or add either to SWB_BLACKLIST to prevent ambiguity.
Ambiguous variables:
      EOS
      same_names.each do |_, vals|
	error_mes += "  - " + vals.join(", ") + "\n"
      end
      raise CaseSensitiveVariableError.new(error_mes)
    end

    [vars, env]
  end

  def mk_tmpname(suffix)
    "#{UnixCompatEnv.win_tmp_in_compat}#{SecureRandom.uuid + suffix}"
  end

  def make_envsync_cmd(cmd)
    files = {}

    begin
      wrapper_batch_file = mk_tmpname(".cmd")
      File.write(wrapper_batch_file, "@" + cmd)
      files[:wrapper_batch_file] = wrapper_batch_file

      statements = ["@call " + dq_win_path(UnixCompatEnv.to_win_path(wrapper_batch_file))]

      statements.push("@set SWB_EXITSTATUS=%errorlevel%")
      proc_env = concat_env_init!(statements, files)
      concat_env_dump!(statements, files)
      concat_macro_dump!(statements, files)
      concat_cwd_dump!(statements, files)
      statements.push("@exit %SWB_EXITSTATUS%")

      internal_command_file = mk_tmpname(".cmd")
      File.write(internal_command_file, statements.join("\r\n"))
      files[:internal_command_file] = internal_command_file
      internal_command = "@" + dq_win_path(UnixCompatEnv.to_win_path(internal_command_file))

      [internal_command, files, proc_env]
    rescue CaseSensitiveVariableError => e
      STDERR.puts e.message
      delete_tmpfiles(files)
      exit(1)
    end
  end

  def concat_env_init!(statements, outfiles)
    vars_to_sync, proc_env = prepare_env_vars

    env_init_file = mk_tmpname(".cmd")
    File.write(env_init_file,
	       vars_to_sync.map {|var, val| "@set #{var}=#{val}"}.join("\r\n"),
	       opt=@file_enc_opts)
    outfiles[:env_init_file] = env_init_file

    statements.unshift("@call " + dq_win_path(UnixCompatEnv.to_win_path(env_init_file)))

    proc_env
  end

  def concat_env_dump!(statements, outfiles)
    env_windump_file = mk_tmpname(".env")
    statements.push("@set > #{dq_win_path(UnixCompatEnv.to_win_path(env_windump_file))}")
    outfiles[:env_windump_file] = env_windump_file
  end

  def concat_macro_dump!(statements, outfiles)
    macro_windump_file = mk_tmpname(".doskey")
    #TODO: escape
    statements.push("@doskey /macros > #{dq_win_path(UnixCompatEnv.to_win_path(macro_windump_file))}")
    outfiles[:macro_windump_file] = macro_windump_file
  end

  def concat_cwd_dump!(statements, outfiles)
    cwd_windump_file = mk_tmpname(".cwd")
    #TODO: escape
    winpath = dq_win_path(UnixCompatEnv.to_win_path(cwd_windump_file))
    statements.push("@ cd > #{winpath} & pushd >> #{winpath}")
    outfiles[:cwd_windump_file] = cwd_windump_file
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

  def to_compat_pathlist(path)
    path.split(";")
      .map {|p| UnixCompatEnv.to_compat_path(p)}
      .join(":")
  end

  def conv_setenv_stmts(setenvfile, outfile)
    return if !File.exist?(setenvfile)

    vars = Hash[]
    envs_casemap = Hash[ENV.keys.map {|k| [k.upcase, k]}]
    File.open(outfile, "w") do |f_out|
      File.read(setenvfile, opt=@file_enc_opts).lines.each do |set_stmt|
	var, val = /([^=]*)=(.*)$/.match(set_stmt)[1..2]

        is_var_valid = /^[a-zA-Z_][_0-9a-zA-Z]*$/ =~ var
        next if !is_var_valid
        next if whitelist_block?(var) || blacklist_block?(var)
	vars[var] = val

	if var.upcase == "PATH"
          val = to_compat_pathlist(val)
        end

	var = envs_casemap[var.upcase] || var
        f_out.puts("export #{var}='#{escape_singlequote(val.chomp)}'")
      end
    end

    if !(same_names = detect_diffcase_vars(vars)).empty?
      STDERR.puts <<-EOS
SWB Warning:
  You've synced the environment variables the names of which differ only 
  in case. That means one of the following.
  1. You define a variable in your WSLENV, and your Windows environment
     has another variable the name of which differ only in case.
  2. SWB synced a variable by WSLENV, and your Windows command defined
     another variable the name of which differ only in case from that of
     the variable SWB synced.
     SWB normally syncs variables by initialization script. However, if 
     a variable's value contains special character to be escaped, SWB
     syncs it by WSLENV instead. That is the case here.
     
  To solve this warning, please undefine those variables, or add them, except
  one variable, to SWB_BLACKLIST to prevent ambiguity.
Ambiguous variables:
      EOS
      same_names.each do |_, vals|
	STDERR.puts("  - " + vals.join(", "))
      end
    end

  end

  def conv_doskey_stmts(doskeyfile, outfile)
    return if !File.exist?(doskeyfile)

    File.open(outfile, "w") do |f_out|
      File.open(doskeyfile, opt=@file_enc_opts) do |f_in|
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

  def gen_chdir_cmds(dirs, outfile)
    return if !File.exist?(dirs)

    lines = File.read(dirs, opt=@file_enc_opts).lines.select {|line| !line.empty?}
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

  def log_file_content(file_type, filename)
    STDERR.puts("=== begin: #{file_type} ===\n")
    if File.exist?(filename)
      STDERR.puts("=== - CP#{@codepage}:'#{filename}' ===\n")
      STDERR.puts(File.read(filename, opt=@file_enc_opts))
    else
      STDERR.puts("This file doesn't exist.")
      STDERR.puts("Maybe Windows command terminated by exit command")
    end
    STDERR.puts("=== end: #{file_type} ===\n")
  end

  def delete_tmpfiles(tmpfiles)
    tmpfiles.each do |k, f|
      if @args[:show_tmpfiles]
	log_file_content(k, f)
      end
      if !@args[:preserve_dump]
	File.delete(f) if File.exist?(f)
      end
    end
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
    --show-tmpfiles     Show the contents of the temporary files such as 
                        the environment dump files
    --debug             Enable '--preserve-dump', '--show-tmpfiles' options

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
	
## Several things to keep in mind:

1. SourceWinBat executes the given Windows command in "Batch file mode".

Windows cmd.exe has a few different behaviors in the interactive 
"command line mode" and the "batch file mode". For example, expansion 
result of an empty variable, or variable expansion in for command.
SourceWinBat executes the given command always in the batch file mode.

2. `exit` command prevents SourceWinBat from synciny environment variables.

If you can fix the batch file you run, please replace `exit` with `exit /B`

EOS
  end

end
