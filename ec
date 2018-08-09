#!/bin/bash

export PATH
tmp_env="$(mktemp)"
tmp_macro="$(mktemp)"
tmp_cwd="$(mktemp)"
ec.rb "${tmp_env}" "${tmp_macro}" "${tmp_cwd}" $@
source "${tmp_env}"
source "${tmp_macro}"
source "${tmp_cwd}"
rm "${tmp_env}" "${tmp_macro}" "${tmp_cwd}"
