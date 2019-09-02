#!/bin/bash

source ./setup_test.bash
tap_tests 4

sw setdoskey.cmd

expected="bar"
[[ $(foo) =~ $expected ]]; tap_okif $?
expected="foo"
[[ $(echo1stparam foo bar) =~ $expected ]]; tap_okif $?
expected="foo bar"
[[ $(echoallparams foo bar) =~ $expected ]]; tap_okif $?
expected="Microsoft Windows"
[[ $(verver) =~ $expected ]]; tap_okif $?

