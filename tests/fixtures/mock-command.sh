#!/usr/bin/env bash

name="$(basename "$0")"

case "$name" in
    uname)
        case "${1:-}" in
            -s) echo "Darwin" ;;
            -m) echo "arm64" ;;
            *) echo "Darwin" ;;
        esac
        ;;
    sw_vers)
        echo "14.7"
        ;;
    xcode-select)
        echo "/Library/Developer/CommandLineTools"
        ;;
    brew)
        case "${1:-}" in
            --version) echo "Homebrew 4.6.0" ;;
            --prefix) echo "/tmp/mockbrew" ;;
            shellenv) echo ':' ;;
            list)
                case "${3:-}" in
                    claude) test -d "/Applications/Claude.app" ;;
                    obsidian) test -d "/Applications/Obsidian.app" ;;
                    *) exit 1 ;;
                esac
                ;;
            install)
                if [ "${2:-}" = "--cask" ] && [ "${3:-}" = "obsidian" ]; then
                    mkdir -p "/Applications/Obsidian.app"
                fi
                ;;
            *) ;;
        esac
        ;;
    curl)
        destination=""
        url=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -o)
                    shift
                    destination="${1:-}"
                    ;;
                http://*|https://*)
                    url="$1"
                    ;;
            esac
            shift
        done
        case "$url" in
            https://raw.githubusercontent.com/kouki485/setup_ai/main/mac/setup-obsidian-mcp.sh)
                cp /workspace/mac/setup-obsidian-mcp.sh "$destination"
                ;;
            *)
                echo "unexpected mock curl URL: $url" >&2
                exit 1
                ;;
        esac
        ;;
    shasum)
        if [ "${1:-}" = "-a" ] && [ "${2:-}" = "256" ]; then
            shift 2
        fi
        exec sha256sum "$@"
        ;;
    git) echo "git version 2.47.0" ;;
    node) echo "v24.6.0" ;;
    npm) echo "11.5.1" ;;
    gh) echo "gh version 2.75.0" ;;
    vercel) echo "Vercel CLI 58.4.0" ;;
    supabase) echo "2.45.0" ;;
    claude) echo "2.1.220 (Claude Code)" ;;
    codex) echo "codex-cli 0.120.0" ;;
    *)
        echo "unexpected mock command: $name" >&2
        exit 1
        ;;
esac
