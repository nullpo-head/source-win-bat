#!/bin/bash

export PATH
tmp_env="$(mktemp)"
tmp_macro="$(mktemp)"
tmp_cwd="$(mktemp)"
ruby -W0 "`which ec.rb`" "${tmp_env}" "${tmp_macro}" "${tmp_cwd}" "$*"
if [[ -e "${tmp_env}" ]]; then
    source "${tmp_env}"
fi
if [[ -e "${tmp_macro}" ]]; then
    source "${tmp_macro}"
fi
if [[ -e "${tmp_cwd}" ]]; then
    source "${tmp_cwd}"
fi

ruby -e "begin; File.delete('${tmp_env}', '${tmp_macro}', '${tmp_cwd}'); rescue Errno::ENOENT; end"
