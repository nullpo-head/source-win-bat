tap_tests () {
  echo 1..$1
}

declare -i tap_test_counter=0
_tap_echo_result () {
  local mes

  tap_test_counter=tap_test_counter+1
  if [[ -n $2 ]]; then
    mes=" - $2"
  else
    mes=""
  fi

  if [[ $1 == 0 ]]; then
    echo ok $tap_test_counter$mes 
  else
    echo not ok $tap_test_counter$mes 
  fi
  
}

tap_ok () {
  _tap_echo_result 0 "$1"
}

tap_notok() {
  _tap_echo_result 1 "$1"
}

tap_okif() {
  _tap_echo_result $1 "$2"
}



