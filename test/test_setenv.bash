#!/bin/bash

source ./setup_test.bash
tap_tests 5

sw setenv.cmd

[[ "$WINENV1" = FOO ]]; tap_okif $? "Test a variable is imported from a bat file 1"
[[ "$WINENV2" = BAR ]]; tap_okif $? "Test a variable is imported from a bat file 2"
[[ "$PATH" =~ ^/[^:]*[cC]/?: ]]; tap_okif $? "Test PATH is imported from a bat file and converted to UNIX-style"
[[ $(sw echo %WINENV1%) =~ FOO ]]; tap_okif $? "Test a variable is exported to a bat file 1"
export UNIXENV1=BUZ
[[ $(sw echo %UNIXENV1%) =~ BUZ ]]; tap_okif $? "Test a variable is exported to a bat file 2"
