#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/project"

usage() {
    echo "Usage: ./launch.sh <platform> [engine args...]"
    echo ""
    echo "Platforms:"
    echo "  linux       Run natively via Godot editor (default)"
    echo "  web         Start local Docker stack (nginx + relay)"
    echo ""
    echo "Engine args are passed directly to the engine as Quake-style"
    echo "+commands. Wrap multi-word commands in quotes."
    echo ""
    echo "Examples:"
    echo "  ./launch.sh linux"
    echo "  ./launch.sh linux \"+set cheats 1\""
    echo "  ./launch.sh linux --dedicated --map=dm/mohdm1"
    echo "  ./launch.sh linux \"+set com_target_game 2\" --map=dm/mohdm1"
    echo "  ./launch.sh web"
    echo "  ./launch.sh web \"+set com_target_game 1\""
    echo ""
    echo "Flags (linux only, passed before -- to Godot):"
    echo "  --dedicated   Launch as dedicated server"
    echo "  --client      Force client mode"
    echo "  --map=<name>  Startup map override"
    echo "  --exec=<cfg>  Exec config at startup"
    echo "  --server      Shorthand for --exec=server.cfg"
    echo "  --dev/--nodev Toggle developer mode"
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

PLATFORM="$1"
shift

case "$PLATFORM" in
    linux)
        # All remaining args go after -- so Godot forwards them to Main.gd
        cd "$PROJECT_DIR"
        exec godot -- "$@"
        ;;
    web)
        # Build URL query string from +set / +command args
        QUERY=""
        while [[ $# -gt 0 ]]; do
            arg="$1"
            shift
            # Handle +set <cvar> <value>
            if [[ "$arg" == "+set" ]] && [[ $# -ge 2 ]]; then
                cvar="$1"; shift
                val="$1"; shift
                if [[ -n "$QUERY" ]]; then QUERY+="&"; fi
                QUERY+="${cvar}=${val}"
            # Handle +connect <ip>
            elif [[ "$arg" == "+connect" ]] && [[ $# -ge 1 ]]; then
                val="$1"; shift
                if [[ -n "$QUERY" ]]; then QUERY+="&"; fi
                QUERY+="connect=${val}"
            # Handle +map <name>
            elif [[ "$arg" == "+map" ]] && [[ $# -ge 1 ]]; then
                val="$1"; shift
                if [[ -n "$QUERY" ]]; then QUERY+="&"; fi
                QUERY+="map=${val}"
            # Handle +devmap <name>
            elif [[ "$arg" == "+devmap" ]] && [[ $# -ge 1 ]]; then
                val="$1"; shift
                if [[ -n "$QUERY" ]]; then QUERY+="&"; fi
                QUERY+="map=${val}"
            # Handle +exec <cfg>
            elif [[ "$arg" == "+exec" ]] && [[ $# -ge 1 ]]; then
                val="$1"; shift
                if [[ -n "$QUERY" ]]; then QUERY+="&"; fi
                QUERY+="exec=${val}"
            # Handle --dedicated
            elif [[ "$arg" == "--dedicated" ]]; then
                if [[ -n "$QUERY" ]]; then QUERY+="&"; fi
                QUERY+="dedicated=1"
            # Handle --server
            elif [[ "$arg" == "--server" ]]; then
                if [[ -n "$QUERY" ]]; then QUERY+="&"; fi
                QUERY+="server=1"
            # Handle --map=<name>
            elif [[ "$arg" == --map=* ]]; then
                val="${arg#--map=}"
                if [[ -n "$QUERY" ]]; then QUERY+="&"; fi
                QUERY+="map=${val}"
            # Handle --exec=<cfg>
            elif [[ "$arg" == --exec=* ]]; then
                val="${arg#--exec=}"
                if [[ -n "$QUERY" ]]; then QUERY+="&"; fi
                QUERY+="exec=${val}"
            else
                echo "Warning: unrecognised web arg '$arg' (ignored)" >&2
            fi
        done

        # Ensure Docker stack is running
        cd "$SCRIPT_DIR"
        if ! docker compose ps --status running 2>/dev/null | grep -q nginx; then
            echo "Starting Docker stack..."
            docker compose up -d
        fi

        URL="http://localhost:8086/mohaa.html"
        if [[ -n "$QUERY" ]]; then
            URL+="?${QUERY}"
        fi

        echo "Opening: $URL"
        xdg-open "$URL" 2>/dev/null || open "$URL" 2>/dev/null || echo "Open in browser: $URL"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown platform: $PLATFORM" >&2
        usage
        exit 1
        ;;
esac
