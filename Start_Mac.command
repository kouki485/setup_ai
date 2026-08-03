#!/bin/bash
# ============================================================
# スタート_Mac.command - 展開したフォルダからダブルクリックで起動
#
# Finder でこのファイルをダブルクリックすると、同梱の
# mac/mac-setup.sh を実行します（GitHub からの再取得は不要）。
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
    printf '        ZIP をフォルダごと展開してから、その中で\n'
    printf '        もう一度このファイルをダブルクリックしてください。\n\n'
    read -r -p '終了するには Enter を押してください...' _
    exit 1
fi

chmod +x "$SETUP" 2>/dev/null || true
bash "$SETUP"
EXIT_CODE=$?

printf '\n============================================================\n'
if [ "$EXIT_CODE" -eq 0 ]; then
    printf ' 完了しました。上の表示を確認してください。\n'
else
    printf ' 終了コード %s で終わりました。上の [NG] を確認し、\n' "$EXIT_CODE"
    printf ' もう一度このファイルを実行してください（導入済みはスキップされます）。\n'
fi
printf '============================================================\n'
printf '\n実行ログ: デスクトップの ai-setup-log.txt\n'
printf 'うまくいかない場合はこのファイルを管理者に送ってください。\n\n'
read -r -p '終了するには Enter を押してください...' _
exit "$EXIT_CODE"
