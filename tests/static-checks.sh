#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n mac/mac-setup.sh
bash -n mac/setup-obsidian-mcp.sh
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

for script in mac/mac-setup.sh windows/wsl-setup.sh; do
    if ! rg -q 'https://hermes-agent\.nousresearch\.com/install\.sh' "$script" \
        || ! rg -q 'bash -n "\$HERMES_INSTALLER"' "$script" \
        || ! rg -q -- '--skip-setup --non-interactive' "$script"; then
        echo "$script の Hermes Agent 任意導入が安全な公式手順になっていません" >&2
        exit 1
    fi
done
if ! rg -q 'https://hermes-agent\.nousresearch\.com/install\.ps1' windows/setup.ps1 \
    || ! rg -q '"hermes" @\("-SkipSetup", "-NonInteractive"\)' windows/setup.ps1; then
    echo "windows/setup.ps1 の Hermes Agent 任意導入が安全な公式手順になっていません" >&2
    exit 1
fi
for script in mac/mac-setup.sh windows/setup.ps1 windows/wsl-setup.sh; do
    if ! rg -q 'Hermes Agent をインストールしますか[?？] \(y/N\)' "$script" \
        || ! rg -q 'hermes : 未導入（任意）' "$script"; then
        echo "$script の Hermes Agent が既定スキップの任意選択になっていません" >&2
        exit 1
    fi
done

if rg -n '(mcp-remote|obsidian-mcp-server|@modelcontextprotocol/server)' \
    mac/setup-obsidian-mcp.sh windows/setup-obsidian-mcp.ps1; then
    echo "Obsidian プラグイン内蔵 MCP 以外のプロキシ導入を検出しました" >&2
    exit 1
fi

for script in mac/mac-setup.sh windows/setup.ps1; do
    if ! rg -q 'Obsidian MCP をインストールしますか[?？] \(y/N\)' "$script" \
        || ! rg -q 'Obsidian MCP : 未導入（任意）' "$script"; then
        echo "$script の Obsidian MCP が既定スキップの任意選択になっていません" >&2
        exit 1
    fi
done
if ! rg -q 'brew_install --cask obsidian' mac/mac-setup.sh \
    || ! rg -q 'winget install --id Obsidian\.Obsidian' windows/setup.ps1; then
    echo "Obsidian の公式パッケージ導入設定が見つかりません" >&2
    exit 1
fi

mac_helper_hash="$(
    sed -n 's/^[[:space:]]*OBSIDIAN_HELPER_SHA256="\([0-9a-f]*\)".*/\1/p' \
        mac/mac-setup.sh
)"
actual_mac_helper_hash="$(shasum -a 256 mac/setup-obsidian-mcp.sh | awk '{print $1}')"
if [ -z "$mac_helper_hash" ] || [ "$mac_helper_hash" != "$actual_mac_helper_hash" ]; then
    echo "mac/mac-setup.sh の Obsidian MCP ヘルパー SHA-256 が一致しません" >&2
    exit 1
fi

windows_helper_hash="$(
    sed -n 's/^\$ObsidianHelperSha256 = "\([0-9a-f]*\)"\r*$/\1/p' \
        windows/setup.ps1
)"
actual_windows_helper_hash="$(
    shasum -a 256 windows/setup-obsidian-mcp.ps1 | awk '{print $1}'
)"
if [ -z "$windows_helper_hash" ] \
    || [ "$windows_helper_hash" != "$actual_windows_helper_hash" ]; then
    echo "windows/setup.ps1 の Obsidian MCP ヘルパー SHA-256 が一致しません" >&2
    exit 1
fi

for helper in mac/setup-obsidian-mcp.sh windows/setup-obsidian-mcp.ps1; do
    if ! rg -q 'http://127\.0\.0\.1.*?/mcp/' "$helper" \
        || ! rg -q 'SETUP_AI_OBSIDIAN_API_KEY' "$helper" \
        || ! rg -q 'MCP_OBSIDIAN_API_KEY' "$helper" \
        || ! rg -q 'bearer-token-env-var.*SETUP_AI_OBSIDIAN_API_KEY' "$helper"; then
        echo "$helper のループバック制限または秘密情報参照が不正です" >&2
        exit 1
    fi
done
if ! rg -q '\^\[A-Za-z0-9.*\{32,256\}' mac/setup-obsidian-mcp.sh \
    || ! rg -q '\^\[A-Za-z0-9.*\{32,256\}' windows/setup-obsidian-mcp.ps1 \
    || ! rg -q 'curl -q --config -' mac/setup-obsidian-mcp.sh; then
    echo "Obsidian API Key の検証または安全な送信処理が見つかりません" >&2
    exit 1
fi
if ! rg -q -- "--noproxy '\\*'.*--proto '=http'.*--max-redirs 0" \
        mac/setup-obsidian-mcp.sh \
    || ! rg -q '\$handler\.UseProxy = \$false' windows/setup-obsidian-mcp.ps1 \
    || ! rg -q '\$handler\.AllowAutoRedirect = \$false' \
        windows/setup-obsidian-mcp.ps1; then
    echo "Obsidian API Key のプロキシ・リダイレクト防止設定が見つかりません" >&2
    exit 1
fi

ps1_prefix="$(od -An -tx1 -N3 windows/setup.ps1 | tr -d ' \n')"
if [ "$ps1_prefix" != "efbbbf" ]; then
    echo "windows/setup.ps1 の UTF-8 BOM がありません" >&2
    exit 1
fi
obsidian_ps1_prefix="$(
    od -An -tx1 -N3 windows/setup-obsidian-mcp.ps1 | tr -d ' \n'
)"
if [ "$obsidian_ps1_prefix" != "efbbbf" ]; then
    echo "windows/setup-obsidian-mcp.ps1 の UTF-8 BOM がありません" >&2
    exit 1
fi
if ! perl -0777 -e '$d = <>; exit(($d !~ /(?<!\r)\n/) ? 0 : 1)' \
    windows/setup-obsidian-mcp.ps1; then
    echo "windows/setup-obsidian-mcp.ps1 に CRLF 以外の改行が含まれています" >&2
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

wsl_step_line="$(rg -n -m 1 '^Write-Step "WSL2 の状態を確認"\r?$' windows/setup.ps1 | cut -d: -f1)"
git_step_line="$(rg -n -m 1 '^Write-Step "Git for Windows"\r?$' windows/setup.ps1 | cut -d: -f1)"
result_step_line="$(rg -n -m 1 '^Write-Step "インストール結果"\r?$' windows/setup.ps1 | cut -d: -f1)"
restart_prompt_line="$(rg -n -m 1 'Read-Host "今すぐ再起動しますか\? \(y/N\)"' windows/setup.ps1 | cut -d: -f1)"
obsidian_step_line="$(rg -n -m 1 '^Write-Step "Obsidian MCP（任意）"\r?$' windows/setup.ps1 | cut -d: -f1)"
codex_step_line="$(rg -n -m 1 '^Write-Step "Codex CLI"\r?$' windows/setup.ps1 | cut -d: -f1)"
if [ "$wsl_step_line" -ge "$git_step_line" ] \
    || [ "$codex_step_line" -ge "$obsidian_step_line" ] \
    || [ "$obsidian_step_line" -ge "$result_step_line" ] \
    || [ "$restart_prompt_line" -le "$result_step_line" ]; then
    echo "Windows の導入順が不正です（WSL後も続行し、検証後に再起動を案内する必要があります）" >&2
    exit 1
fi
if sed -n "${wsl_step_line},${git_step_line}p" windows/setup.ps1 | rg -q '^[[:space:]]*exit 0\r?$'; then
    echo "WSL 初回導入後に Windows 向けツールを入れず終了しています" >&2
    exit 1
fi

echo "static checks: OK"
