#!/usr/bin/env bash
# ============================================================
# wsl-setup.sh - WSL2 (Ubuntu) 内のAI CLI一括セットアップ
#
# インストール内容:
#   1. 基本パッケージ (git / curl / build-essential / unzip など)
#   2. Node.js LTS   (NodeSource 公式リポジトリ経由)
#   3. GitHub CLI    (公式 apt リポジトリ経由)
#   4. Supabase CLI  (GitHub Releases の .deb)
#   5. Vercel CLI    (公式ネイティブ npm パッケージ)
#   6. Claude Code   (署名付き公式 apt リポジトリ)
#   7. Codex CLI     (公式 npm パッケージ)
#   8. Hermes Agent  (任意 / Nous Research 公式インストーラ)
#
# 対応 OS: Ubuntu 20.04 以上 / Debian 10 以上。実行前に確認します。
#
# 実行方法（Ubuntuターミナルで）:
#   bash wsl-setup.sh
#
# 一部が失敗しても続行し、最後に結果一覧を表示します。
# ============================================================

set -u
set -o pipefail
umask 077
# 最小構成の Ubuntu でも tzdata などの対話待ちで止まらないようにする。
export DEBIAN_FRONTEND=noninteractive

# 全体の何番目を実行中かを常に見せる。長い処理が続くと利用者は
# 「止まったのでは」と不安になり、強制終了してしまうため。
TOTAL_STEPS=11
STEP_NO=0

step() {
    STEP_NO=$((STEP_NO + 1))
    printf '\n\033[36m==> [%d/%d] %s\033[0m\n' "$STEP_NO" "$TOTAL_STEPS" "$1"
}

ok()   { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
skip() { printf '  \033[33m[SKIP]\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m[注意]\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m[NG]\033[0m %s\n' "$1"; }

FAILED=0
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

# rootで実行された場合はsudo不要
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if ! command -v sudo >/dev/null 2>&1 || ! sudo -v; then
        fail "管理者権限を取得できません。sudo を利用できるユーザーで再実行してください。"
        exit 1
    fi
    SUDO="sudo"
fi

as_root() {
    if [ -n "$SUDO" ]; then sudo "$@"; else "$@"; fi
}

download() {
    curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused "$1" -o "$2"
}

key_has_fingerprint() {
    local key_file="$1" expected="$2"
    gpg --batch --show-keys --with-colons "$key_file" 2>/dev/null \
        | awk -F: '$1 == "fpr" { print $10 }' \
        | grep -Fqx "$expected"
}

# ------------------------------------------------------------
# 0. 実行環境（OSバージョン）の確認
#
# Claude Code は Ubuntu 20.04 以上 / Debian 10 以上が必要。また
# このスクリプトは apt 前提のため、それ以外のディストリビューション
# では中断する。アーキテクチャは Supabase CLI の .deb 選択に使う。
# ------------------------------------------------------------
step "実行環境の確認"

if [ ! -r /etc/os-release ]; then
    fail "/etc/os-release が読めません。Ubuntu / Debian で実行してください。"
    exit 1
fi
. /etc/os-release
OS_ID="${ID:-unknown}"
OS_VER="${VERSION_ID:-0}"
OS_VER_MAJOR="$(echo "$OS_VER" | cut -d. -f1)"

case "$OS_VER_MAJOR" in
    ''|*[!0-9]*)
        fail "OS バージョンを判定できませんでした: $OS_VER"
        exit 1
        ;;
esac

case "$OS_ID" in
    ubuntu|debian)
        ok "${PRETTY_NAME:-$OS_ID $OS_VER}"
        ;;
    *)
        fail "このスクリプトは Ubuntu / Debian 専用です（現在: ${PRETTY_NAME:-$OS_ID}）"
        exit 1
        ;;
esac

if [ "$OS_ID" = "ubuntu" ] && [ "${OS_VER_MAJOR:-0}" -lt 20 ] 2>/dev/null; then
    fail "Ubuntu $OS_VER は非対応です（20.04 以上が必要）"
    exit 1
fi
if [ "$OS_ID" = "debian" ] && [ "${OS_VER_MAJOR:-0}" -lt 10 ] 2>/dev/null; then
    fail "Debian $OS_VER は非対応です（10 以上が必要）"
    exit 1
fi

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
    amd64|arm64) ;;
    *)
        fail "未対応のアーキテクチャです: $ARCH（amd64 / arm64 のみ対応）"
        exit 1
        ;;
esac
ok "アーキテクチャ: $ARCH"

# ------------------------------------------------------------
# 1. 基本パッケージ
# ------------------------------------------------------------
step "基本パッケージ (git / curl など)"
printf '  \033[90mパッケージ一覧の更新とインストールに数分かかります...\033[0m\n'
if $SUDO apt-get update -q \
    && $SUDO apt-get install -y -q git curl wget unzip ca-certificates gnupg jq build-essential; then
    ok "git: $(git --version)"
    ok "curl: $(curl --version | head -n1)"
else
    fail "aptパッケージのインストールに失敗しました"
    FAILED=1
fi

# ------------------------------------------------------------
# 2. PATH 確認（~/.local/bin）
#
# CLI の導入より前に設定する。Claude Code / Codex CLI / Vercel CLI は
# ここへ入るが、途中で中断された場合に PATH だけ未設定だと、実体が
# あるのにコマンドが見つからない状態になる。
# ------------------------------------------------------------
step "PATH 設定を確認"
# shellcheck disable=SC2016  # 設定ファイルへリテラルとして書き込む
LOCAL_PATH_EXPORT='export PATH="$HOME/.local/bin:$PATH"'
case ":$PATH:" in
    *":$HOME/.local/bin:"*)
        skip "PATH は設定済み"
        ;;
    *)
    # 今のシェルの PATH に無くても .bashrc に書いてあれば追記しない
    # （非対話シェルから再実行されたときに重複追記しないため）
    if ! grep -Fqx "$LOCAL_PATH_EXPORT" "$HOME/.bashrc" 2>/dev/null; then
        printf '%s\n' "$LOCAL_PATH_EXPORT" >> "$HOME/.bashrc"
        ok ".bashrc に PATH を追加しました"
    else
        skip ".bashrc に設定済み"
    fi
    export PATH="$HOME/.local/bin:$PATH"
        ;;
esac

# ------------------------------------------------------------
# 3. Node.js (LTS)
#
# Ubuntu / Debian 標準リポジトリの Node は古いため、NodeSource の
# 公式リポジトリから LTS (24.x) を入れる。npm 配布 CLI の導入に使う。
# ------------------------------------------------------------
step "Node.js (LTS)"

NODE_MAJOR=""
NODE_MIN_MAJOR=22
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
fi

if [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -ge "$NODE_MIN_MAJOR" ] 2>/dev/null; then
    skip "インストール済み ($(node --version))"
else
    if [ -n "$NODE_MAJOR" ]; then
        warn "既存の Node.js ($(node --version)) は古いため LTS 版を上書きインストールします"
    fi
    printf '  \033[90m署名鍵を検証し、NodeSource リポジトリから Node.js LTS をインストールします...\033[0m\n'
    NODE_KEY_ASC="$TMP_DIR/nodesource.asc"
    NODE_KEY_GPG="$TMP_DIR/nodesource.gpg"
    NODE_KEY_FINGERPRINT="6F71F525282841EEDAF851B42F59B5F99B1BE0B4" # gitleaks:allow 公開署名鍵
    if download "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" "$NODE_KEY_ASC" \
        && key_has_fingerprint "$NODE_KEY_ASC" "$NODE_KEY_FINGERPRINT" \
        && gpg --batch --yes --dearmor --output "$NODE_KEY_GPG" "$NODE_KEY_ASC" \
        && as_root mkdir -p -m 755 /etc/apt/keyrings \
        && as_root install -m 644 "$NODE_KEY_GPG" /etc/apt/keyrings/nodesource.gpg \
        && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main\n' "$ARCH" \
            | as_root tee /etc/apt/sources.list.d/nodesource.list >/dev/null \
        && $SUDO apt-get update -q \
        && $SUDO apt-get install -y -q nodejs; then
        ok "Node.js をインストールしました ($(node --version 2>/dev/null))"
    else
        fail "Node.js の署名鍵検証またはインストールに失敗しました"
        FAILED=1
    fi
fi

# ------------------------------------------------------------
# 4. GitHub CLI (gh)
#
# GitHub 公式の apt リポジトリを登録して入れる（Ubuntu 標準の gh は
# 古く、GitHub の API 変更で動かないことがあるため公式版を使う）。
# ------------------------------------------------------------
step "GitHub CLI (gh)"

if command -v gh >/dev/null 2>&1; then
    skip "インストール済み ($(gh --version 2>/dev/null | head -n1))"
else
    printf '  \033[90mGitHub 公式リポジトリを登録して gh をインストールします...\033[0m\n'
    GH_KEY="$TMP_DIR/githubcli-archive-keyring.gpg"
    GH_KEY_SHA256="6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b" # gitleaks:allow 公開鍵のハッシュ
    if download "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "$GH_KEY" \
        && printf '%s  %s\n' "$GH_KEY_SHA256" "$GH_KEY" | sha256sum -c - >/dev/null \
        && $SUDO mkdir -p -m 755 /etc/apt/keyrings \
        && $SUDO install -m 644 "$GH_KEY" /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
        && $SUDO apt-get update -q \
        && $SUDO apt-get install -y -q gh; then
        ok "GitHub CLI をインストールしました ($(gh --version 2>/dev/null | head -n1))"
    else
        fail "GitHub CLI の鍵検証またはインストールに失敗しました"
        FAILED=1
    fi
fi

# ------------------------------------------------------------
# 5. Supabase CLI
#
# Linux 向けの公式配布は GitHub Releases のパッケージのみ
# （npm グローバル導入は公式に廃止済み）。最新の .deb を取得して入れる。
# ------------------------------------------------------------
step "Supabase CLI"

if command -v supabase >/dev/null 2>&1; then
    skip "インストール済み ($(supabase --version 2>/dev/null | head -n1))"
else
    printf '  \033[90m最新の Supabase CLI (.deb) を取得しています...\033[0m\n'
    SUPABASE_RELEASE="$TMP_DIR/supabase-release.json"
    SUPABASE_DEB="$TMP_DIR/supabase.deb"
    SUPABASE_ASSET_SUFFIX="_linux_${ARCH}.deb"
    SUPABASE_DEB_URL=""
    SUPABASE_DEB_DIGEST=""
    if download "https://api.github.com/repos/supabase/cli/releases/latest" "$SUPABASE_RELEASE"; then
        SUPABASE_DEB_URL="$(jq -r --arg suffix "$SUPABASE_ASSET_SUFFIX" \
            '.assets[] | select(.name | endswith($suffix)) | .browser_download_url' \
            "$SUPABASE_RELEASE" | head -n1)"
        SUPABASE_DEB_DIGEST="$(jq -r --arg suffix "$SUPABASE_ASSET_SUFFIX" \
            '.assets[] | select(.name | endswith($suffix)) | (.digest // "")' \
            "$SUPABASE_RELEASE" | head -n1)"
    fi
    case "$SUPABASE_DEB_URL" in
        https://github.com/supabase/cli/releases/download/*/"supabase_"*"_linux_${ARCH}.deb") ;;
        *) SUPABASE_DEB_URL="" ;;
    esac
    case "$SUPABASE_DEB_DIGEST" in
        sha256:????????????????????????????????????????????????????????????????) ;;
        *) SUPABASE_DEB_DIGEST="" ;;
    esac
    if [ -n "$SUPABASE_DEB_URL" ] \
        && [ -n "$SUPABASE_DEB_DIGEST" ] \
        && download "$SUPABASE_DEB_URL" "$SUPABASE_DEB" \
        && printf '%s  %s\n' "${SUPABASE_DEB_DIGEST#sha256:}" "$SUPABASE_DEB" \
            | sha256sum -c - >/dev/null \
        && $SUDO dpkg -i "$SUPABASE_DEB"; then
        ok "Supabase CLI をインストールしました ($(supabase --version 2>/dev/null | head -n1))"
    else
        fail "Supabase CLI の配布元・SHA-256検証またはインストールに失敗しました"
        FAILED=1
    fi
fi

# ------------------------------------------------------------
# 6. Vercel CLI
#
# Node.js 版の vercel パッケージではなく、依存関係を持たない公式
# ネイティブ版を固定して入れる。ライフサイクルスクリプトも実行しない。
# sudo 無しで入るように導入先は ~/.local にする。
# ------------------------------------------------------------
step "Vercel CLI"

VERCEL_NATIVE_VERSION="58.4.0"
if command -v vercel >/dev/null 2>&1; then
    skip "インストール済み ($(vercel --version 2>/dev/null | head -n1))"
elif ! command -v npm >/dev/null 2>&1; then
    fail "npm が見つからないため Vercel CLI をスキップしました（Node.js の導入失敗が原因です）"
    FAILED=1
else
    printf '  \033[90m公式ネイティブ版 Vercel CLI を取得しています...\033[0m\n'
    if npm install --prefix "$HOME/.local" -g --ignore-scripts \
        "@vercel/vc-native@$VERCEL_NATIVE_VERSION" \
        && command -v vercel >/dev/null 2>&1; then
        ok "Vercel CLI をインストールしました ($(vercel --version 2>/dev/null | head -n1))"
    else
        fail "Vercel CLI のインストールに失敗しました"
        FAILED=1
    fi
fi

# ------------------------------------------------------------
# 7. Claude Code
# ------------------------------------------------------------
step "Claude Code"
if command -v claude >/dev/null 2>&1; then
    skip "インストール済み ($(claude --version 2>/dev/null | head -n1))"
else
    printf '  \033[90mAnthropic の署名付き apt リポジトリから安定版を取得します...\033[0m\n'
    CLAUDE_KEY="$TMP_DIR/claude-code.asc"
    CLAUDE_KEY_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE" # gitleaks:allow 公開署名鍵
    if download "https://downloads.claude.ai/keys/claude-code.asc" "$CLAUDE_KEY" \
        && key_has_fingerprint "$CLAUDE_KEY" "$CLAUDE_KEY_FINGERPRINT" \
        && $SUDO mkdir -p -m 755 /etc/apt/keyrings \
        && $SUDO install -m 644 "$CLAUDE_KEY" /etc/apt/keyrings/claude-code.asc \
        && echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
            | $SUDO tee /etc/apt/sources.list.d/claude-code.list >/dev/null \
        && $SUDO apt-get update -q \
        && $SUDO apt-get install -y -q claude-code; then
        ok "Claude Code をインストールしました ($(claude --version 2>/dev/null | head -n1))"
    else
        fail "Claude Code の署名鍵検証またはインストールに失敗しました"
        FAILED=1
    fi
fi

# ------------------------------------------------------------
# 8. Codex CLI
# ------------------------------------------------------------
step "Codex CLI"
if command -v codex >/dev/null 2>&1; then
    skip "インストール済み ($(codex --version 2>/dev/null | head -n1))"
elif ! command -v npm >/dev/null 2>&1; then
    fail "npm が見つからないため Codex CLI をスキップしました"
    FAILED=1
else
    printf '  \033[90m公式 npm パッケージから Codex CLI を取得しています...\033[0m\n'
    if npm install --prefix "$HOME/.local" -g --ignore-scripts @openai/codex; then
        ok "Codex CLI をインストールしました ($(codex --version 2>/dev/null | head -n1))"
    else
        fail "Codex CLI のインストールに失敗しました"
        FAILED=1
    fi
fi

# ------------------------------------------------------------
# 9. Hermes Agent（任意）
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
                && bash -n "$HERMES_INSTALLER" \
                && bash "$HERMES_INSTALLER" --skip-setup --non-interactive; then
                hash -r
                if command -v hermes >/dev/null 2>&1; then
                    ok "Hermes Agent をインストールしました ($(hermes --version 2>/dev/null | head -n1))"
                else
                    fail "インストール後も hermes コマンドが見つかりません"
                    FAILED=1
                fi
            else
                fail "Hermes Agent の検証またはインストールに失敗しました"
                FAILED=1
            fi
            ;;
        *)
            skip "Hermes Agent は選択されなかったためスキップしました"
            ;;
    esac
fi

# ------------------------------------------------------------
# 10. 結果確認
# ------------------------------------------------------------
step "インストール結果"
for cmd in git node npm gh vercel supabase claude codex; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd : $("$cmd" --version 2>/dev/null | head -n1)"
    else
        fail "$cmd が見つかりません（新しいシェルを開いて再確認）"
        FAILED=1
    fi
done

if command -v hermes >/dev/null 2>&1; then
    ok "hermes : $(hermes --version 2>/dev/null | head -n1)"
else
    skip "hermes : 未導入（任意）"
fi

cat <<'EOF'

============================================================
 WSL側セットアップ完了！次のステップ:
   1. source ~/.bashrc （または新しいターミナルを開く）
   2. claude を実行 → Windows側ブラウザが開くのでログイン
   3. codex  を実行 → 同様にログイン
   4. Hermes を選んだ場合: hermes setup で初期設定
      ※ Nous Portal を使う場合: hermes setup --portal

 ヒント: プロジェクトは /mnt/c/ ではなく ~/ 以下に置くと
         ファイルI/Oが速く快適です。
============================================================
EOF

exit $FAILED
