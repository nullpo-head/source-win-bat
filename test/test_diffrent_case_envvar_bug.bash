#!/bin/bash

source ./setup_test.bash
tap_tests 9

export DIFFCASE1=FOO
[[ $(sw echo %DiffCase1%) =~ FOO ]]; tap_okif $? "Test a variable of different cases can be read in Windows 1"
export DiffCase2=FOO
[[ $(sw echo %DIFFCASE2%) =~ FOO ]]; tap_okif $? "Test a variable of different cases can be read in Windows 2"
[[ -z "$DIFFCASE3" ]]; tap_okif $? "Test a variable is undefined 1"
[[ -z "$DiffCase3" ]]; tap_okif $? "Test a variable is undefined 2"

sw set_diff_case_env.cmd

[[ "$DIFFCASE1" =~ BAR ]]; tap_okif $? "Test a variable of different cases is modified in Windows 1"
[[ -z "$DiffCase1" ]]; tap_okif $? "Test a variable of different cases merges"
[[ "$DiffCase2" =~ BAR ]]; tap_okif $? "Test a variable of different cases is modified in Windows 2"
[[ "$DiffCase3" =~ BAR ]]; tap_okif $? "Test a variable of different cases is modified in Windows 3"
[[ -z "$DIFFCASE3" ]]; tap_okif $? "Test a variable is undefined 3"
