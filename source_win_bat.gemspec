Gem::Specification.new do |s|
  s.name        = 'source_win_bat'
  s.version     = '0.1.0'
  s.date        = '2019-01-03'
  s.summary     = "'source' Windows bat files in your UNIX compatible shell in Windows"
  s.description = <<EOS
sw, or SourceWinBat, is a utility to run Windows batch files from WSL /
MSYS2 / Cygwin and sync environment variables, aliases / doskeys, and
working directories between batch files and their UNIX shell environments.
EOS
  s.authors     = ["Takaya Saeki"]
  s.email       = 'abc.tkys+pub@gmail.com'
  s.files       = `git ls-files`.split("\n")
  s.executables = ["init_sw"]
  s.homepage    = 'http://rubygems.org/gems/source_win_bat'
  s.license     = 'MIT'
end