#!/usr/bin/env bash
# Convenience wrapper — delegates to scripts/build-native.sh
exec "$(dirname "$0")/scripts/build-native.sh" "$@"

