#!/usr/bin/env bash
# Convenience wrapper — delegates to scripts/build-web.sh
exec "$(dirname "$0")/scripts/build-web.sh" "$@"

