#!/bin/bash

source ./setup_test.bash
if [[ $(uname) =~ CYGWIN ]]; then
  set -o igncr # Workaround for the problem that '\r' is inserted after each line in Cygwin
fi
tap_tests 4

ec setdoskey.cmd

expected="bar \r?"
[[ $(foo) =~ $expected ]]; tap_okif $?
expected="foo \r?"
[[ $(echo1stparam foo bar) =~ $expected ]]; tap_okif $?
expected="foo bar \r?"
[[ $(echoallparams foo bar) =~ $expected ]]; tap_okif $?
expected="Microsoft Windows"
[[ $(verver) =~ $expected ]]; tap_okif $?

