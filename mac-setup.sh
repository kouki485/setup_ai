#!/usr/bin/env bash
# ============================================================
# mac-setup.sh - macOS 用 AI 開発環境一括セットアップ
#
# インストール内容:
#   1. Xcode Command Line Tools  (Homebrew の前提)
#   2. Homebrew                  (未導入なら導入し PATH も設定)
#   3. Git                       (Homebrew 経由。既にあればスキップ)
#   4. Claude Code               (ネイティブ版)
#   5. Codex CLI                 (ネイティブ版)
#   6. Claude Desktop            (GUIアプリ / Homebrew Cask)
#
# 実行方法:
#   bash mac-setup.sh
#
# Homebrew の導入時のみ管理者パスワードを求められます。
# 一部が失敗しても続行し、最後に結果一覧を表示します。
# 何度実行しても安全です（導入済みはスキップされます）。
# ============================================================

set -u

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
skip() { printf '  \033[33m[SKIP]\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m[NG]\033[0m %s\n' "$1"; }

FAILED=""

# 実行ログを残す。複数台に配る際、失敗した端末の状況を後から確認するため。
LOG="$HOME/Desktop/ai-setup-log.txt"
exec > >(tee "$LOG") 2>&1

# 一時的な 503 等に備えたリトライ付きダウンロード実行
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
    FAILED="$FAILED $name"
    return 1
}

# ------------------------------------------------------------
# 0. 前提の確認
# ------------------------------------------------------------
step "実行環境の確認"

if [ "$(uname -s)" != "Darwin" ]; then
    fail "このスクリプトは macOS 専用です（現在: $(uname -s)）"
    echo "  Windows の場合は setup.ps1、WSL の場合は wsl-setup.sh を使ってください。"
    exit 1
fi

ARCH="$(uname -m)"
ok "macOS $(sw_vers -productVersion) / $ARCH"

# Apple Silicon と Intel で Homebrew の導入先が異なる
if [ "$ARCH" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi
BREW_BIN="$BREW_PREFIX/bin/brew"

# ログイン時に読まれる設定ファイル。Homebrew の PATH はここに書く必要がある
# （.zshrc ではなく .zprofile。ログインシェルで一度だけ評価されるため）
case "${SHELL:-}" in
    */zsh)  PROFILE="$HOME/.zprofile" ;;
    */bash) PROFILE="$HOME/.bash_profile" ;;
    *)      PROFILE="$HOME/.profile" ;;
esac
ok "シェル設定ファイル: $PROFILE"

# ------------------------------------------------------------
# 1. Xcode Command Line Tools
# ------------------------------------------------------------
step "Xcode Command Line Tools"

if xcode-select -p >/dev/null 2>&1; then
    skip "インストール済み ($(xcode-select -p))"
else
    echo "  インストールを開始します。ダイアログが出たら「インストール」を選んでください。"
    xcode-select --install >/dev/null 2>&1 || true
    echo "  完了を待っています（数分かかります。ダイアログの進行に従ってください）..."
    # ダイアログ側の完了を待つ。最大 30 分。
    waited=0
    while ! xcode-select -p >/dev/null 2>&1; do
        sleep 15
        waited=$((waited + 15))
        if [ "$waited" -ge 1800 ]; then
            fail "Xcode Command Line Tools のインストールが完了しませんでした"
            echo "  手動で 'xcode-select --install' を実行してから、このスクリプトを再実行してください。"
            exit 1
        fi
    done
    ok "Xcode Command Line Tools をインストールしました"
fi

# ------------------------------------------------------------
# 2. Homebrew
# ------------------------------------------------------------
step "Homebrew"

if command -v brew >/dev/null 2>&1; then
    skip "インストール済み ($(brew --version | head -n1))"
    BREW_BIN="$(command -v brew)"
elif [ -x "$BREW_BIN" ]; then
    # 導入済みだが PATH に入っていない状態
    skip "インストール済みだが PATH 未設定 ($BREW_BIN)"
    eval "$("$BREW_BIN" shellenv)"
else
    echo "  Homebrew をインストールします。"
    echo "  この処理でのみ管理者パスワードを求められます（画面には表示されません）。"
    if ! sudo -v; then
        fail "パスワード認証に失敗しました。Homebrew を導入できません。"
        exit 1
    fi
    # NONINTERACTIVE=1 で確認プロンプトを省略する（sudo は上で認証済み）
    if NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        ok "Homebrew をインストールしました"
    else
        fail "Homebrew のインストールに失敗しました"
        echo "  https://brew.sh の手順に従って手動で導入してから再実行してください。"
        exit 1
    fi

    if [ ! -x "$BREW_BIN" ]; then
        fail "Homebrew が想定の場所に見つかりません ($BREW_BIN)"
        exit 1
    fi
    eval "$("$BREW_BIN" shellenv)"
fi

# PATH 設定を設定ファイルに永続化する（Apple Silicon では既定で PATH に入らない）
if ! grep -q "brew shellenv" "$PROFILE" 2>/dev/null; then
    {
        echo ''
        echo '# Homebrew'
        echo "eval \"\$($BREW_BIN shellenv)\""
    } >> "$PROFILE"
    ok "$PROFILE に Homebrew の PATH 設定を追加しました"
else
    skip "$PROFILE に Homebrew の PATH 設定は既にあります"
fi

# ------------------------------------------------------------
# 3. Git
# ------------------------------------------------------------
step "Git"

# macOS には Command Line Tools 付属の git があるため、通常はここでスキップされる
if command -v git >/dev/null 2>&1; then
    skip "インストール済み ($(git --version))"
else
    if brew install git; then
        ok "Git をインストールしました ($(git --version))"
    else
        fail "Git のインストールに失敗しました"
        FAILED="$FAILED Git"
    fi
fi

# ------------------------------------------------------------
# 4. Claude Code
# ------------------------------------------------------------
step "Claude Code"

if command -v claude >/dev/null 2>&1; then
    skip "インストール済み ($(claude --version 2>/dev/null | head -n1))"
else
    run_installer "Claude Code" "https://claude.ai/install.sh" "bash" || true
fi

# ------------------------------------------------------------
# 5. Codex CLI
# ------------------------------------------------------------
step "Codex CLI"

if command -v codex >/dev/null 2>&1; then
    skip "インストール済み ($(codex --version 2>/dev/null | head -n1))"
else
    run_installer "Codex CLI" "https://chatgpt.com/codex/install.sh" "sh" || true
fi

# ------------------------------------------------------------
# 6. Claude Desktop (GUIアプリ)
# ------------------------------------------------------------
step "Claude Desktop"

if [ -d "/Applications/Claude.app" ]; then
    skip "インストール済み (/Applications/Claude.app)"
elif brew list --cask claude >/dev/null 2>&1; then
    skip "インストール済み (Homebrew Cask)"
else
    printf '  \033[90mClaude Desktop をダウンロードしています（数分かかります）...\033[0m\n'
    if brew install --cask claude; then
        ok "Claude Desktop をインストールしました（Launchpad から起動できます）"
    else
        fail "Claude Desktop のインストールに失敗しました"
        FAILED="$FAILED Claude-Desktop"
    fi
fi

# ------------------------------------------------------------
# 7. PATH 確認（~/.local/bin）
# ------------------------------------------------------------
step "PATH 設定を確認"

LOCAL_BIN="$HOME/.local/bin"
if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
    if ! grep -q '\.local/bin' "$PROFILE" 2>/dev/null; then
        {
            echo ''
            echo '# ユーザーローカルのコマンド'
            echo 'export PATH="$HOME/.local/bin:$PATH"'
        } >> "$PROFILE"
        ok "$PROFILE に ~/.local/bin を追加しました"
    else
        skip "$PROFILE に ~/.local/bin の設定は既にあります"
    fi
    export PATH="$LOCAL_BIN:$PATH"
else
    skip "PATH は設定済み"
fi

# ------------------------------------------------------------
# 8. インストール結果
# ------------------------------------------------------------
step "インストール結果"

for cmd in brew git claude codex; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd : $("$cmd" --version 2>/dev/null | head -n1)"
    else
        fail "$cmd が見つかりません（新しいターミナルを開いてから再確認してください）"
    fi
done

if [ -d "/Applications/Claude.app" ]; then
    ok "Claude Desktop : /Applications/Claude.app"
else
    fail "Claude Desktop が見つかりません"
fi

if [ -n "$FAILED" ]; then
    printf '\n\033[31m 失敗した項目:%s\033[0m\n' "$FAILED"
    echo " ネットワークの一時的な問題の可能性があります。再実行すると成功項目はスキップされます。"
fi

cat <<EOF

============================================================
 セットアップ完了！次のステップ:
   1. 新しいターミナルを開く（PATH反映のため）
      ※ 今の画面でそのまま試すなら: source $PROFILE
   2. claude を実行 → ブラウザでログイン（Pro/Max等が必要）
   3. codex  を実行 → ブラウザでログイン（ChatGPT Plus等が必要）
   4. Launchpad から Claude を起動 → アカウントでサインイン

 業務での使い方は prompts/ のプロンプトを参照してください。
   business-discovery.md … 自分の業務を Claude に理解させる
   ax-proposal.md        … AI で楽にできる部分を洗い出す

 実行ログ: $LOG
 うまくいかない場合はこのファイルを管理者に送ってください。
============================================================
EOF

if [ -n "$FAILED" ]; then exit 1; fi
exit 0
