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

# 実行ログをデスクトップに残す。社内で複数台に配る際、失敗した端末の状況を
# 後から確認できるようにするため。exit で抜けてもプロセス終了時に自動で閉じる。
$script:LogPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "ai-setup-log.txt"
try { Start-Transcript -Path $script:LogPath -Force | Out-Null } catch { }

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "  [SKIP] $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "  [NG] $msg" -ForegroundColor Red; }

# 一時的な503等に備えたリトライ付きインストーラー実行
#
# 値を返さないのは意図的。呼び出し側で `| Out-Null` すると戻り値だけでなく
# インストーラ本体の出力まで捨てられ、進捗が何も見えなくなるため。
# 失敗は $script:Failed に記録して呼び出し側に伝える。
function Invoke-Installer($name, $url) {
    for ($i = 1; $i -le 3; $i++) {
        try {
            Write-Host "  インストーラを取得しています..." -ForegroundColor DarkGray
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $installScript = Invoke-RestMethod -Uri $url -TimeoutSec 120
            Write-Host "  取得完了 ($([int]$sw.Elapsed.TotalSeconds)秒)。インストールを実行します。" -ForegroundColor DarkGray
            Write-Host "  ダウンロードと展開に 1〜3 分かかります。画面が止まって見えても正常です。" -ForegroundColor DarkGray

            # 出力をそのまま流す。ここを Out-Null すると無言になり、
            # 利用者が固まったと誤解して強制終了してしまう。
            Invoke-Expression $installScript

            Write-Ok "$name をインストールしました ($([int]$sw.Elapsed.TotalSeconds)秒)"
            return
        } catch {
            Write-Fail "$name のダウンロード/実行に失敗 (試行 $i/3): $($_.Exception.Message)"
            if ($i -lt 3) {
                Write-Host "  5秒後に再試行します..." -ForegroundColor DarkGray
                Start-Sleep -Seconds 5
            }
        }
    }
    Write-Fail "$name のインストールに失敗しました。後で手動実行してください: irm $url | iex"
    $script:Failed += $name
}

# ---- 管理者チェック（WSLインストールに必要） ----
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ============================================================
# 1. WSL2
# ============================================================
Write-Step "WSL2 の状態を確認"

# WSL は「機能が有効か」と「ディストリビューションが入っているか」を別に確認する。
# `wsl --status` は機能が有効なだけで exit 0 を返すため、これだけで判定すると
# Ubuntu が未導入なのに「インストール済み」と誤判定してしまう。
$wslInstalled = $false
$distroInstalled = $false
$distroList = ""

try {
    $null = & wsl.exe --status 2>$null
    if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
} catch { }

if ($wslInstalled) {
    try {
        # --list --quiet の出力は UTF-16LE のため NUL を除いてから中身を判定する
        $distroList = (& wsl.exe --list --quiet 2>$null | Out-String).Replace("`0", "").Trim()
        if ($LASTEXITCODE -eq 0 -and $distroList) { $distroInstalled = $true }
    } catch { }
}

if ($wslInstalled -and $distroInstalled) {
    Write-Ok "WSL2 はインストール済み"
    Write-Host "  WSLカーネルの更新を確認しています（数分かかることがあります）..." -ForegroundColor DarkGray
    try { & wsl.exe --update 2>$null | Out-Null; Write-Ok "WSLカーネルを最新化" } catch { }
} elseif ($wslInstalled) {
    # WSL 本体は有効。ディストリビューションを足すだけなので再起動は不要。
    if (-not $isAdmin) {
        Write-Fail "Ubuntu のインストールには管理者権限が必要です。"
        Write-Host "  PowerShellを「管理者として実行」で開き直して再実行してください。"
        exit 1
    }
    Write-Host "  WSL2 は有効ですが Ubuntu が入っていません。Ubuntu を追加します..."
    # --no-launch は初回起動の対話設定を挟まずに導入する（未対応の WSL では無しで再試行）
    & wsl.exe --install -d Ubuntu --no-launch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  --no-launch が使えないため通常の方法で再試行します..."
        & wsl.exe --install -d Ubuntu
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Ubuntu をインストールしました"
        Write-Host "  ※ 初回だけスタートメニューから Ubuntu を開き、ユーザー名とパスワードの設定が必要です" -ForegroundColor Yellow
    } else {
        Write-Fail "Ubuntu のインストールに失敗しました (exit=$LASTEXITCODE)"
        $script:Failed += "Ubuntu"
    }
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

# winget の有無を先に判定する。無い場合でも Claude Code / Codex CLI は
# インストーラを直接ダウンロードするため導入できる。ここで中断してはいけない。
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
if (-not $hasWinget) {
    Write-Fail "winget が見つかりません。Git と Claude Desktop はスキップして続行します。"
    Write-Host "  Microsoft Store で「アプリ インストーラー」を入れると次回から導入できます。" -ForegroundColor Yellow
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Skip "Git はインストール済み ($(git --version))"
} elseif (-not $hasWinget) {
    Write-Skip "Git は winget が無いためスキップしました"
    $script:Failed += "Git (winget なし)"
} else {
    Write-Host "  Git をダウンロードしています（約60MB、数分かかります）..." -ForegroundColor DarkGray
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
    Invoke-Installer "Claude Code" "https://claude.ai/install.ps1"
}

# ============================================================
# 4. Codex CLI（ネイティブ版・Node不要）
# ============================================================
Write-Step "Codex CLI"

if (Get-Command codex -ErrorAction SilentlyContinue) {
    Write-Skip "Codex CLI はインストール済み"
} else {
    Invoke-Installer "Codex CLI" "https://chatgpt.com/codex/install.ps1"
}

# ============================================================
# 5. Claude Desktop（GUIアプリ）
# ============================================================
Write-Step "Claude Desktop"

$desktopInstalled = $null
if ($hasWinget) {
    $desktopInstalled = winget list --id Anthropic.Claude -e 2>$null | Select-String "Anthropic.Claude"
}
if (-not $hasWinget) {
    Write-Skip "Claude Desktop は winget が無いためスキップしました"
    $script:Failed += "Claude Desktop (winget なし)"
} elseif ($desktopInstalled) {
    Write-Skip "Claude Desktop はインストール済み"
} else {
    Write-Host "  Claude Desktop をダウンロードしています（数分かかります）..." -ForegroundColor DarkGray
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
        if ($cmd -eq "git" -and -not $hasWinget) { Write-Host "        → winget が無いため未導入です" -ForegroundColor DarkGray }
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
Write-Host "      ※ 今の画面でそのまま試すなら、次の1行を貼り付けてください:" -ForegroundColor DarkGray
Write-Host '        $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")' -ForegroundColor DarkGray
Write-Host "   2. claude を実行 → ブラウザでログイン（Pro/Max等が必要）" -ForegroundColor Green
Write-Host "   3. codex  を実行 → ブラウザでログイン（ChatGPT Plus等が必要）" -ForegroundColor Green
Write-Host "   4. スタートメニューから Claude を起動 → アカウントでサインイン" -ForegroundColor Green
Write-Host "" -ForegroundColor Green
Write-Host " WSL側にもCLIを入れる場合は、Ubuntuターミナルで" -ForegroundColor Green
Write-Host "   bash wsl-setup.sh を実行してください（windows フォルダ内にあります）。" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host " 実行ログ: $script:LogPath" -ForegroundColor DarkGray
Write-Host " うまくいかない場合はこのファイルを管理者に送ってください。" -ForegroundColor DarkGray

try { Stop-Transcript | Out-Null } catch { }
