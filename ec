#!/bin/bash

export PATH
tmp_env=$(mktemp)
tmp_macro=$(mktemp)
ec.rb "${tmp_env}" "${tmp_macro}" $@
source ${tmp_env}
source ${tmp_macro}
rm ${tmp_env} ${tmp_macro}
