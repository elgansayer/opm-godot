#!/usr/bin/env bash
# Convenience wrapper — delegates to scripts/release.sh
exec "$(dirname "$0")/scripts/release.sh" "$@"
