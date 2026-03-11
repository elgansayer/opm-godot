#!/bin/sh
printf '\033c\033]0;%s\a' OpenMoHAA Test
base_path="$(dirname "$(realpath "$0")")"
"$base_path/mohaa.x86_64" "$@"
