Gem::Specification.new do |s|
  s.name        = 'source_win_bat'
  s.version     = '0.4.0'
  s.date        = '2019-02-06'
  s.summary     = "'source' Windows bat files in your UNIX compatible shell in Windows"
  s.description = <<EOS
sw, or SourceWinBat, is a utility to run Windows batch files from WSL /
MSYS2 / Cygwin and sync environment variables, doskeys, and working 
directories between batch files and their UNIX shell environments.
EOS
  s.authors     = ["Takaya Saeki"]
  s.email       = 'abc.tkys+pub@gmail.com'
  s.files       = `git ls-files`.split("\n")
  s.executables = ["init_sw"]
  s.homepage    = 'https://github.com/nullpo-head/source-win-bat'
  s.license     = 'MIT'
end
