#!/usr/bin/env bash
# Convenience wrapper — delegates to scripts/test.sh
exec "$(dirname "$0")/scripts/test.sh" "$@"
