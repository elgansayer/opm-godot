#!/usr/bin/env bash
set -euo pipefail

# Headless smoke test
cd "$(dirname "$0")/project"

godot --headless --quit-after 5000
