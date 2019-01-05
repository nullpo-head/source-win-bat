# SourceWinBat - Source a Windows Batch in Bash!

`sw`, or SourceWinBat is a CLI utility to run Windows batch files from WSL/MSYS2/Cygwin,
and sync the shell environments of Bash and the Windows batch files, including
* Environment variables
* Doskeys
* Working directories

By SourceWinBat, you can execute Windows initialization scripts in Bash as if you use `source` 
command for initialization Bash scripts.  
SourceWinBat helps you do your daily Windows work in your favorite UNIX-compatible environment.


## Usage

After initalization, `sw` function is defined in your Bash environment. 
Run your Windows batch files or Windows CLI commands by `sw`.

You can run a Windows batch file
```console
$ cat winbat.bat
@echo off
set ENV1=bar!  ; Environment variables will be synced
echo foo!      ; Execute Windows echo commands
ver            ; Execute Windows ver command, which outputs the OS version
$ sw winbat.bat  # winbat.bat is executed
foo!

Microsoft Windows [Version 10.0.17763.195]
$ echo $ENV1     # ENV1 is synced!
bar!
```

You can also run a Windows command directly.
```console
$ sw ver

Microsoft Windows [Version 10.0.17763.195]
```

## Examples

### Environment Syncing

SourceWinBat syncs environment variables, doskeys, and working directories of the
Bash environment with those of the Windows cmd environment where a batch file is executed.

#### 1. Environment variables
A batch file can see the exported environment variables of Bash.  
Conversely, Bash has the environment variables defined by the batch file and Windows system
after the batch file is executed. `PATH` is properly converted.

```console
$ export UNIXENV="An UNIX environment variable is imported!"
$ cat syncenv.bat
echo %UNIXENV%
set WINENV=A Windows environment variable is imported!
set PATH=C:\any\path;%PATH%
$ sw syncenv.bat  # syncenv sees the value of $UNIXENV, which we defined in Bash!
An UNIX environment variable is imported!
$ echo $WINENV    # Now we can see $WINENV, which is set in synenv.bat!!
A Windows environment variable is imported!
$ echo $PATH      # PATH is converted to the path of WSL
/mnt/c/any/path:/usr/bin/:/bin:(other paths go on...)
```

#### 2. Doskeys
SourceWinBat enables Bash to import doskeys from Windows Batch files as Bash functions.

```console
$ cat syncdoskey.bat
doskey echo1stparam=echo $1
doskey echoallparams=echo $*
doskey verver=ver
$ sw syncdoskey.bat
$ echo1stparam 1st 2nd 3rd  # echo1stparam is imported!
1st
$ echo1stparam %OS%         # "echo $1" is executed by cmd.exe, so %OS% is expanded
Windows_NT
$ echoallparams 1st 2nd 3rd
1st 2nd 3rd
$ verver

Microsoft Windows [Version 10.0.17763.195]
```

#### 3. Working directories
As `source` of built-in Bash command syncs working directories, SourceWinBat also syncs them.

```console
$ cd ~
$ cat syncwd.bat
pushd C:\Windows
pushd C:\Windows\system32
cd C:\Windows\system32\drivers
$ sw syncwd.bat
$ pwd   # The current directory of Bash is changed
/mnt/c/Windows/System32/drivers
$ dirs  # The directory stack is synced with that of the batch file
/mnt/c/Windows/System32/ /mnt/c/Windows /home/nullpo
```

## Installation

SourceWinBat is written in Ruby. You can install it by Gem.
```console
# gem install source_win_bat
```

Execute the line below to add the initialization in your `.bashrc`.
```console
$ echo 'eval "$(init_sw)"' >> ~/.bashrc
```
After restarting Bash, you will be able to use `sw` in your shell.  
Currently, SourceWinBat supports only Bash as a shell.

## Requirements

### 1. For WSL users

October update or later is required. SourceWinBat requires ConPTY API.

### 2. For MSYS2 and Cygwin users

If you use MSYS2 and Cygwin with SourceWinBat, `winpty` command is required.
Clone it from its GitHub repository and build it from the source. The repository is https://github.com/rprichard/winpty .  
For MSYS2 users, DO NOT install `winpty` via `pacman`. As of 2019/01/03, Pacman installs the latest released version, 0.4.3-1, but this version does not work anymore.

## TODOs

* Support non-ascii characters in Cygwin and MSYS2. SourceWinBat already supports them in WSL.
* Support shell operators in doskey such as pipe.
