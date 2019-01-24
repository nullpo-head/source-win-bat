#!/bin/bash

eval "$("$(dirname "$(realpath "${BASH_SOURCE:-0}")")/../bin/init_sw")"
source ./tap.bash

to_unix_path () {
  if [[ $(uname) = Linux ]]; then
    wslpath "$@"
  else
    cygpath "$@"
  fi
}

to_win_path () {
  if [[ $(uname) = Linux ]]; then
    wslpath -w "$@"
  else
    cygpath -w "$@"
  fi
}

strip () {
  sed -e 's/[ \r]*$//'
}
