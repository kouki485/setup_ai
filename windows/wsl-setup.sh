#!/usr/bin/env bash
# ============================================================
# wsl-setup.sh - WSL2 (Ubuntu) 内のAI CLI一括セットアップ
#
# インストール内容:
#   1. 基本パッケージ (git / curl / build-essential / unzip)
#   2. Claude Code (Linuxネイティブ版)
#   3. Codex CLI  (Linuxネイティブ版)
#
# 実行方法（Ubuntuターミナルで）:
#   bash wsl-setup.sh
#
# 一部が失敗しても続行し、最後に結果一覧を表示します。
# ============================================================

set -uo pipefail

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
skip() { printf '  \033[33m[SKIP]\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m[NG]\033[0m %s\n' "$1"; }

FAILED=0

# rootで実行された場合はsudo不要
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# 一時的な503等に備えたリトライ付きダウンロード実行
# 使い方: run_installer "名前" "URL" "bash|sh"
run_installer() {
    local name="$1" url="$2" shell="$3" attempt start elapsed
    for attempt in 1 2 3; do
        printf '  \033[90mインストーラを取得して実行します。\033[0m\n'
        printf '  \033[90mダウンロードと展開に 1〜3 分かかります。画面が止まって見えても正常です。\033[0m\n'
        start=$(date +%s)
        # 出力は捨てずにそのまま流す。無言にすると利用者が固まったと誤解して
        # 強制終了してしまうため。
        if curl -fsSL "$url" | "$shell"; then
            elapsed=$(( $(date +%s) - start ))
            ok "$name をインストールしました (${elapsed}秒)"
            return 0
        fi
        fail "$name のダウンロードに失敗 (試行 $attempt/3)。5秒後に再試行..."
        sleep 5
    done
    fail "$name のインストールに失敗しました。後で手動実行してください: curl -fsSL $url | $shell"
    FAILED=1
    return 1
}

# ------------------------------------------------------------
# 1. 基本パッケージ
# ------------------------------------------------------------
step "基本パッケージ (git / curl など)"
printf '  \033[90mパッケージ一覧の更新とインストールに数分かかります...\033[0m\n'
if $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git curl unzip build-essential; then
    ok "git: $(git --version)"
    ok "curl: $(curl --version | head -n1)"
else
    fail "aptパッケージのインストールに失敗しました"
    FAILED=1
fi

# ------------------------------------------------------------
# 2. Claude Code
# ------------------------------------------------------------
step "Claude Code"
if command -v claude >/dev/null 2>&1; then
    skip "インストール済み ($(claude --version 2>/dev/null | head -n1))"
else
    run_installer "Claude Code" "https://claude.ai/install.sh" "bash" || true
fi

# ------------------------------------------------------------
# 3. Codex CLI
# ------------------------------------------------------------
step "Codex CLI"
if command -v codex >/dev/null 2>&1; then
    skip "インストール済み ($(codex --version 2>/dev/null | head -n1))"
else
    # セットアップ途中で Codex 本体を起動しない。起動すると終了コードが
    # インストーラへ伝播し、導入済みでも失敗としてリトライされるため。
    CODEX_NON_INTERACTIVE=1 run_installer "Codex CLI" "https://chatgpt.com/codex/install.sh" "sh" || true
fi

# ------------------------------------------------------------
# 4. PATH 確認（~/.local/bin）
# ------------------------------------------------------------
step "PATH 設定を確認"
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    export PATH="$HOME/.local/bin:$PATH"
    ok "~/.bashrc に PATH を追加しました"
else
    skip "PATH は設定済み"
fi

# ------------------------------------------------------------
# 5. 結果確認
# ------------------------------------------------------------
step "インストール結果"
for cmd in git claude codex; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd : $("$cmd" --version 2>/dev/null | head -n1)"
    else
        fail "$cmd が見つかりません（source ~/.bashrc 後に再確認）"
    fi
done

cat <<'EOF'

============================================================
 WSL側セットアップ完了！次のステップ:
   1. source ~/.bashrc （または新しいターミナルを開く）
   2. claude を実行 → Windows側ブラウザが開くのでログイン
   3. codex  を実行 → 同様にログイン

 ヒント: プロジェクトは /mnt/c/ ではなく ~/ 以下に置くと
         ファイルI/Oが速く快適です。
============================================================
EOF

exit $FAILED
