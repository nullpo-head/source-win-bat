#!/bin/bash

source ./setup_test.bash
tap_tests 9

export SWB_BLACKLIST="SWB_FOO:SWB_BLACK_.*:SWB_BAR"
[[ -z "$(sw set SWB_FOO=FOO; echo $SWB_FOO)" ]]; tap_okif $?
[[ -z "$(sw set SWB_BLACK_FOO=FOO; echo $SWB_BLACK_FOO)" ]]; tap_okif $?
[[ -z "$(sw set SWB_BAR=BAR; echo $SWB_BAR)" ]]; tap_okif $?
[[ $(sw set SWB_BAZ=BAZ; echo $SWB_BAZ) = BAZ ]]; tap_okif $?


export SWB_WHITELIST="SWB_W1:SWB_WHITE_.*:SWB_W2"
export SWB_W1="foo"
export SWB_WHITE_FOO="foo foo"
export SWB_W2="bar"
[[ $(sw set SWB_W1=foo; echo $SWB_W1) = foo ]]; tap_okif $?
[[ $(sw set SWB_WHITE_FOO=foo; echo $SWB_WHITE_FOO) = foo ]]; tap_okif $?
[[ $(sw set SWB_W2=bar; echo $SWB_W2) = bar ]]; tap_okif $?
[[ -z "$(sw set SWB_W3=baz; echo $SWB_W3)" ]]; tap_okif $?

export SWB_W1=
export SWB_BLACKLIST="${SWB_BLACLIST}:SWB_W1"
[[ -z "$(sw set SWB_W1=W1; echo $SWB_W1)" ]]; tap_okif $?
