#!/bin/bash

export PATH
tmp_env="$(mktemp)"
tmp_macro="$(mktemp)"
tmp_cwd="$(mktemp)"
ec.rb "${tmp_env}" "${tmp_macro}" "${tmp_cwd}" "$*"
if [[ -e "${tmp_env}" ]]; then
    source "${tmp_env}"
fi
if [[ -e "${tmp_macro}" ]]; then
    source "${tmp_macro}"
fi
if [[ -e "${tmp_cwd}" ]]; then
    source "${tmp_cwd}"
fi
rm -f "${tmp_env}" "${tmp_macro}" "${tmp_cwd}"
