#!/bin/bash

source ./setup_test.bash
tap_tests 1

unset WSLENV
if sw echo test > /dev/null; then tap_ok; else tap_notok; fi
