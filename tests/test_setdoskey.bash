#!/bin/bash

source ./setup_test.bash
set -o igncr # Workaround for the problem that '\r' is inserted after each line in Cygwin
tap_tests 4

ec setdoskey.cmd

[[ $(foo) = "bar " ]]; tap_okif $?
[[ $(echo1stparam foo bar) = "foo " ]]; tap_okif $?
[[ $(echoallparams foo bar) = "foo bar " ]]; tap_okif $?
expected="Microsoft Windows"
[[ $(verver) =~ $expected ]]; tap_okif $?

