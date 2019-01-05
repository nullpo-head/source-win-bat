#!/bin/bash

source ./setup_test.bash
tap_tests 6

export jp=日本語
[[ $(sw echo %jp% | strip) = "日本語" ]]; tap_okif $?
sw echo %jp% > /dev/null  # Re-import $jp from Windows
[[ $(echo $jp) = "日本語" ]]; tap_okif $? "Test a varible with Japanese value keeps its value after sw"
sw set jp2=あいうえお > /dev/null
[[ $(echo $jp2) = "あいうえお" ]]; tap_okif $?


tmp="$(to_unix_path "$(sw echo %TEMP% | strip)")/sw_日本語ディレクトリ"
rm -rf "$tmp"
mkdir "$tmp"
win_tmp="$(to_win_path "$tmp")"
sw cd "$win_tmp"
[[ `pwd` = "$tmp" ]]; tap_okif $?
[[ $(sw echo %jp% | strip) = "日本語" ]]; tap_okif $?
[[ $(sw cd | strip) = "$win_tmp" ]]; tap_okif $?
rm -rf "$tmp"
