@echo off

doskey foo=echo bar
doskey echo1stparam=echo $1
doskey echoallparams=echo $*
doskey verver=ver
REM other special characters are not supported currently
