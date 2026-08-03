# AI 開発環境セットアップ

Windows / Mac に、Claude を使った開発環境をまとめて導入します。

[**セットアップ ZIP をダウンロード**](https://github.com/kouki485/setup_ai/releases/latest/download/AI-Dev-Setup.zip)

## 入るもの

| ツール | Windows | Mac |
|---|:---:|:---:|
| Claude Code / Claude Desktop | ○ | ○ |
| Git / Node.js LTS / GitHub CLI | ○ | ○ |
| Vercel CLI / Supabase CLI | ○ | ○ |
| WSL2（Ubuntu） | ○ | — |
| Homebrew / Xcode Command Line Tools | — | ○ |

`claude` などをコマンド名だけで実行できるよう、PATH も設定します。

## セットアップ手順

1. [**AI-Dev-Setup.zip をダウンロード**](https://github.com/kouki485/setup_ai/releases/latest/download/AI-Dev-Setup.zip)
2. ZIP をフォルダごと展開する
3. **`Start.html` をダブルクリック**（ブラウザで開きます）
4. 画面の案内に従う
5. 終わったら新しいターミナルで `claude` と入力してログインする

> Mac で `Start_Mac.command` をダブルクリックすると「検証できません」で止まることがあります（Apple の仕様）。そのときは **`Start.html` を開く**か、`Start_Mac.command` を右クリック →「開く」で進めてください。


### Mac で警告が出る場合

「Appleは悪質なソフトウェアが含まれていないことを検証できませんでした」と表示されたら、次の順に操作します。

1. 警告画面で「完了」を押す
2. **システム設定 → プライバシーとセキュリティ**を開く
3. 下へスクロールして**このまま開く**を押す
4. 確認画面で**開く**を押す

初回のみ必要です。警告なしで配布するには、Apple Developer ID による署名とノータリゼーションが必要です。

## コマンドから実行する場合

Windows:

```powershell
curl.exe -fsSL -o "$env:TEMP\install.bat" https://raw.githubusercontent.com/kouki485/setup_claude/main/windows/install.bat
& "$env:TEMP\install.bat"
```

Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/kouki485/setup_claude/main/mac/mac-setup.sh -o mac-setup.sh
bash mac-setup.sh
```

WSL / Ubuntu 内にも CLI を入れる場合:

```bash
curl -fsSL https://raw.githubusercontent.com/kouki485/setup_claude/main/windows/wsl-setup.sh -o wsl-setup.sh
bash wsl-setup.sh
source ~/.bashrc
```

## 動作条件と注意

- Windows 10 1809 以降、macOS 13 以降、Ubuntu 20.04 以降に対応
- WSL2 は Windows 10 ビルド 19041 以降で導入
- Mac では Homebrew 導入時にログインパスワードが必要
- Windows で WSL2 を初めて入れた場合は、完了後に再起動が必要
- Windows Arm64 では Vercel CLI のネイティブ版は導入対象外
- Claude Code の利用には対応する Claude プランまたは API 契約が必要
- 実行ログはデスクトップの `ai-setup-log.txt` に保存

失敗した場合は、ネットワークを確認して同じファイルを再実行してください。導入済みの項目はスキップされます。

## 配布 ZIP の更新

```bash
bash scripts/build-dist.sh
```

生成先: `dist/AI-Dev-Setup.zip`
