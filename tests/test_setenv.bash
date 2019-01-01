#!/bin/bash

source ./setup_test.bash
tap_tests 3

ec setenv.cmd

[[ "$WINENV1" = FOO ]]; tap_okif $?
[[ "$WINENV2" = BAR ]]; tap_okif $?
[[ "$PATH" =~ ^/[^:]*[cC]/?: ]]; tap_okif $?
