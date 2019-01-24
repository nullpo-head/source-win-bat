#!/bin/bash

source ./setup_test.bash
tap_tests 3

sw exit 0
[[ $? = 0 ]]; tap_okif $? "Test exitcode is propagated 1"

sw exit 42
[[ $? = 42 ]]; tap_okif $? "Test exitcode is propagated 2"

sw exit_42.cmd
[[ $? = 42 ]]; tap_okif $? "Test exitcode is propagated 3"
