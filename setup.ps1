# ============================================================
# setup.ps1 - 新品Windows用 AI開発環境一括セットアップ
#
# インストール内容:
#   1. WSL2 (Ubuntu)          ※初回は再起動が必要
#   2. Git for Windows        (winget経由)
#   3. Claude Code (ネイティブ版)
#   4. Codex CLI  (ネイティブ版)
#   5. Claude Desktop (GUIアプリ)
#
# 実行方法（管理者PowerShellで）:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# WSL2が未導入の場合、インストール後に再起動を促します。
# 再起動後にもう一度このスクリプトを実行すると残りが入ります。
# 一部が失敗しても続行し、最後に結果一覧を表示します。
# ============================================================

$ErrorActionPreference = "Continue"
$script:Failed = @()

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "  [SKIP] $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "  [NG] $msg" -ForegroundColor Red; }

# 一時的な503等に備えたリトライ付きインストーラー実行
function Invoke-Installer($name, $url) {
    for ($i = 1; $i -le 3; $i++) {
        try {
            $script = Invoke-RestMethod -Uri $url -TimeoutSec 120
            Invoke-Expression $script
            Write-Ok "$name をインストールしました"
            return $true
        } catch {
            Write-Fail "$name のダウンロード/実行に失敗 (試行 $i/3): $($_.Exception.Message)"
            if ($i -lt 3) { Start-Sleep -Seconds 5 }
        }
    }
    Write-Fail "$name のインストールに失敗しました。後で手動実行してください: irm $url | iex"
    $script:Failed += $name
    return $false
}

# ---- 管理者チェック（WSLインストールに必要） ----
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ============================================================
# 1. WSL2
# ============================================================
Write-Step "WSL2 の状態を確認"

$wslInstalled = $false
try {
    $null = & wsl.exe --status 2>$null
    if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
} catch { }

if ($wslInstalled) {
    Write-Ok "WSL2 はインストール済み"
    try { & wsl.exe --update 2>$null | Out-Null; Write-Ok "WSLカーネルを最新化" } catch { }
} else {
    if (-not $isAdmin) {
        Write-Fail "WSL2のインストールには管理者権限が必要です。"
        Write-Host "  PowerShellを「管理者として実行」で開き直して再実行してください。"
        exit 1
    }
    Write-Host "  WSL2 (Ubuntu) をインストールします..."
    & wsl.exe --install -d Ubuntu
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " WSL2のインストールが完了しました。PCの再起動が必要です。" -ForegroundColor Yellow
    Write-Host " 再起動後:" -ForegroundColor Yellow
    Write-Host "   1. スタートメニューから Ubuntu を開き、初期設定（ユーザー名/パスワード）" -ForegroundColor Yellow
    Write-Host "   2. このスクリプトをもう一度実行して残りをインストール" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    $answer = Read-Host "今すぐ再起動しますか? (y/N)"
    if ($answer -eq "y") { Restart-Computer }
    exit 0
}

# ============================================================
# 2. Git for Windows
# ============================================================
Write-Step "Git for Windows"

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Skip "Git はインストール済み ($(git --version))"
} else {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail "winget が見つかりません。Microsoft Storeで「アプリ インストーラー」を更新してください。"
        exit 1
    }
    winget install --id Git.Git -e --source winget `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) { Write-Ok "Git for Windows をインストールしました" }
    else { Write-Fail "Git のインストールに失敗しました (exit=$LASTEXITCODE)"; $script:Failed += "Git" }
}

# ============================================================
# 3. Claude Code（ネイティブ版・Node不要）
# ============================================================
Write-Step "Claude Code"

if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Skip "Claude Code はインストール済み"
} else {
    Invoke-Installer "Claude Code" "https://claude.ai/install.ps1" | Out-Null
}

# ============================================================
# 4. Codex CLI（ネイティブ版・Node不要）
# ============================================================
Write-Step "Codex CLI"

if (Get-Command codex -ErrorAction SilentlyContinue) {
    Write-Skip "Codex CLI はインストール済み"
} else {
    Invoke-Installer "Codex CLI" "https://chatgpt.com/codex/install.ps1" | Out-Null
}

# ============================================================
# 5. Claude Desktop（GUIアプリ）
# ============================================================
Write-Step "Claude Desktop"

$desktopInstalled = winget list --id Anthropic.Claude -e 2>$null | Select-String "Anthropic.Claude"
if ($desktopInstalled) {
    Write-Skip "Claude Desktop はインストール済み"
} else {
    winget install --id Anthropic.Claude -e --source winget `
        --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -eq 0) { Write-Ok "Claude Desktop をインストールしました（スタートメニューから起動できます）" }
    else { Write-Fail "Claude Desktop のインストールに失敗しました (exit=$LASTEXITCODE)"; $script:Failed += "Claude Desktop" }
}

# ============================================================
# 6. PATH の確認・追加（%USERPROFILE%\.local\bin）
# ============================================================
Write-Step "PATH 設定を確認"

$localBin = Join-Path $env:USERPROFILE ".local\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$localBin*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$localBin", "User")
    Write-Ok "PATH に $localBin を追加しました"
} else {
    Write-Skip "PATH は設定済み"
}

# 現セッションのPATHを最新化（インストール直後の検証を正しく行うため）
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path", "User")

# ============================================================
# 7. インストール確認
# ============================================================
Write-Step "インストール結果"

foreach ($cmd in @("git", "claude", "codex")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        try { $v = (& $cmd --version 2>$null | Select-Object -First 1) } catch { $v = "(version取得失敗)" }
        Write-Ok "$cmd : $v"
    } else {
        Write-Fail "$cmd が見つかりません（ターミナル再起動後に再確認してください）"
    }
}

if ($script:Failed.Count -gt 0) {
    Write-Host "`n 失敗した項目: $($script:Failed -join ', ')" -ForegroundColor Red
    Write-Host " ネットワークの一時的な問題の可能性があります。再実行すると成功項目はスキップされます。" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " セットアップ完了！次のステップ:" -ForegroundColor Green
Write-Host "   1. 新しいターミナルを開く（PATH反映のため）" -ForegroundColor Green
Write-Host "   2. claude を実行 → ブラウザでログイン（Pro/Max等が必要）" -ForegroundColor Green
Write-Host "   3. codex  を実行 → ブラウザでログイン（ChatGPT Plus等が必要）" -ForegroundColor Green
Write-Host "   4. スタートメニューから Claude を起動 → アカウントでサインイン" -ForegroundColor Green
Write-Host "" -ForegroundColor Green
Write-Host " WSL側にもCLIを入れる場合は、Ubuntuターミナルで" -ForegroundColor Green
Write-Host "   bash wsl-setup.sh を実行してください。" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
