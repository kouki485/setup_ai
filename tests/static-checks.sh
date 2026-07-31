#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n mac/mac-setup.sh
bash -n windows/wsl-setup.sh

if rg -n \
    '(?i)invoke-expression|\[scriptblock\]::create|curl[^\n]*\|[^\n]*(bash|sh)|/tmp/(supabase|githubcli)|get\.scoop\.sh' \
    mac windows; then
    echo "危険なリモート実行または固定一時パスを検出しました" >&2
    exit 1
fi

if rg -n 'npm[^\n]*install[^\n]*[[:space:]]vercel(@|[[:space:]]|$)' mac windows; then
    echo "脆弱な依存関係を含む Node.js 版 Vercel CLI の導入を検出しました" >&2
    exit 1
fi

for script in mac/mac-setup.sh windows/setup.ps1 windows/wsl-setup.sh; do
    if ! rg -q '@vercel/vc-native@.*VercelNativeVersion|@vercel/vc-native@.*VERCEL_NATIVE_VERSION' "$script"; then
        echo "$script が固定した Vercel ネイティブ版を使っていません" >&2
        exit 1
    fi
done
for script in mac/mac-setup.sh windows/wsl-setup.sh; do
    if ! rg -q '^VERCEL_NATIVE_VERSION="58\.4\.0"$' "$script"; then
        echo "$script の Vercel ネイティブ版固定値が一致しません" >&2
        exit 1
    fi
done
if ! rg -q '^\$VercelNativeVersion = "58\.4\.0"\r?$' windows/setup.ps1; then
    echo "windows/setup.ps1 の Vercel ネイティブ版固定値が一致しません" >&2
    exit 1
fi

if rg -n 'npm[^\n]*install' mac windows | rg -v -- '--ignore-scripts'; then
    echo "ライフサイクルスクリプトを許可した npm install を検出しました" >&2
    exit 1
fi

ps1_prefix="$(od -An -tx1 -N3 windows/setup.ps1 | tr -d ' \n')"
if [ "$ps1_prefix" != "efbbbf" ]; then
    echo "windows/setup.ps1 の UTF-8 BOM がありません" >&2
    exit 1
fi
if ! perl -0777 -e '$d = <>; exit(($d !~ /(?<!\r)\n/) ? 0 : 1)' windows/setup.ps1; then
    echo "windows/setup.ps1 に CRLF 以外の改行が含まれています" >&2
    exit 1
fi
if ! perl -0777 -e '$d = <>; exit(($d !~ /[^\x00-\x7f]/ && $d !~ /(?<!\r)\n/) ? 0 : 1)' windows/install.bat; then
    echo "windows/install.bat は ASCII・CRLF ではありません" >&2
    exit 1
fi

expected_hash="$(
    sed -n 's/^set "EXPECTED_SHA256=\([0-9A-Fa-f]*\)".*/\1/p' windows/install.bat \
        | tr '[:upper:]' '[:lower:]'
)"
actual_hash="$(shasum -a 256 windows/setup.ps1 | awk '{print $1}')"
if [ -z "$expected_hash" ] || [ "$expected_hash" != "$actual_hash" ]; then
    echo "install.bat の EXPECTED_SHA256 が setup.ps1 と一致しません" >&2
    exit 1
fi

echo "static checks: OK"
