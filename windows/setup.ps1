# ============================================================
# setup.ps1 - 新品Windows用 AI開発環境一括セットアップ
#
# インストール内容:
#   1. WSL2 (Ubuntu)          ※初回は再起動が必要
#   2. Git for Windows        (winget経由)
#   3. Node.js LTS            (winget経由 / npm 配布CLIの導入に使用)
#   4. GitHub CLI (gh)        (winget経由)
#   5. Supabase CLI           (公式 GitHub Release / SHA-256検証)
#   6. Vercel CLI             (公式ネイティブ npm パッケージ)
#   7. Claude Code (ネイティブ版)
#   8. Codex CLI  (ネイティブ版)
#   9. Claude Desktop (GUIアプリ)
#
# 対応 OS: Windows 10 1809 (ビルド 17763) 以上。実行前にバージョンを確認します。
# WSL2 はビルド 19041 以上でのみインストールします。
#
# 実行方法（通常のPowerShellで。WSL導入時だけUACを表示）:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# WSL2が未導入の場合も Windows 向けツールの導入を続け、
# 最後に再起動を促します。
# 一部が失敗しても続行し、最後に結果一覧を表示します。
# ============================================================

$ErrorActionPreference = "Continue"
$script:Failed = @()
$script:RestartRequired = $false
$VercelNativeVersion = "58.4.0"
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Host "このスクリプトは Windows 専用です。" -ForegroundColor Red
    exit 1
}
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# 実行ログをデスクトップに残す。社内で複数台に配る際、失敗した端末の状況を
# 後から確認できるようにするため。exit で抜けてもプロセス終了時に自動で閉じる。
$script:LogPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "ai-setup-log.txt"
try { Start-Transcript -Path $script:LogPath -Force | Out-Null } catch { }

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "  [SKIP] $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "  [NG] $msg" -ForegroundColor Red; }

function Add-Failure($name) {
    if ($script:Failed -notcontains $name) {
        $script:Failed += $name
    }
}

# 取得途中のスクリプトや、`exit` を含むスクリプトを現在のプロセスで
# 評価しない。完全に保存して構文確認した後、子 PowerShell で実行する。
function Invoke-Installer($name, $url, $expectedCommand, $arguments = @()) {
    for ($i = 1; $i -le 3; $i++) {
        $tempScript = Join-Path ([IO.Path]::GetTempPath()) "setup-ai-$([Guid]::NewGuid().ToString('N')).ps1"
        try {
            Write-Host "  インストーラを取得しています..." -ForegroundColor DarkGray
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $tempScript `
                -TimeoutSec 120 -ErrorAction Stop

            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $tempScript, [ref]$tokens, [ref]$parseErrors
            ) | Out-Null
            if ($parseErrors.Count -gt 0) {
                throw "取得したファイルは有効な PowerShell スクリプトではありません"
            }

            Write-Host "  取得完了 ($([int]$sw.Elapsed.TotalSeconds)秒)。インストールを実行します。" -ForegroundColor DarkGray
            Write-Host "  ダウンロードと展開に 1〜3 分かかります。画面が止まって見えても正常です。" -ForegroundColor DarkGray

            $powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $tempScript @arguments
            if ($LASTEXITCODE -ne 0) {
                throw "インストーラが終了コード $LASTEXITCODE を返しました"
            }

            Update-SessionPath
            if (-not (Get-Command $expectedCommand -ErrorAction SilentlyContinue)) {
                throw "インストーラ完了後も '$expectedCommand' が見つかりません"
            }
            Write-Ok "$name をインストールしました ($([int]$sw.Elapsed.TotalSeconds)秒)"
            return
        } catch {
            Write-Fail "$name のダウンロード/実行に失敗 (試行 $i/3): $($_.Exception.Message)"
            if ($i -lt 3) {
                Write-Host "  5秒後に再試行します..." -ForegroundColor DarkGray
                Start-Sleep -Seconds 5
            }
        } finally {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Fail "$name のインストールに失敗しました"
    Add-Failure $name
}

function Save-RemoteFile($url, $destination) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $destination `
                -TimeoutSec 120 -ErrorAction Stop
            return
        } catch {
            Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
            if ($attempt -eq 3) { throw }
            Write-Host "  ダウンロード失敗。5秒後に再試行します ($attempt/3)..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 5
        }
    }
}

# winget や npm でインストールした直後は、そのツールがこのセッションの
# PATH にまだ入っていない。後続の処理から使えるように再構築する。
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Invoke-WslInstall($arguments) {
    if ($isAdmin) {
        & "$env:SystemRoot\System32\wsl.exe" @arguments | Out-Host
        return $LASTEXITCODE
    }

    try {
        $process = Start-Process -FilePath "$env:SystemRoot\System32\wsl.exe" `
            -ArgumentList $arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop
        return $process.ExitCode
    } catch {
        Write-Fail "WSL の管理者実行に失敗しました: $($_.Exception.Message)"
        return 1
    }
}

# ---- 管理者チェック（WSLインストールに必要） ----
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ============================================================
# 0. 実行環境（OSバージョン）の確認
#
# 古い Windows では Claude Code (ビルド 17763 以上) や WSL2 (ビルド
# 19041 以上) が動かない。入らないものをダウンロードする前にここで
# 判定して、非対応なら中断・一部非対応ならその機能だけスキップする。
# ============================================================
Write-Step "実行環境の確認"

$osBuild = [Environment]::OSVersion.Version.Build
$osCaption = "Windows (詳細不明)"
try {
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $osCaption = $osInfo.Caption.Trim()
} catch { }
Write-Ok "$osCaption / ビルド $osBuild / $env:PROCESSOR_ARCHITECTURE"

if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Fail "32ビット版 Windows は非対応です。64ビット版 Windows が必要です。"
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

if ($osBuild -lt 17763) {
    Write-Fail "この Windows (ビルド $osBuild) は非対応です。Claude Code には Windows 10 1809 (ビルド 17763) 以上が必要です。"
    Write-Host "  Windows Update で更新してから再実行してください。" -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

$wsl2Supported = ($osBuild -ge 19041)
if (-not $wsl2Supported) {
    Write-Fail "この Windows (ビルド $osBuild) では WSL2 が使えません (ビルド 19041 以上が必要)。WSL2 はスキップして続行します。"
    Add-Failure "WSL2 (OS非対応)"
}

# ============================================================
# 1. PATH の確認・追加（%USERPROFILE%\.local\bin）
#
# インストールより前に登録する。Claude Code / Codex CLI はここへ入るが、
# 途中で中断された場合に PATH だけ設定されないと、実体があるのに
# コマンドが見つからない状態になる。ディレクトリが未作成でも登録は可能。
# ============================================================
Write-Step "PATH 設定を確認"

$localBin = Join-Path $env:USERPROFILE ".local\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$userPathEntries = @($userPath -split ";" | Where-Object { $_ })
if ($userPathEntries -notcontains $localBin) {
    $updatedUserPath = @($userPathEntries + $localBin) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $updatedUserPath, "User")
    Write-Ok "PATH に $localBin を追加しました"
} else {
    Write-Skip "PATH は設定済み"
}

# このセッションの PATH も更新しておく（後段の検証を正しく行うため）
Update-SessionPath

# ============================================================
# 2. WSL2
# ============================================================
Write-Step "WSL2 の状態を確認"

# WSL は「機能が有効か」と「ディストリビューションが入っているか」を別に確認する。
# `wsl --status` は機能が有効なだけで exit 0 を返すため、これだけで判定すると
# Ubuntu が未導入なのに「インストール済み」と誤判定してしまう。
$wslInstalled = $false
$ubuntuInstalled = $false
$distroNames = @()

try {
    $null = & wsl.exe --status 2>$null
    if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
} catch { }

if ($wslInstalled) {
    try {
        # --list --quiet の出力は UTF-16LE のため NUL を除いてから中身を判定する
        $rawDistroList = & wsl.exe --list --quiet 2>$null
        $listExitCode = $LASTEXITCODE
        if ($listExitCode -eq 0) {
            $distroNames = @($rawDistroList | ForEach-Object {
                $_.ToString().Replace("`0", "").Trim()
            } | Where-Object { $_ })
            $ubuntuInstalled = [bool]($distroNames | Where-Object {
                $_ -match "^Ubuntu(?:-.+)?$"
            })
        }
    } catch { }
}

if (-not $wsl2Supported) {
    Write-Skip "WSL2 はこの Windows のバージョンでは利用できないためスキップします"
} elseif ($wslInstalled -and $ubuntuInstalled) {
    Write-Ok "WSL2 と Ubuntu はインストール済み"
    Write-Host "  WSLカーネルの更新を確認しています（数分かかることがあります）..." -ForegroundColor DarkGray
    $wslUpdateExitCode = Invoke-WslInstall @("--update")
    if ($wslUpdateExitCode -eq 0) {
        Write-Ok "WSLカーネルを最新化"
    } else {
        Write-Fail "WSLカーネルの更新に失敗しました (exit=$wslUpdateExitCode)"
        Add-Failure "WSL update"
    }
} elseif ($wslInstalled) {
    # WSL 本体は有効。ディストリビューションを足すだけなので再起動は不要。
    Write-Host "  WSL2 は有効ですが Ubuntu が入っていません。Ubuntu を追加します..."
    # --no-launch は初回起動の対話設定を挟まずに導入する（未対応の WSL では無しで再試行）
    $ubuntuExitCode = Invoke-WslInstall @("--install", "-d", "Ubuntu", "--no-launch")
    if ($ubuntuExitCode -ne 0) {
        Write-Host "  --no-launch が使えないため通常の方法で再試行します..."
        $ubuntuExitCode = Invoke-WslInstall @("--install", "-d", "Ubuntu")
    }
    if ($ubuntuExitCode -eq 0) {
        Write-Ok "Ubuntu をインストールしました"
        Write-Host "  ※ 初回だけスタートメニューから Ubuntu を開き、ユーザー名とパスワードの設定が必要です" -ForegroundColor Yellow
    } else {
        Write-Fail "Ubuntu のインストールに失敗しました (exit=$ubuntuExitCode)"
        Add-Failure "Ubuntu"
    }
} else {
    Write-Host "  WSL2 (Ubuntu) をインストールします..."
    $wslInstallExitCode = Invoke-WslInstall @("--install", "-d", "Ubuntu")
    if ($wslInstallExitCode -ne 0) {
        Write-Fail "WSL2 のインストールに失敗しました (exit=$wslInstallExitCode)"
        Add-Failure "WSL2"
    } else {
        $script:RestartRequired = $true
        Write-Ok "WSL2 と Ubuntu をインストールしました"
        Write-Host "  Windows 向けツールの導入を続け、最後に再起動を案内します。" -ForegroundColor Yellow
    }
}

# ============================================================
# 3. Git for Windows
# ============================================================
Write-Step "Git for Windows"

# winget の有無を先に判定する。無い場合でも Claude Code / Codex CLI は
# インストーラを直接ダウンロードするため導入できる。ここで中断してはいけない。
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
if (-not $hasWinget) {
    Write-Fail "winget が見つかりません。Git / Node.js / GitHub CLI / Claude Desktop はスキップします。"
    Write-Host "  Microsoft Store で「アプリ インストーラー」を入れると次回から導入できます。" -ForegroundColor Yellow
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Skip "Git はインストール済み ($(git --version))"
} elseif (-not $hasWinget) {
    Write-Skip "Git は winget が無いためスキップしました"
    Add-Failure "Git (winget なし)"
} else {
    Write-Host "  Git をダウンロードしています（約60MB、数分かかります）..." -ForegroundColor DarkGray
    winget install --id Git.Git -e --source winget `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Update-SessionPath
        Write-Ok "Git for Windows をインストールしました"
    }
    else { Write-Fail "Git のインストールに失敗しました (exit=$LASTEXITCODE)"; Add-Failure "Git" }
}

# ============================================================
# 4. Node.js LTS（npm 配布 CLI の導入に使用）
# ============================================================
Write-Step "Node.js (LTS)"

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$nodeMajor = 0
$nodeVersion = ""
if ($nodeCommand) {
    $nodeVersion = & node --version 2>$null
}
if ($nodeVersion -match "^v(\d+)") {
    $nodeMajor = [int]$Matches[1]
}

if ($nodeMajor -ge 22) {
    Write-Skip "Node.js はインストール済み ($nodeVersion)"
} elseif (-not $hasWinget) {
    Write-Skip "Node.js は winget が無いためスキップしました"
    Add-Failure "Node.js (winget なし)"
} else {
    if ($nodeCommand) {
        Write-Host "  既存の Node.js は古いため、サポート中の LTS へ更新します ($nodeVersion)" -ForegroundColor Yellow
    }
    Write-Host "  Node.js LTS をダウンロードしています（数分かかります）..." -ForegroundColor DarkGray
    if ($nodeCommand) {
        winget upgrade --id OpenJS.NodeJS.LTS -e --source winget `
            --accept-package-agreements --accept-source-agreements
        $nodeInstallExitCode = $LASTEXITCODE
        if ($nodeInstallExitCode -ne 0) {
            winget install --id OpenJS.NodeJS.LTS -e --source winget --force `
                --accept-package-agreements --accept-source-agreements
            $nodeInstallExitCode = $LASTEXITCODE
        }
    } else {
        winget install --id OpenJS.NodeJS.LTS -e --source winget `
            --accept-package-agreements --accept-source-agreements
        $nodeInstallExitCode = $LASTEXITCODE
    }
    Update-SessionPath  # 後段の npm (Vercel CLI) から使えるようにする
    $installedNodeVersion = ""
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $installedNodeVersion = & node --version 2>$null
    }
    if ($nodeInstallExitCode -eq 0 -and $installedNodeVersion -match "^v(\d+)" -and [int]$Matches[1] -ge 22) {
        Write-Ok "Node.js をインストールしました ($installedNodeVersion)"
    } else {
        Write-Fail "Node.js のインストールまたはバージョン確認に失敗しました (exit=$nodeInstallExitCode)"
        Add-Failure "Node.js"
    }
}

# ============================================================
# 5. GitHub CLI (gh)
# ============================================================
Write-Step "GitHub CLI (gh)"

if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Skip "GitHub CLI はインストール済み ($(gh --version 2>$null | Select-Object -First 1))"
} elseif (-not $hasWinget) {
    Write-Skip "GitHub CLI は winget が無いためスキップしました"
    Add-Failure "GitHub CLI (winget なし)"
} else {
    Write-Host "  GitHub CLI をダウンロードしています..." -ForegroundColor DarkGray
    winget install --id GitHub.cli -e --source winget `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Update-SessionPath
        Write-Ok "GitHub CLI をインストールしました"
    }
    else { Write-Fail "GitHub CLI のインストールに失敗しました (exit=$LASTEXITCODE)"; Add-Failure "GitHub CLI" }
}

# ============================================================
# 6. Supabase CLI（公式 GitHub Release）
#
# 公式 Release API からこの OS 用の ZIP と SHA-256 を取得する。
# 配布元 URL を制限し、照合後の実行ファイルだけをユーザー領域へ置く。
# ============================================================
Write-Step "Supabase CLI"

if (Get-Command supabase -ErrorAction SilentlyContinue) {
    Write-Skip "Supabase CLI はインストール済み"
} else {
    $supabaseArchitecture = @{
        "AMD64" = "amd64"
        "ARM64" = "arm64"
    }[$env:PROCESSOR_ARCHITECTURE]
    if (-not $supabaseArchitecture) {
        Write-Fail "Supabase CLI はこのアーキテクチャに対応していません: $env:PROCESSOR_ARCHITECTURE"
        Add-Failure "Supabase CLI (非対応アーキテクチャ)"
    } else {
        $supabaseTemp = Join-Path ([IO.Path]::GetTempPath()) "setup-ai-supabase-$([Guid]::NewGuid().ToString('N'))"
        try {
            New-Item -ItemType Directory -Path $supabaseTemp -ErrorAction Stop | Out-Null
            $releaseFile = Join-Path $supabaseTemp "release.json"
            $archiveFile = Join-Path $supabaseTemp "supabase.zip"
            $extractDir = Join-Path $supabaseTemp "extract"

            Write-Host "  公式 Release 情報と SHA-256 を取得しています..." -ForegroundColor DarkGray
            Save-RemoteFile "https://api.github.com/repos/supabase/cli/releases/latest" $releaseFile
            $release = Get-Content -LiteralPath $releaseFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $assetPattern = "^supabase_[0-9]+\.[0-9]+\.[0-9]+_windows_$supabaseArchitecture\.zip$"
            $assets = @($release.assets | Where-Object { $_.name -match $assetPattern })
            if ($assets.Count -ne 1) {
                throw "対象の Windows 配布物を一意に特定できませんでした"
            }

            $asset = $assets[0]
            $assetUri = [Uri][string]$asset.browser_download_url
            $digestMatch = [regex]::Match([string]$asset.digest, "^sha256:([0-9a-fA-F]{64})$")
            if ($assetUri.Scheme -ne "https" -or
                $assetUri.Host -ne "github.com" -or
                -not $assetUri.AbsolutePath.StartsWith("/supabase/cli/releases/download/") -or
                -not $assetUri.AbsolutePath.EndsWith("/$($asset.name)") -or
                -not $digestMatch.Success) {
                throw "配布元 URL または SHA-256 の形式が不正です"
            }

            Save-RemoteFile $assetUri.AbsoluteUri $archiveFile
            $actualHash = (Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256).Hash
            if ($actualHash -ine $digestMatch.Groups[1].Value) {
                throw "SHA-256 が一致しません"
            }

            Expand-Archive -LiteralPath $archiveFile -DestinationPath $extractDir -ErrorAction Stop
            $binaries = @(Get-ChildItem -LiteralPath $extractDir -Filter "supabase.exe" -File -Recurse)
            if ($binaries.Count -ne 1) {
                throw "アーカイブ内の supabase.exe を一意に特定できませんでした"
            }

            New-Item -ItemType Directory -Path $localBin -Force -ErrorAction Stop | Out-Null
            Copy-Item -LiteralPath $binaries[0].FullName `
                -Destination (Join-Path $localBin "supabase.exe") -Force -ErrorAction Stop
            Update-SessionPath
            if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
                throw "導入後も supabase コマンドが見つかりません"
            }
            Write-Ok "Supabase CLI をインストールしました"
        } catch {
            Write-Fail "Supabase CLI の検証またはインストールに失敗しました: $($_.Exception.Message)"
            Add-Failure "Supabase CLI"
        } finally {
            Remove-Item -LiteralPath $supabaseTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# 7. Vercel CLI（公式ネイティブ npm パッケージ）
#
# Node.js 版の vercel パッケージではなく、依存関係を持たない公式
# ネイティブ版を固定して入れる。ライフサイクルスクリプトも実行しない。
# 現在の Windows 向けネイティブ配布は x64 のみ。
# ============================================================
Write-Step "Vercel CLI"

if (Get-Command vercel -ErrorAction SilentlyContinue) {
    Write-Skip "Vercel CLI はインストール済み"
} elseif (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Fail "npm が見つからないため Vercel CLI をスキップしました"
    Add-Failure "Vercel CLI (npm なし)"
} else {
    $nodeArchitecture = (& node -p "process.arch" 2>$null | Select-Object -First 1)
    if ($nodeArchitecture -ne "x64") {
        Write-Fail "Vercel CLI の Windows ネイティブ版は x64 のみ対応です（現在: $nodeArchitecture）"
        Add-Failure "Vercel CLI (非対応アーキテクチャ)"
    } else {
        Write-Host "  公式ネイティブ版 Vercel CLI をダウンロードしています..." -ForegroundColor DarkGray
        npm install -g --ignore-scripts "@vercel/vc-native@$VercelNativeVersion"
        $vercelInstallExitCode = $LASTEXITCODE
        Update-SessionPath
        if ($vercelInstallExitCode -eq 0 -and (Get-Command vercel -ErrorAction SilentlyContinue)) {
            Write-Ok "Vercel CLI をインストールしました"
        } else {
            Write-Fail "Vercel CLI のインストールに失敗しました (exit=$vercelInstallExitCode)"
            Add-Failure "Vercel CLI"
        }
    }
}

# ============================================================
# 8. Claude Code（ネイティブ版・Node不要）
# ============================================================
Write-Step "Claude Code"

if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Skip "Claude Code はインストール済み"
} else {
    if ($hasWinget) {
        winget install --id Anthropic.ClaudeCode -e --source winget `
            --accept-package-agreements --accept-source-agreements
        Update-SessionPath
    }
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Ok "Claude Code をインストールしました"
    } else {
        Invoke-Installer "Claude Code" "https://claude.ai/install.ps1" "claude"
    }
}

# ============================================================
# 9. Codex CLI（ネイティブ版・Node不要）
# ============================================================
Write-Step "Codex CLI"

if (Get-Command codex -ErrorAction SilentlyContinue) {
    Write-Skip "Codex CLI はインストール済み"
} else {
    if ($hasWinget) {
        winget install --id OpenAI.Codex -e --source winget `
            --accept-package-agreements --accept-source-agreements
        Update-SessionPath
    }
    if (Get-Command codex -ErrorAction SilentlyContinue) {
        Write-Ok "Codex CLI をインストールしました"
    } else {
        Invoke-Installer "Codex CLI" "https://chatgpt.com/codex/install.ps1" "codex"
    }
}

# ============================================================
# 10. Claude Desktop（GUIアプリ）
# ============================================================
Write-Step "Claude Desktop"

$desktopInstalled = $null
if ($hasWinget) {
    $desktopInstalled = winget list --id Anthropic.Claude -e 2>$null | Select-String "Anthropic.Claude"
}
if (-not $hasWinget) {
    Write-Skip "Claude Desktop は winget が無いためスキップしました"
    Add-Failure "Claude Desktop (winget なし)"
} elseif ($desktopInstalled) {
    Write-Skip "Claude Desktop はインストール済み"
} else {
    Write-Host "  Claude Desktop をダウンロードしています（数分かかります）..." -ForegroundColor DarkGray
    winget install --id Anthropic.Claude -e --source winget `
        --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -eq 0) { Write-Ok "Claude Desktop をインストールしました（スタートメニューから起動できます）" }
    else { Write-Fail "Claude Desktop のインストールに失敗しました (exit=$LASTEXITCODE)"; Add-Failure "Claude Desktop" }
}

# ============================================================
# 11. インストール確認
# ============================================================
Write-Step "インストール結果"

foreach ($cmd in @("git", "node", "npm", "gh", "vercel", "supabase", "claude", "codex")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        try { $v = (& $cmd --version 2>$null | Select-Object -First 1) } catch { $v = "(version取得失敗)" }
        Write-Ok "$cmd : $v"
    } else {
        Write-Fail "$cmd が見つかりません（ターミナル再起動後に再確認してください）"
        Add-Failure $cmd
        if ($cmd -eq "git" -and -not $hasWinget) { Write-Host "        → winget が無いため未導入です" -ForegroundColor DarkGray }
    }
}

if ($script:Failed.Count -gt 0) {
    Write-Host "`n 失敗した項目: $($script:Failed -join ', ')" -ForegroundColor Red
    Write-Host " ネットワークの一時的な問題の可能性があります。再実行すると成功項目はスキップされます。" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
if ($script:Failed.Count -gt 0) {
    Write-Host " セットアップは一部失敗しました。上の [NG] を確認してください。" -ForegroundColor Red
} else {
    Write-Host " セットアップ完了！次のステップ:" -ForegroundColor Green
}
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

if ($script:RestartRequired) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " WSL2のインストールを反映するため、PCの再起動が必要です。" -ForegroundColor Yellow
    Write-Host " 再起動後、スタートメニューから Ubuntu を開き、" -ForegroundColor Yellow
    Write-Host " ユーザー名とパスワードを設定してください。" -ForegroundColor Yellow
    Write-Host " Windows 向けツールは導入済みなので、このスクリプトの再実行は不要です。" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    $answer = Read-Host "今すぐ再起動しますか? (y/N)"
    if ($answer -eq "y") {
        try {
            Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" `
                -ArgumentList @("/r", "/t", "0") -Verb RunAs -ErrorAction Stop
        } catch {
            Write-Fail "再起動を開始できませんでした。スタートメニューから手動で再起動してください。"
        }
    }
}

try { Stop-Transcript | Out-Null } catch { }
if ($script:Failed.Count -gt 0) { exit 1 }
exit 0
