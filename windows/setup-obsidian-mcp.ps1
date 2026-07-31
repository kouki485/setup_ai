param(
    [switch]$Force
)

# Obsidian の Local REST API 内蔵 MCP を Claude Code / Codex CLI /
# Hermes Agent（導入済みの場合）へ登録する。

$ErrorActionPreference = "Stop"
$script:Failed = $false
$script:Configured = 0
$script:ClientFound = 0

function Write-Ok($message)   { Write-Host "  [OK] $message" -ForegroundColor Green }
function Write-Skip($message) { Write-Host "  [SKIP] $message" -ForegroundColor Yellow }
function Write-Warn($message) { Write-Host "  [注意] $message" -ForegroundColor Yellow }
function Write-Fail($message) { Write-Host "  [NG] $message" -ForegroundColor Red }

function Confirm-Replacement($label) {
    if ($Force) { return $true }
    $answer = Read-Host "  $label に既存の obsidian 設定があります。置き換えますか? (y/N)"
    return ($answer -match "^(y|yes)$")
}

function Test-ServerListed($client) {
    if ($client -eq "hermes") {
        $output = (& hermes mcp list 2>$null | Out-String)
        return [bool]($output -match "(?m)(^|\s)obsidian(\s|$)")
    }
    & $client mcp get obsidian *> $null
    return ($LASTEXITCODE -eq 0)
}

function Invoke-LoopbackGet($uri, $bearerToken = $null) {
    # Windows PowerShell 5.1 の Invoke-WebRequest には -NoProxy がないため、
    # HttpClient でプロキシと自動リダイレクトを明示的に無効化する。
    # API Key が 127.0.0.1 以外へ転送される経路を作らない。
    Add-Type -AssemblyName System.Net.Http
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $handler.AllowAutoRedirect = $false
    $handler.UseDefaultCredentials = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(10)
    $request = $null
    $response = $null
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Get, $uri
        )
        if ($bearerToken) {
            $request.Headers.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new(
                    "Bearer", $bearerToken
                )
        }
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        return [int]$response.StatusCode
    } finally {
        if ($response) { $response.Dispose() }
        if ($request) { $request.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}

$mcpUrl = if ($env:OBSIDIAN_MCP_URL) {
    $env:OBSIDIAN_MCP_URL
} else {
    "http://127.0.0.1:27123/mcp/"
}

try {
    $mcpUri = [Uri]$mcpUrl
} catch {
    Write-Fail "OBSIDIAN_MCP_URL が有効な URL ではありません"
    exit 1
}

# API キーを任意の外部ホストへ送らないよう、ループバックの HTTP
# エンドポイントだけを許可する。自己署名証明書を全クライアントで信頼させる
# 必要をなくすため、プラグインのローカル HTTP を利用する。
if ($mcpUri.Scheme -ne "http" -or
    $mcpUri.Host -ne "127.0.0.1" -or
    $mcpUri.UserInfo -or
    $mcpUri.AbsolutePath -ne "/mcp/" -or
    $mcpUri.Port -lt 1 -or
    $mcpUri.Port -gt 65535 -or
    $mcpUri.Query -or
    $mcpUri.Fragment -or
    $mcpUrl -cne "http://127.0.0.1:$($mcpUri.Port)/mcp/") {
    Write-Fail "OBSIDIAN_MCP_URL は http://127.0.0.1:<port>/mcp/ の形式にしてください"
    exit 1
}

$origin = "{0}://{1}:{2}" -f $mcpUri.Scheme, $mcpUri.Host, $mcpUri.Port
$statusUrl = "$origin/"
$restUrl = "$origin/vault/"

Write-Host ""
Write-Host "Obsidian MCP の接続設定を始めます。" -ForegroundColor Cyan
Write-Host "先に Obsidian で次の設定を完了してください。"
Write-Host "  1. コミュニティプラグイン「Local REST API with MCP」を導入・有効化"
Write-Host "  2. Local REST API の設定で「Enable HTTP server」を有効化"
Write-Host "  3. Binding Host は 127.0.0.1 のまま変更しない"
Write-Host "  4. Authorization header は既定値 Authorization のままにする"
Write-Host "  5. 同じ画面に表示される API Key を用意"
Write-Host ""
Write-Host "プラグイン: https://community.obsidian.md/plugins/obsidian-local-rest-api"

try {
    $statusCode = Invoke-LoopbackGet $statusUrl
    if ($statusCode -lt 200 -or $statusCode -ge 300) {
        throw "HTTP $statusCode"
    }
} catch {
    Write-Fail "Obsidian の Local REST API に接続できません: $statusUrl"
    Write-Host "  Obsidian を起動し、上記 1～3 を確認してから再実行してください。" -ForegroundColor Yellow
    exit 1
}

$apiKey = if ($env:OBSIDIAN_API_KEY) {
    $env:OBSIDIAN_API_KEY
} else {
    $env:SETUP_AI_OBSIDIAN_API_KEY
}
if (-not $apiKey) {
    $secureApiKey = Read-Host "API Key（入力内容は表示されません）" -AsSecureString
    $apiKeyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
    try {
        $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($apiKeyPointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($apiKeyPointer)
    }
}

# 既定の API Key は64桁の16進文字列だが、プラグイン設定で変更できる。
# URL-safe な文字種と十分な長さに限定し、ヘッダー注入を防ぐ。
if ($apiKey -notmatch "^[A-Za-z0-9._~+/=-]{32,256}$") {
    Write-Fail "API Key の形式が不正です（32～256文字の英数字・安全な記号だけを使用してください）"
    exit 1
}

try {
    $statusCode = Invoke-LoopbackGet $restUrl $apiKey
    if ($statusCode -ge 200 -and $statusCode -lt 300) {
        Write-Ok "Local REST API と API Key を確認しました"
    } elseif ($statusCode -in @(401, 403)) {
        Write-Fail "API Key が拒否されました（HTTP $statusCode）"
        exit 1
    } else {
        Write-Fail "Local REST API の認証確認に失敗しました（HTTP $statusCode）"
        exit 1
    }
} catch {
    Write-Fail "Local REST API の認証確認に失敗しました"
    exit 1
}

# 秘密値は MCP 設定やログへ直書きせず、ユーザー環境変数から参照する。
try {
    [Environment]::SetEnvironmentVariable("SETUP_AI_OBSIDIAN_API_KEY", $apiKey, "User")
    [Environment]::SetEnvironmentVariable("MCP_OBSIDIAN_API_KEY", $apiKey, "User")
    $env:SETUP_AI_OBSIDIAN_API_KEY = $apiKey
    $env:MCP_OBSIDIAN_API_KEY = $apiKey
    Write-Ok "API Key をユーザー環境変数へ保存しました"
} catch {
    Write-Fail "API Key をユーザー環境変数へ保存できませんでした"
    exit 1
}

Write-Host ""
Write-Host "MCP クライアントへ登録します。" -ForegroundColor Cyan

if (Get-Command claude -ErrorAction SilentlyContinue) {
    $script:ClientFound++
    $claudeExists = Test-ServerListed "claude"
    if ($claudeExists -and -not (Confirm-Replacement "Claude Code")) {
        Write-Skip "Claude Code の既存設定を維持しました"
    } else {
        if ($claudeExists) {
            & claude mcp remove obsidian --scope user *> $null
        }
        $claudeConfig = @{
            type = "http"
            url = $mcpUrl
            headers = @{
                Authorization = 'Bearer ${SETUP_AI_OBSIDIAN_API_KEY}'
            }
        } | ConvertTo-Json -Compress -Depth 4
        & claude mcp add-json --scope user obsidian $claudeConfig
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Claude Code に obsidian を登録しました（ユーザースコープ）"
            $script:Configured++
        } else {
            Write-Fail "Claude Code への登録に失敗しました"
            $script:Failed = $true
        }
    }
} else {
    Write-Skip "Claude Code が見つからないため登録をスキップしました"
}

if (Get-Command codex -ErrorAction SilentlyContinue) {
    $script:ClientFound++
    $codexExists = Test-ServerListed "codex"
    if ($codexExists -and -not (Confirm-Replacement "Codex CLI")) {
        Write-Skip "Codex CLI の既存設定を維持しました"
    } else {
        if ($codexExists) {
            & codex mcp remove obsidian *> $null
        }
        & codex mcp add obsidian --url $mcpUrl --bearer-token-env-var SETUP_AI_OBSIDIAN_API_KEY
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Codex CLI に obsidian を登録しました"
            $script:Configured++
        } else {
            Write-Fail "Codex CLI への登録に失敗しました"
            $script:Failed = $true
        }
    }
} else {
    Write-Skip "Codex CLI が見つからないため登録をスキップしました"
}

if (Get-Command hermes -ErrorAction SilentlyContinue) {
    $script:ClientFound++
    $hermesExists = Test-ServerListed "hermes"
    if ($hermesExists -and -not (Confirm-Replacement "Hermes Agent")) {
        Write-Skip "Hermes Agent の既存設定を維持しました"
    } else {
        if ($hermesExists) {
            "y" | & hermes mcp remove obsidian *> $null
        }
        if ($Force) {
            @("", "") | & hermes mcp add obsidian --url $mcpUrl --auth header
        } else {
            Write-Host "  Hermes の質問では、必要なら select を選んで利用ツールを絞れます。" -ForegroundColor DarkGray
            & hermes mcp add obsidian --url $mcpUrl --auth header
        }
        $hermesExit = $LASTEXITCODE
        if ($hermesExit -eq 0 -and (Test-ServerListed "hermes")) {
            Write-Ok "Hermes Agent に obsidian を登録しました"
            $script:Configured++
        } else {
            Write-Fail "Hermes Agent への登録に失敗しました"
            $script:Failed = $true
        }
    }
} else {
    Write-Skip "Hermes Agent は未導入（任意）のため登録をスキップしました"
}

$apiKey = $null
$secureApiKey = $null
$statusCode = $null

if ($script:ClientFound -eq 0) {
    Write-Fail "対応する MCP クライアントが1つも見つかりませんでした"
    $script:Failed = $true
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Obsidian MCP の設定処理が完了しました。" -ForegroundColor Green
Write-Host "   接続先: $mcpUrl" -ForegroundColor Green
Write-Host ""
Write-Host " 次に新しいターミナルを開き、次で確認してください:" -ForegroundColor Green
Write-Host "   claude mcp get obsidian" -ForegroundColor Green
Write-Host "   codex mcp get obsidian" -ForegroundColor Green
Write-Host "   hermes mcp test obsidian   # Hermes を導入した場合" -ForegroundColor Green
Write-Host ""
Write-Host " 注意:" -ForegroundColor Yellow
Write-Host "   - Obsidian を起動している間だけ MCP を利用できます" -ForegroundColor Yellow
Write-Host "   - Binding Host は 127.0.0.1 のままにしてください" -ForegroundColor Yellow
Write-Host "   - API Key を共有・Git commit しないでください" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green

if ($script:Failed) { exit 1 }
exit 0
