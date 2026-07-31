#!/usr/bin/env bash
# ============================================================
# mac-setup.sh - macOS 用 AI 開発環境一括セットアップ
#
# インストール内容:
#   1. Xcode Command Line Tools  (Homebrew の前提)
#   2. Homebrew                  (未導入なら導入し PATH も設定)
#   3. Git                       (Homebrew 経由。既にあればスキップ)
#   4. Node.js LTS               (Homebrew 経由 / npm 配布CLIの導入に使用)
#   5. GitHub CLI (gh)           (Homebrew 経由)
#   6. Supabase CLI              (Homebrew 公式 tap 経由)
#   7. Vercel CLI                (公式ネイティブ npm パッケージ)
#   8. Claude Code               (Homebrew Cask)
#   9. Codex CLI                 (Homebrew Cask)
#  10. Hermes Agent              (任意 / Nous Research 公式インストーラ)
#  11. Claude Desktop            (GUIアプリ / Homebrew Cask)
#  12. Obsidian + MCP設定ヘルパー (任意 / Homebrew Cask)
#
# 対応 OS: macOS 13 (Ventura) 以上。実行前にバージョンを確認します。
#
# 実行方法:
#   bash mac-setup.sh
#
# Homebrew の導入時のみ管理者パスワードを求められます。
# 一部が失敗しても続行し、最後に結果一覧を表示します。
# 何度実行しても安全です（導入済みはスキップされます）。
# ============================================================

set -u
set -o pipefail
umask 077

# 全体の何番目を実行中かを常に見せる。長い処理が続くと利用者は
# 「止まったのでは」と不安になり、強制終了してしまうため。
TOTAL_STEPS=15
STEP_NO=0

step() {
    STEP_NO=$((STEP_NO + 1))
    printf '\n\033[36m==> [%d/%d] %s\033[0m\n' "$STEP_NO" "$TOTAL_STEPS" "$1"
}

# brew install は初回の "Updating Homebrew..." で 1 分以上まったく
# 出力が出ないことがある。何を待っているのかを先に伝えてから実行する。
brew_install() {
    local label="${*#--cask }"
    printf '  \033[90mHomebrew で %s を取得します。1〜3 分かかることがあります。\033[0m\n' "$label"
    brew install "$@"
}

ok()   { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
skip() { printf '  \033[33m[SKIP]\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m[注意]\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m[NG]\033[0m %s\n' "$1"; }

FAILED=""
OBSIDIAN_SELECTED=0
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai.XXXXXX")" || {
    fail "一時ディレクトリを作成できませんでした"
    exit 1
}

# shellcheck disable=SC2329  # EXIT trap から呼び出す
cleanup() {
    rm -f -- "$TMP_DIR"/* 2>/dev/null || true
    rmdir "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

# 実行ログを残す。複数台に配る際、失敗した端末の状況を後から確認するため。
LOG="$HOME/Desktop/ai-setup-log.txt"
exec > >(tee "$LOG") 2>&1

download() {
    curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused "$1" -o "$2"
}

# ------------------------------------------------------------
# 0. 前提の確認
# ------------------------------------------------------------
step "実行環境の確認"

if [ "$(uname -s)" != "Darwin" ]; then
    fail "このスクリプトは macOS 専用です（現在: $(uname -s)）"
    echo "  Windows の場合は windows/setup.ps1、WSL の場合は windows/wsl-setup.sh を使ってください。"
    exit 1
fi

ARCH="$(uname -m)"
OS_VERSION="$(sw_vers -productVersion)"
OS_MAJOR="$(echo "$OS_VERSION" | cut -d. -f1)"

# OS バージョンを先に判定する。古い macOS では Claude Code (13.0+) や
# Homebrew (14+ が公式サポート) が動かないため、入らないものを
# 延々ダウンロードする前にここで止める。
if [ "$OS_MAJOR" -lt 13 ] 2>/dev/null; then
    fail "macOS $OS_VERSION は非対応です（Claude Code には macOS 13 以上が必要）"
    echo "  「システム設定 > 一般 > ソフトウェアアップデート」で macOS を更新してから再実行してください。"
    exit 1
fi
ok "macOS $OS_VERSION / $ARCH"
if [ "$OS_MAJOR" -eq 13 ] 2>/dev/null; then
    warn "macOS 13 は Homebrew の公式サポート外です（macOS 14 以上を推奨。動作する可能性はありますが失敗したら OS 更新を検討してください）"
fi

# Apple Silicon と Intel で Homebrew の導入先が異なる
case "$ARCH" in
    arm64)  BREW_PREFIX="/opt/homebrew" ;;
    x86_64) BREW_PREFIX="/usr/local" ;;
    *)
        fail "未対応のアーキテクチャです: $ARCH（arm64 / x86_64 のみ対応）"
        exit 1
        ;;
esac
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
        # 無言で待つと固まったと誤解されるため、30 秒ごとに生存を示す。
        if [ $((waited % 30)) -eq 0 ]; then
            printf '  \033[90m... ダイアログの完了を待っています (%d分%d秒経過 / 最大30分)\033[0m\n' \
                "$((waited / 60))" "$((waited % 60))"
        fi
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
    BREW_PREFIX="$("$BREW_BIN" --prefix)"
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
    HOMEBREW_INSTALLER="$TMP_DIR/homebrew-install.sh"
    if download "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "$HOMEBREW_INSTALLER" \
        && /bin/bash -n "$HOMEBREW_INSTALLER" \
        && NONINTERACTIVE=1 /bin/bash "$HOMEBREW_INSTALLER"; then
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
BREW_PREFIX="$("$BREW_BIN" --prefix)"

# PATH 設定を設定ファイルに永続化する（Apple Silicon では既定で PATH に入らない）
BREW_SHELLENV_LINE="eval \"\$($BREW_BIN shellenv)\""
if ! grep -Fqx "$BREW_SHELLENV_LINE" "$PROFILE" 2>/dev/null; then
    {
        echo ''
        echo '# Homebrew'
        printf '%s\n' "$BREW_SHELLENV_LINE"
    } >> "$PROFILE"
    ok "$PROFILE に Homebrew の PATH 設定を追加しました"
else
    skip "$PROFILE に Homebrew の PATH 設定は既にあります"
fi

# ------------------------------------------------------------
# 3. PATH 確認（~/.local/bin）
#
# CLI の導入より前に設定する。Vercel CLI などはここへ入るが、
# 途中で中断された場合に PATH だけ未設定だと、実体があるのにコマンドが
# 見つからない状態になる。ディレクトリが未作成でも追記は可能。
# ------------------------------------------------------------
step "PATH 設定を確認"

LOCAL_BIN="$HOME/.local/bin"
# shellcheck disable=SC2016  # 設定ファイルへリテラルとして書き込む
LOCAL_PATH_EXPORT='export PATH="$HOME/.local/bin:$PATH"'
case ":$PATH:" in
    *":$LOCAL_BIN:"*)
        skip "PATH は設定済み"
        ;;
    *)
    if ! grep -Fqx "$LOCAL_PATH_EXPORT" "$PROFILE" 2>/dev/null; then
        {
            echo ''
            echo '# ユーザーローカルのコマンド'
            printf '%s\n' "$LOCAL_PATH_EXPORT"
        } >> "$PROFILE"
        ok "$PROFILE に .local/bin を追加しました"
    else
        skip "$PROFILE に .local/bin の設定は既にあります"
    fi
    export PATH="$LOCAL_BIN:$PATH"
        ;;
esac

# ------------------------------------------------------------
# 4. Git
# ------------------------------------------------------------
step "Git"

# macOS には Command Line Tools 付属の git があるため、通常はここでスキップされる
if command -v git >/dev/null 2>&1; then
    skip "インストール済み ($(git --version))"
else
    if brew_install git; then
        ok "Git をインストールしました ($(git --version))"
    else
        fail "Git のインストールに失敗しました"
        FAILED="$FAILED Git"
    fi
fi

# ------------------------------------------------------------
# 5. Node.js (LTS)
#
# npm 配布 CLI の導入に使用する。node@24 は keg-only のため
# インストールしただけでは PATH に入らず、明示的な追記が必要。
# ------------------------------------------------------------
step "Node.js (LTS)"

NODE_FORMULA="node@24"
NODE_MAJOR=""
NODE_MIN_MAJOR=22
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
fi

if [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -ge "$NODE_MIN_MAJOR" ] 2>/dev/null; then
    skip "インストール済み ($(node --version))"
else
    if [ -n "$NODE_MAJOR" ]; then
        warn "既存の Node.js ($(node --version)) は古いため LTS 版を追加インストールします"
    fi
    printf '  \033[90mNode.js LTS をダウンロードしています（数分かかります）...\033[0m\n'
    if brew_install "$NODE_FORMULA"; then
        NODE_BIN="$BREW_PREFIX/opt/$NODE_FORMULA/bin"
        if ! grep -q "opt/$NODE_FORMULA/bin" "$PROFILE" 2>/dev/null; then
            {
                echo ''
                echo '# Node.js (LTS)'
                echo "export PATH=\"$NODE_BIN:\$PATH\""
            } >> "$PROFILE"
            ok "$PROFILE に Node.js の PATH 設定を追加しました"
        fi
        export PATH="$NODE_BIN:$PATH"
        ok "Node.js をインストールしました ($(node --version 2>/dev/null))"
    else
        fail "Node.js のインストールに失敗しました"
        FAILED="$FAILED Node.js"
    fi
fi

# ------------------------------------------------------------
# 6. GitHub CLI (gh)
# ------------------------------------------------------------
step "GitHub CLI (gh)"

if command -v gh >/dev/null 2>&1; then
    skip "インストール済み ($(gh --version 2>/dev/null | head -n1))"
else
    if brew_install gh; then
        ok "GitHub CLI をインストールしました ($(gh --version 2>/dev/null | head -n1))"
    else
        fail "GitHub CLI のインストールに失敗しました"
        FAILED="$FAILED GitHub-CLI"
    fi
fi

# ------------------------------------------------------------
# 7. Supabase CLI
#
# npm でのグローバル導入は公式に廃止されているため Homebrew の
# 公式 tap (supabase/tap) を使う。
# ------------------------------------------------------------
step "Supabase CLI"

if command -v supabase >/dev/null 2>&1; then
    skip "インストール済み ($(supabase --version 2>/dev/null | head -n1))"
else
    if brew_install supabase/tap/supabase; then
        ok "Supabase CLI をインストールしました ($(supabase --version 2>/dev/null | head -n1))"
    else
        fail "Supabase CLI のインストールに失敗しました"
        FAILED="$FAILED Supabase-CLI"
    fi
fi

# ------------------------------------------------------------
# 8. Vercel CLI
#
# Node.js 版の vercel パッケージではなく、依存関係を持たない公式
# ネイティブ版を固定して入れる。ライフサイクルスクリプトも実行しない。
# ------------------------------------------------------------
step "Vercel CLI"

VERCEL_NATIVE_VERSION="58.4.0"
if command -v vercel >/dev/null 2>&1; then
    skip "インストール済み ($(vercel --version 2>/dev/null | head -n1))"
elif ! command -v npm >/dev/null 2>&1; then
    fail "npm が見つからないため Vercel CLI をスキップしました"
    FAILED="$FAILED Vercel-CLI"
else
    printf '  \033[90m公式ネイティブ版 Vercel CLI を取得しています...\033[0m\n'
    if npm install --prefix "$HOME/.local" -g --ignore-scripts \
        "@vercel/vc-native@$VERCEL_NATIVE_VERSION" \
        && command -v vercel >/dev/null 2>&1; then
        ok "Vercel CLI をインストールしました ($(vercel --version 2>/dev/null | head -n1))"
    else
        fail "Vercel CLI のインストールに失敗しました"
        FAILED="$FAILED Vercel-CLI"
    fi
fi

# ------------------------------------------------------------
# 9. Claude Code
# ------------------------------------------------------------
step "Claude Code"

if command -v claude >/dev/null 2>&1; then
    skip "インストール済み ($(claude --version 2>/dev/null | head -n1))"
else
    if brew_install --cask claude-code; then
        ok "Claude Code をインストールしました ($(claude --version 2>/dev/null | head -n1))"
    else
        fail "Claude Code のインストールに失敗しました"
        FAILED="$FAILED Claude-Code"
    fi
fi

# ------------------------------------------------------------
# 10. Codex CLI
# ------------------------------------------------------------
step "Codex CLI"

if command -v codex >/dev/null 2>&1; then
    skip "インストール済み ($(codex --version 2>/dev/null | head -n1))"
else
    if brew_install --cask codex; then
        ok "Codex CLI をインストールしました ($(codex --version 2>/dev/null | head -n1))"
    else
        fail "Codex CLI のインストールに失敗しました"
        FAILED="$FAILED Codex-CLI"
    fi
fi

# ------------------------------------------------------------
# 11. Hermes Agent（任意）
# ------------------------------------------------------------
step "Hermes Agent（任意）"

if command -v hermes >/dev/null 2>&1; then
    skip "インストール済み ($(hermes --version 2>/dev/null | head -n1))"
else
    printf '  Hermes Agent をインストールしますか？ (y/N): '
    HERMES_ANSWER=""
    IFS= read -r HERMES_ANSWER || HERMES_ANSWER=""
    case "$HERMES_ANSWER" in
        y|Y|yes|YES|Yes)
            printf '  \033[90mNous Research の公式インストーラを取得しています...\033[0m\n'
            HERMES_INSTALLER="$TMP_DIR/hermes-install.sh"
            if download "https://hermes-agent.nousresearch.com/install.sh" "$HERMES_INSTALLER" \
                && /bin/bash -n "$HERMES_INSTALLER" \
                && /bin/bash "$HERMES_INSTALLER" --skip-setup --non-interactive; then
                hash -r
                if command -v hermes >/dev/null 2>&1; then
                    ok "Hermes Agent をインストールしました ($(hermes --version 2>/dev/null | head -n1))"
                else
                    fail "インストール後も hermes コマンドが見つかりません"
                    FAILED="$FAILED Hermes-Agent"
                fi
            else
                fail "Hermes Agent の検証またはインストールに失敗しました"
                FAILED="$FAILED Hermes-Agent"
            fi
            ;;
        *)
            skip "Hermes Agent は選択されなかったためスキップしました"
            ;;
    esac
fi

# ------------------------------------------------------------
# 12. Claude Desktop (GUIアプリ)
# ------------------------------------------------------------
step "Claude Desktop"

if [ -d "/Applications/Claude.app" ]; then
    skip "インストール済み (/Applications/Claude.app)"
elif brew list --cask claude >/dev/null 2>&1; then
    skip "インストール済み (Homebrew Cask)"
else
    printf '  \033[90mClaude Desktop をダウンロードしています（数分かかります）...\033[0m\n'
    if brew_install --cask claude; then
        ok "Claude Desktop をインストールしました（Launchpad から起動できます）"
    else
        fail "Claude Desktop のインストールに失敗しました"
        FAILED="$FAILED Claude-Desktop"
    fi
fi

# ------------------------------------------------------------
# 13. Obsidian + MCP設定ヘルパー（任意）
# ------------------------------------------------------------
step "Obsidian MCP（任意）"

printf '  Obsidian MCP をインストールしますか？ (y/N): '
OBSIDIAN_ANSWER=""
IFS= read -r OBSIDIAN_ANSWER || OBSIDIAN_ANSWER=""
case "$OBSIDIAN_ANSWER" in
    y|Y|yes|YES|Yes)
        OBSIDIAN_SELECTED=1
        if [ -d "/Applications/Obsidian.app" ]; then
            skip "Obsidian はインストール済み (/Applications/Obsidian.app)"
        elif brew list --cask obsidian >/dev/null 2>&1; then
            skip "Obsidian はインストール済み (Homebrew Cask)"
        else
            printf '  \033[90mObsidian をダウンロードしています（数分かかります）...\033[0m\n'
            if brew_install --cask obsidian; then
                ok "Obsidian をインストールしました（Launchpad から起動できます）"
            else
                fail "Obsidian のインストールに失敗しました"
                FAILED="$FAILED Obsidian"
            fi
        fi

        OBSIDIAN_HELPER_URL="https://raw.githubusercontent.com/kouki485/setup_ai/main/mac/setup-obsidian-mcp.sh"
        OBSIDIAN_HELPER_SHA256="1e2e86de3d1619a69cbc31ac7d43b098db366b391a5014adb836f20d46a2e7e2"
        OBSIDIAN_HELPER_TEMP="$TMP_DIR/setup-obsidian-mcp.sh"
        OBSIDIAN_HELPER_DEST="$LOCAL_BIN/setup-obsidian-mcp"
        mkdir -p "$LOCAL_BIN"
        if download "$OBSIDIAN_HELPER_URL" "$OBSIDIAN_HELPER_TEMP" \
            && printf '%s  %s\n' "$OBSIDIAN_HELPER_SHA256" "$OBSIDIAN_HELPER_TEMP" \
                | shasum -a 256 -c - >/dev/null \
            && /bin/bash -n "$OBSIDIAN_HELPER_TEMP" \
            && install -m 700 "$OBSIDIAN_HELPER_TEMP" "$OBSIDIAN_HELPER_DEST"; then
            ok "MCP 設定コマンドをインストールしました ($OBSIDIAN_HELPER_DEST)"
        else
            fail "MCP 設定コマンドの配布元・SHA-256・構文検証に失敗しました"
            FAILED="$FAILED Obsidian-MCP-Helper"
        fi
        ;;
    *)
        skip "Obsidian MCP は選択されなかったためスキップしました"
        ;;
esac

# ------------------------------------------------------------
# 14. インストール結果
# ------------------------------------------------------------
step "インストール結果"

for cmd in brew git node npm gh vercel supabase claude codex; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd : $("$cmd" --version 2>/dev/null | head -n1)"
    else
        fail "$cmd が見つかりません（新しいターミナルを開いてから再確認してください）"
        FAILED="$FAILED $cmd"
    fi
done

if command -v hermes >/dev/null 2>&1; then
    ok "hermes : $(hermes --version 2>/dev/null | head -n1)"
else
    skip "hermes : 未導入（任意）"
fi

if [ -d "/Applications/Claude.app" ]; then
    ok "Claude Desktop : /Applications/Claude.app"
else
    fail "Claude Desktop が見つかりません"
    FAILED="$FAILED Claude-Desktop"
fi

if [ "$OBSIDIAN_SELECTED" -eq 1 ]; then
    if [ -d "/Applications/Obsidian.app" ]; then
        ok "Obsidian : /Applications/Obsidian.app"
    else
        fail "Obsidian が見つかりません"
        FAILED="$FAILED Obsidian"
    fi
    if [ -x "$LOCAL_BIN/setup-obsidian-mcp" ]; then
        ok "Obsidian MCP 設定 : setup-obsidian-mcp"
    else
        fail "setup-obsidian-mcp が見つかりません"
        FAILED="$FAILED Obsidian-MCP-Helper"
    fi
else
    skip "Obsidian MCP : 未導入（任意）"
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
   4. Hermes を選んだ場合: hermes setup で初期設定
      ※ Nous Portal を使う場合: hermes setup --portal
   5. Launchpad から Claude を起動 → アカウントでサインイン
   6. Obsidian MCP を選んだ場合:
      Obsidian で Local REST API with MCP を有効化し、
      HTTP server を有効にしてから setup-obsidian-mcp を実行

 業務での使い方は prompts/ のプロンプトを参照してください。
   business-discovery.md … 自分の業務を Claude に理解させる
   ax-proposal.md        … AI で楽にできる部分を洗い出す

 実行ログ: $LOG
 うまくいかない場合はこのファイルを管理者に送ってください。
============================================================
EOF

if [ -n "$FAILED" ]; then exit 1; fi
exit 0
