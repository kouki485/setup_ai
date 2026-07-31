#!/usr/bin/env bash
# Obsidian の Local REST API 内蔵 MCP を Claude Code / Codex CLI /
# Hermes Agent（導入済みの場合）へ登録する。

set -u
set -o pipefail
umask 077

FORCE=0
case "${1:-}" in
    "") ;;
    --force) FORCE=1 ;;
    -h|--help)
        echo "使い方: setup-obsidian-mcp [--force]"
        echo "  --force  既存の obsidian 設定を確認なしで置き換える"
        exit 0
        ;;
    *)
        echo "[NG] 未対応の引数です: $1" >&2
        exit 2
        ;;
esac

ok()   { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
skip() { printf '  \033[33m[SKIP]\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m[注意]\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m[NG]\033[0m %s\n' "$1" >&2; }

FAILED=0
CONFIGURED=0
CLIENT_FOUND=0
MCP_URL="${OBSIDIAN_MCP_URL:-http://127.0.0.1:27123/mcp/}"

# API キーを任意の外部ホストへ送らないよう、接続先はループバックの
# Streamable HTTP エンドポイントだけを許可する。ポート変更は許容する。
if [[ ! "$MCP_URL" =~ ^http://127\.0\.0\.1:([0-9]{1,5})/mcp/$ ]]; then
    fail "OBSIDIAN_MCP_URL は http://127.0.0.1:<port>/mcp/ の形式にしてください"
    exit 1
fi
MCP_PORT="${BASH_REMATCH[1]}"
if [ "$MCP_PORT" -lt 1 ] || [ "$MCP_PORT" -gt 65535 ]; then
    fail "MCP のポート番号が不正です: $MCP_PORT"
    exit 1
fi
REST_URL="${MCP_URL%/mcp/}/vault/"
STATUS_URL="${MCP_URL%/mcp/}/"

cat <<'EOF'

Obsidian MCP の接続設定を始めます。
先に Obsidian で次の設定を完了してください。
  1. コミュニティプラグイン「Local REST API with MCP」を導入・有効化
  2. Local REST API の設定で「Enable HTTP server」を有効化
  3. Binding Host は 127.0.0.1 のまま変更しない
  4. Authorization header は既定値 Authorization のままにする
  5. 同じ画面に表示される API Key を用意

プラグイン: https://community.obsidian.md/plugins/obsidian-local-rest-api
EOF

if ! curl -q -fsS --noproxy '*' --proto '=http' --max-redirs 0 \
    --connect-timeout 3 --max-time 10 -o /dev/null "$STATUS_URL"; then
    fail "Obsidian の Local REST API に接続できません: $STATUS_URL"
    echo "  Obsidian を起動し、上記 1〜3 を確認してから再実行してください。" >&2
    exit 1
fi

API_KEY="${OBSIDIAN_API_KEY:-${SETUP_AI_OBSIDIAN_API_KEY:-}}"
if [ -z "$API_KEY" ]; then
    printf 'API Key（入力内容は表示されません）: '
    IFS= read -r -s API_KEY || API_KEY=""
    printf '\n'
fi

# 既定の API Key は64桁の16進文字列だが、プラグイン設定で変更できる。
# URL-safe な文字種と十分な長さに限定し、改行・シェル構文注入も防ぐ。
if [[ ! "$API_KEY" =~ ^[A-Za-z0-9._~+/=-]{32,256}$ ]]; then
    fail "API Key の形式が不正です（32〜256文字の英数字・安全な記号だけを使用してください）"
    exit 1
fi

# ヘッダーをコマンドライン引数に置かず、curl の設定を標準入力で渡す。
HTTP_STATUS="$(
    printf 'header = "Authorization: Bearer %s"\n' "$API_KEY" \
        | curl -q --config - --silent --show-error --noproxy '*' --proto '=http' \
            --max-redirs 0 --connect-timeout 3 --max-time 10 -o /dev/null \
            -w '%{http_code}' "$REST_URL"
)" || HTTP_STATUS=""
case "$HTTP_STATUS" in
    2??) ok "Local REST API と API Key を確認しました" ;;
    401|403)
        fail "API Key が拒否されました（HTTP $HTTP_STATUS）"
        exit 1
        ;;
    *)
        fail "Local REST API の認証確認に失敗しました（HTTP ${HTTP_STATUS:-接続失敗}）"
        exit 1
        ;;
esac

# Codex / Claude は環境変数からキーを参照する。秘密値は権限 600 の
# 専用ファイルだけに保存し、各 MCP 設定やシェル設定へ直書きしない。
SECRET_DIR="$HOME/.config/setup-ai"
SECRET_FILE="$SECRET_DIR/obsidian-mcp.env"
mkdir -p "$SECRET_DIR"
chmod 700 "$SECRET_DIR"
{
    printf "export SETUP_AI_OBSIDIAN_API_KEY='%s'\n" "$API_KEY"
    printf 'export MCP_OBSIDIAN_API_KEY="$SETUP_AI_OBSIDIAN_API_KEY"\n'
} > "$SECRET_FILE"
chmod 600 "$SECRET_FILE"

case "${SHELL:-}" in
    */bash) PROFILE="$HOME/.bash_profile" ;;
    */zsh|"") PROFILE="$HOME/.zprofile" ;;
    *) PROFILE="$HOME/.profile" ;;
esac
# shellcheck disable=SC2016  # 設定ファイルへリテラルとして書き込む
SOURCE_LINE='[ -r "$HOME/.config/setup-ai/obsidian-mcp.env" ] && . "$HOME/.config/setup-ai/obsidian-mcp.env"'
if ! grep -Fqx "$SOURCE_LINE" "$PROFILE" 2>/dev/null; then
    {
        echo ""
        echo "# Obsidian Local REST API MCP"
        printf '%s\n' "$SOURCE_LINE"
    } >> "$PROFILE"
fi
export SETUP_AI_OBSIDIAN_API_KEY="$API_KEY"
export MCP_OBSIDIAN_API_KEY="$API_KEY"
ok "API Key を $SECRET_FILE に保存しました（権限 600）"

confirm_replace() {
    local label="$1" answer=""
    if [ "$FORCE" -eq 1 ]; then
        return 0
    fi
    printf '  %s に既存の obsidian 設定があります。置き換えますか？ (y/N): ' "$label"
    IFS= read -r answer || answer=""
    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

echo ""
echo "MCP クライアントへ登録します。"

if command -v claude >/dev/null 2>&1; then
    CLIENT_FOUND=$((CLIENT_FOUND + 1))
    CLAUDE_EXISTS=0
    claude mcp get obsidian >/dev/null 2>&1 && CLAUDE_EXISTS=1
    if [ "$CLAUDE_EXISTS" -eq 1 ] && ! confirm_replace "Claude Code"; then
        skip "Claude Code の既存設定を維持しました"
    else
        if [ "$CLAUDE_EXISTS" -eq 1 ]; then
            claude mcp remove obsidian --scope user >/dev/null 2>&1 || true
        fi
        CLAUDE_JSON="{\"type\":\"http\",\"url\":\"$MCP_URL\",\"headers\":{\"Authorization\":\"Bearer \${SETUP_AI_OBSIDIAN_API_KEY}\"}}"
        if claude mcp add-json --scope user obsidian "$CLAUDE_JSON"; then
            ok "Claude Code に obsidian を登録しました（ユーザースコープ）"
            CONFIGURED=$((CONFIGURED + 1))
        else
            fail "Claude Code への登録に失敗しました"
            FAILED=1
        fi
    fi
else
    skip "Claude Code が見つからないため登録をスキップしました"
fi

if command -v codex >/dev/null 2>&1; then
    CLIENT_FOUND=$((CLIENT_FOUND + 1))
    CODEX_EXISTS=0
    codex mcp get obsidian >/dev/null 2>&1 && CODEX_EXISTS=1
    if [ "$CODEX_EXISTS" -eq 1 ] && ! confirm_replace "Codex CLI"; then
        skip "Codex CLI の既存設定を維持しました"
    else
        if [ "$CODEX_EXISTS" -eq 1 ]; then
            codex mcp remove obsidian >/dev/null 2>&1 || true
        fi
        if codex mcp add obsidian --url "$MCP_URL" \
            --bearer-token-env-var SETUP_AI_OBSIDIAN_API_KEY; then
            ok "Codex CLI に obsidian を登録しました"
            CONFIGURED=$((CONFIGURED + 1))
        else
            fail "Codex CLI への登録に失敗しました"
            FAILED=1
        fi
    fi
else
    skip "Codex CLI が見つからないため登録をスキップしました"
fi

if command -v hermes >/dev/null 2>&1; then
    CLIENT_FOUND=$((CLIENT_FOUND + 1))
    HERMES_EXISTS=0
    if hermes mcp list 2>/dev/null | grep -Eq '(^|[[:space:]])obsidian([[:space:]]|$)'; then
        HERMES_EXISTS=1
    fi
    if [ "$HERMES_EXISTS" -eq 1 ] && ! confirm_replace "Hermes Agent"; then
        skip "Hermes Agent の既存設定を維持しました"
    else
        if [ "$HERMES_EXISTS" -eq 1 ]; then
            printf 'y\n' | hermes mcp remove obsidian >/dev/null 2>&1 || true
        fi
        if [ -t 0 ] && [ "$FORCE" -eq 0 ]; then
            echo "  Hermes の質問では、必要なら select を選んで利用ツールを絞れます。"
            hermes mcp add obsidian --url "$MCP_URL" --auth header
            HERMES_EXIT=$?
        else
            # 認証あり・全ツール有効の既定回答。API Key は環境変数から読まれる。
            printf '\n\n' | hermes mcp add obsidian --url "$MCP_URL" --auth header
            HERMES_EXIT=$?
        fi
        if [ "$HERMES_EXIT" -eq 0 ] \
            && hermes mcp list 2>/dev/null | grep -Eq '(^|[[:space:]])obsidian([[:space:]]|$)'; then
            ok "Hermes Agent に obsidian を登録しました"
            CONFIGURED=$((CONFIGURED + 1))
        else
            fail "Hermes Agent への登録に失敗しました"
            FAILED=1
        fi
    fi
else
    skip "Hermes Agent は未導入（任意）のため登録をスキップしました"
fi

unset API_KEY

if [ "$CLIENT_FOUND" -eq 0 ]; then
    fail "対応する MCP クライアントが1つも見つかりませんでした"
    FAILED=1
fi

cat <<EOF

============================================================
 Obsidian MCP の設定処理が完了しました。
   接続先: $MCP_URL

 次に新しいターミナルを開き、次で確認してください:
   claude mcp get obsidian
   codex mcp get obsidian
   hermes mcp test obsidian   # Hermes を導入した場合

 注意:
   - Obsidian を起動している間だけ MCP を利用できます
   - Binding Host は 127.0.0.1 のままにしてください
   - API Key を共有・Git commit しないでください
============================================================
EOF

exit "$FAILED"
