#!/bin/bash

eval "$("$(dirname "$(realpath "${BASH_SOURCE:-0}")")/../bin/init_sw")"
source ./tap.bash
