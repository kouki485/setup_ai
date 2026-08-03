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
                    *) exit 1 ;;
                esac
                ;;
            install) ;;
            *) ;;
        esac
        ;;
    git) echo "git version 2.47.0" ;;
    node) echo "v24.6.0" ;;
    npm) echo "11.5.1" ;;
    gh) echo "gh version 2.75.0" ;;
    vercel) echo "Vercel CLI 58.4.0" ;;
    supabase) echo "2.45.0" ;;
    claude) echo "2.1.220 (Claude Code)" ;;
    *)
        echo "unexpected mock command: $name" >&2
        exit 1
        ;;
esac
