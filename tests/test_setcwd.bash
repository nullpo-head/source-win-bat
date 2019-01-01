#!/bin/bash

source ./setup_test.bash
tap_tests 2

ec setcwd.cmd

expected="[cC]/Windows/System32/drivers /.*[cC]/Windows .*/[cC]\$"
[[ $(dirs) =~ $expected ]]; tap_okif $? "test if pushd works"
[[ $(pwd) =~ [cC]/Windows/System32/drivers$ ]]; tap_okif $? "test if cd works"
