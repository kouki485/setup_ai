#!/bin/bash
# ============================================================
# Start_Mac.command - local launcher for the extracted package
#
# NOTE: Double-clicking a downloaded .command is often blocked by
# macOS Gatekeeper. Prefer opening Start.html, or right-click → Open.
# ============================================================

set -u

cd "$(dirname "$0")" || exit 1
ROOT="$(pwd)"
SETUP="$ROOT/mac/mac-setup.sh"

printf '\n============================================================\n'
printf ' AI 開発環境セットアップ（Mac）\n'
printf '============================================================\n\n'

if [ ! -f "$SETUP" ]; then
    printf '[ERROR] mac/mac-setup.sh が見つかりません。\n'
    printf '        ZIP をフォルダごと展開してから、その中の Start.html を開いてください。\n\n'
    read -r -p '終了するには Enter を押してください...' _
    exit 1
fi

# Clear download quarantine so nested tools are less likely to be blocked.
if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$ROOT" 2>/dev/null || true
fi

chmod +x "$SETUP" 2>/dev/null || true
bash "$SETUP"
EXIT_CODE=$?

printf '\n============================================================\n'
if [ "$EXIT_CODE" -eq 0 ]; then
    printf ' 完了しました。上の表示を確認してください。\n'
else
    printf ' 終了コード %s で終わりました。\n' "$EXIT_CODE"
    printf ' 止まった場合は同フォルダの Start.html をブラウザで開いてください。\n'
fi
printf '============================================================\n'
printf '\n実行ログ: デスクトップの ai-setup-log.txt\n\n'
read -r -p '終了するには Enter を押してください...' _
exit "$EXIT_CODE"
