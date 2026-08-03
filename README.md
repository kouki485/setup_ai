# AI 開発環境セットアップ

Windows / Mac に、Claude を使った開発環境をまとめて導入します。

## Mac（いちばんかんたん）

ターミナル（Launchpad → その他 → ターミナル）を開き、次の **1 行** を貼り付けて Enter してください。

```bash
curl -fsSL https://raw.githubusercontent.com/kouki485/setup_ai/v2.0.2/mac/mac-setup.sh -o /tmp/ai-mac-setup.sh && bash /tmp/ai-mac-setup.sh
```

Gatekeeper の警告は出ません（Homebrew と同じ入れ方です）。  
終わったら新しいターミナルを開き、`claude` でログインしてください。

> `Start_Mac.command` のダブルクリックが止まるのは Apple の仕様です。警告なしのダブルクリックにするには Apple Developer の署名・公証が必要です。

## Windows（いちばんかんたん）

PowerShell で次を実行するか、下の ZIP を使ってください。

```powershell
curl.exe -fsSL -o "$env:TEMP\install.bat" https://raw.githubusercontent.com/kouki485/setup_ai/v2.0.2/windows/install.bat
& "$env:TEMP\install.bat"
```

または [**AI-Dev-Setup.zip**](https://github.com/kouki485/setup_ai/releases/latest/download/AI-Dev-Setup.zip) を展開して `Start_Windows.bat` をダブルクリック。  
SmartScreen が出たら「詳細情報」→「実行」。WSL の UAC は「はい」。

## 入るもの

| ツール | Windows | Mac |
|---|:---:|:---:|
| Claude Code / Claude Desktop | ○ | ○ |
| Git / Node.js LTS / GitHub CLI | ○ | ○ |
| Vercel CLI / Supabase CLI | ○ | ○ |
| WSL2（Ubuntu） | ○ | — |
| Homebrew / Xcode Command Line Tools | — | ○ |

`claude` などをコマンド名だけで実行できるよう、PATH も設定します。

## ZIP で入れたい場合

[**AI-Dev-Setup.zip をダウンロード**](https://github.com/kouki485/setup_ai/releases/latest/download/AI-Dev-Setup.zip)

1. フォルダごと展開
2. **`Start.html` を開く**（案内どおりに進む）
3. 完了後、新しいターミナルで `claude` ログイン

Mac で `Start_Mac.command` をダブルクリックして止まっても、`Start.html` か上の 1 行コマンドを使えば進められます。

## WSL / Ubuntu の中にも入れる場合

```bash
curl -fsSL https://raw.githubusercontent.com/kouki485/setup_ai/v2.0.2/windows/wsl-setup.sh -o /tmp/ai-wsl-setup.sh && bash /tmp/ai-wsl-setup.sh
source ~/.bashrc
```

## 動作条件と注意

- Windows 10 1809 以降、macOS 13 以降、Ubuntu 20.04 以降
- Mac では Homebrew 導入時にログインパスワードが必要
- Windows で WSL2 を初めて入れた場合は再起動が必要
- Windows Arm64 では Vercel CLI のネイティブ版は対象外
- Claude Code の利用には対応プランまたは API 契約が必要
- 実行ログはデスクトップの `ai-setup-log.txt`

失敗したら同じコマンドをもう一度実行してください（導入済みはスキップされます）。

## 配布 ZIP の更新

```bash
bash scripts/build-dist.sh
```

生成先: `dist/AI-Dev-Setup.zip`
