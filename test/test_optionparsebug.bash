#!/bin/bash

source ./setup_test.bash
tap_tests 1

expected="^test-test \r?"
[[ $(sw "echo test-test") =~ $expected ]]; tap_okif $? "Test the bug is fixed that sw misunderstoods hyphens in a commad as an option"
