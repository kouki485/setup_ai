#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n mac/mac-setup.sh
bash -n windows/wsl-setup.sh
bash -n Start_Mac.command

if ! perl -0777 -e '$d = <>; exit(($d !~ /[^\x00-\x7f]/ && $d !~ /(?<!\r)\n/) ? 0 : 1)' Start_Windows.bat; then
    echo "Start_Windows.bat は ASCII・CRLF ではありません" >&2
    exit 1
fi
if ! rg -q 'windows\\setup\.ps1' Start_Windows.bat; then
    echo "Start_Windows.bat が同梱の setup.ps1 を参照していません" >&2
    exit 1
fi
if ! rg -q 'mac/mac-setup\.sh' Start_Mac.command; then
    echo "Start_Mac.command が同梱の mac-setup.sh を参照していません" >&2
    exit 1
fi
if [ ! -f README_JA.txt ]; then
    echo "README_JA.txt がありません" >&2
    exit 1
fi
if [ ! -x scripts/build-dist.sh ]; then
    echo "scripts/build-dist.sh が実行可能ではありません" >&2
    exit 1
fi

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

# 今回の配布対象外ツールが混入していないことを確認する
if rg -n -i '(codex|hermes|obsidian)' mac/mac-setup.sh windows/setup.ps1 windows/wsl-setup.sh README.md; then
    echo "配布対象外の Codex / Hermes / Obsidian への参照が残っています" >&2
    exit 1
fi
if [ -e mac/setup-obsidian-mcp.sh ] \
    || [ -e windows/setup-obsidian-mcp.ps1 ] \
    || [ -e tests/windows-obsidian-helper-harness.ps1 ]; then
    echo "Obsidian MCP ヘルパーが残っています" >&2
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
    echo "  expected: $expected_hash" >&2
    echo "  actual:   $actual_hash" >&2
    exit 1
fi

wsl_step_line="$(rg -n -m 1 '^Write-Step "WSL2 の状態を確認"\r?$' windows/setup.ps1 | cut -d: -f1)"
git_step_line="$(rg -n -m 1 '^Write-Step "Git for Windows"\r?$' windows/setup.ps1 | cut -d: -f1)"
result_step_line="$(rg -n -m 1 '^Write-Step "インストール結果"\r?$' windows/setup.ps1 | cut -d: -f1)"
restart_prompt_line="$(rg -n -m 1 'Read-Host "今すぐ再起動しますか\? \(y/N\)"' windows/setup.ps1 | cut -d: -f1)"
claude_desktop_line="$(rg -n -m 1 '^Write-Step "Claude Desktop"\r?$' windows/setup.ps1 | cut -d: -f1)"
if [ -z "$wsl_step_line" ] || [ -z "$git_step_line" ] \
    || [ -z "$result_step_line" ] || [ -z "$restart_prompt_line" ] \
    || [ -z "$claude_desktop_line" ]; then
    echo "Windows の必須ステップが見つかりません" >&2
    exit 1
fi
if [ "$wsl_step_line" -ge "$git_step_line" ] \
    || [ "$claude_desktop_line" -ge "$result_step_line" ] \
    || [ "$restart_prompt_line" -le "$result_step_line" ]; then
    echo "Windows の導入順が不正です（WSL後も続行し、検証後に再起動を案内する必要があります）" >&2
    exit 1
fi
if sed -n "${wsl_step_line},${git_step_line}p" windows/setup.ps1 | rg -q '^[[:space:]]*exit 0\r?$'; then
    echo "WSL 初回導入後に Windows 向けツールを入れず終了しています" >&2
    exit 1
fi

echo "static checks: OK"
