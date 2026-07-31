# AI 開発環境 セットアップスクリプト（Windows / Mac）

新品の Windows または Mac に、AI でコードを書くための道具をまとめて入れます。手作業で 30 分以上かかる作業が、コマンド 2 行で終わります。

> **インストールが終わったら** → [自分の業務を AI に手伝わせる](prompts/README.md)

## 何が入るか

| | Windows | Mac |
|---|:---:|:---:|
| **Claude Code** — ターミナルで動く AI コーディング支援（Anthropic 製） | ○ | ○ |
| **Codex CLI** — 同上（OpenAI 製） | ○ | ○ |
| **Claude Desktop** — 画面から使うデスクトップアプリ | ○ | ○ |
| **Git** — 変更履歴を管理する道具 | ○ | ○ |
| **Node.js (LTS)** — JavaScript の実行環境（npm 配布 CLI の導入に使用） | ○ | ○ |
| **GitHub CLI (gh)** — GitHub をコマンドで操作する道具 | ○ | ○ |
| **Vercel CLI** — Vercel へのデプロイを行う公式ネイティブ CLI | ○ | ○ |
| **Supabase CLI** — Supabase の開発・管理を行う道具 | ○ | ○ |
| **WSL2 (Ubuntu)** — Windows の中で Linux を動かす仕組み | ○ | — |
| **Homebrew / Xcode Command Line Tools** — Mac のソフト管理の土台 | — | ○ |

あわせて、`claude` などをコマンド名だけで呼び出せるよう **PATH** を設定します。

## 安全性

- Windows の `install.bat` は、取得した `setup.ps1` の SHA-256 が同梱値と一致した場合だけ実行します
- Windows / WSL では Supabase CLI の配布元を公式 GitHub Release に限定し、SHA-256 を照合します
- WSL では Node.js / GitHub CLI / Claude Code の署名鍵を照合します
- Vercel CLI は既知の脆弱な依存ツリーを持つ Node.js 版を避け、`npm audit` で既知脆弱性 0 件を確認した公式ネイティブ版 58.4.0 を固定して導入します
- npm 経由の導入ではパッケージのライフサイクルスクリプトを実行しません
- Windows 全体を管理者として実行せず、WSL の導入・更新操作だけ UAC で昇格します

スクリプトは多数の開発ツールをインストールし、PATH やパッケージリポジトリを変更します。配布元と内容を確認できるこのリポジトリから取得してください。

## 始める前に

スクリプトは実行の最初に OS のバージョンを確認し、対応していない場合は何もインストールせずに止まります。

| 必要なもの | 無いとどうなるか |
|---|---|
| **対応 OS**（Windows 10 1809 以上 / macOS 13 以上 / Ubuntu 20.04 以上） | 最初のバージョン確認で中断します。OS を更新してから再実行してください |
| **UAC を承認できること**（Windows） | WSL2 の導入・更新だけ失敗します。他のユーザー向けツールは通常権限で入ります |
| **アプリ インストーラー**（winget / Windows） | Git / Node.js / GitHub CLI / Claude Desktop がスキップされます |
| **AI サービスの契約** | ツールは入りますが、ログインできません |

Windows 10 ビルド 19041（バージョン 2004）未満では WSL2 だけがスキップされ、他のツールは入ります。macOS 13 は動く可能性が高いものの Homebrew の公式サポート外のため、macOS 14 以上を推奨します。

Vercel の Windows ネイティブ版は現在 x64 のみです。Windows Arm64 では Vercel CLI だけ `[NG]` になりますが、WSL の Arm64 版は利用できます。

契約は Claude Code / Claude Desktop なら **Claude Pro** または **Max**、Codex CLI なら **ChatGPT Plus** などが必要です。

winget は Microsoft Store の「アプリ インストーラー」に含まれます。通常 Windows 10/11 には最初から入っていますが、古いと動かないことがあります。

---

## Windows で入れる

### かんたん版（おすすめ）

1. [install.bat をダウンロード](https://raw.githubusercontent.com/kouki485/setup_ai/main/windows/install.bat)（右クリック →「名前を付けてリンク先を保存」）
2. ダウンロードした `install.bat` を**ダブルクリック**
3. WSL2 の導入・更新で UAC が表示された場合だけ「はい」

本体のダウンロード、SHA-256 検証、実行まで自動で進みます。終わるとデスクトップに `ai-setup-log.txt` が残ります。うまくいかなかったときは、このファイルを担当者に送ってください。

> Windows Defender や SmartScreen の警告が出たら「詳細情報」→「実行」。インターネットから入手したバッチファイルには必ず出ます。

### コマンド版

通常の PowerShell で次の 2 行を実行します。取得した `install.bat` が、セットアップ本体の SHA-256 を検証してから実行します。

```powershell
curl.exe -fsSL -o "$env:TEMP\install.bat" https://raw.githubusercontent.com/kouki485/setup_ai/main/windows/install.bat
& "$env:TEMP\install.bat"
```

<details>
<summary>この 2 行の意味</summary>

- `curl.exe` … 起動ファイルを一旦保存します
- `&` … 保存した起動ファイルを実行します
- 起動ファイルは `setup.ps1` を別の一時ファイルへ保存し、SHA-256 と UTF-8 BOM を確認します。不一致なら実行せず削除します
- ダウンロード内容をその場で評価する `irm ... | iex` は使いません

</details>

### WSL2 が未導入の PC は最後に再起動します

```
1 回実行 → WSL2 と Windows 向けツールがすべて入り、最後に再起動を求められる
再起動   → スタートメニューから「Ubuntu」を開き、ユーザー名とパスワードを決める（必須）
```

パスワードは入力しても画面に何も表示されませんが、ちゃんと入力されています。Windows 向けツールを入れるためにセットアップを 2 回実行する必要はありません。

### 終わったらログイン

**必ず新しいターミナルを開き直してから**（PATH の設定を反映するため）実行します。

```powershell
claude      # ブラウザが開くので Claude アカウントでログイン
codex       # ブラウザが開くので ChatGPT アカウントでログイン
```

Claude Desktop はスタートメニューから起動してサインインします。

---

## Mac で入れる

`install.bat` や `setup.ps1` は Windows 専用です。Mac ではターミナル（アプリケーション → ユーティリティ → ターミナル）で次の 2 行を実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/kouki485/setup_ai/main/mac/mac-setup.sh -o mac-setup.sh
bash mac-setup.sh
```

終わったら**新しいターミナルを開いて**ログインします。

```bash
claude      # ブラウザが開くので Claude アカウントでログイン
codex       # ブラウザが開くので ChatGPT アカウントでログイン
```

Claude Desktop は Launchpad から起動してサインインします。実行ログはデスクトップの `ai-setup-log.txt` に残ります。

<details>
<summary>Mac 特有の注意 3 点</summary>

**パスワードを 1 回聞かれます**

Homebrew の導入時だけ、Mac のログインパスワードを求められます。入力しても画面には何も表示されませんが、ちゃんと入力されています。そのまま Enter を押してください。Homebrew が既に入っている場合は聞かれません。

**Xcode Command Line Tools のダイアログが出ます**

初回のみ「ソフトウェアをインストールしますか？」が表示されます。「インストール」を選んでください。数分かかりますが、スクリプトは完了を自動で待ちます。

**Apple Silicon と Intel でインストール先が変わります**

スクリプトが自動で判定します（Apple Silicon: `/opt/homebrew` / Intel: `/usr/local`）。Apple Silicon では Homebrew のコマンドが初期状態で認識されないため、`~/.zprofile` に設定を自動追記します。今の画面でそのまま試したい場合は `source ~/.zprofile` を実行してください。

</details>

---

## WSL / Ubuntu の中にも入れる

Windows 側とは別に、Ubuntu の中にも入れる作業です。**Ubuntu のターミナル**で実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/kouki485/setup_ai/main/windows/wsl-setup.sh -o wsl-setup.sh
bash wsl-setup.sh
source ~/.bashrc
```

基本パッケージ（`git` / `curl` / `unzip` / `build-essential` など）に加えて、Node.js LTS / GitHub CLI / Supabase CLI / Vercel CLI と、Claude Code / Codex CLI の Linux 版が入ります。終わったら `claude` / `codex` でログインしてください。

> **ヒント**: WSL で作業するときは、ファイルを `/mnt/c/...`（Windows 側のフォルダ）ではなく `~/`（Ubuntu の中）に置いてください。読み書きの速度がはっきり変わります。

---

## うまくいかないとき

**何度実行しても安全です。** 導入済みの項目は `[SKIP]` と表示して飛ばし、直接ダウンロードする処理は通信エラー時に 3 回まで再挑戦します。1 つ失敗しても止まらず最後まで進み、結果の一覧を表示します。`[NG]` が出た項目だけ、あとから対処すれば大丈夫です。

| 症状 | 対処 |
|---|---|
| `claude` コマンドが見つからない | ターミナルを開き直してください。PATH の変更は新しく開いたターミナルにしか反映されません |
| `npm` / `vercel` / `supabase` コマンドが見つからない | 同上。ターミナルを開き直しても見つからない場合は、結果一覧で `[NG]` になっていないか確認して再実行してください |
| 「この Windows（ビルド …）は非対応です」と出て止まる | Windows Update で更新してから再実行してください（Windows 10 1809 以上が必要） |
| 「式またはステートメントのトークン '}' を使用できません」等のエラーが大量に出る | 文字化けです。`irm` ではなく **`curl.exe`** でダウンロードし直してください |
| WSL2 導入時の UAC をキャンセルした | 他のツールの処理は続きます。再実行して UAC を承認するか、IT 部門に WSL2 の導入を依頼してください |
| 「winget が見つかりません」と出て止まる | Microsoft Store で「アプリ インストーラー」を検索して更新してください |
| スクリプトの実行がブロックされる | グループポリシーの制限です。`-ExecutionPolicy Bypass` でも回避できません。IT 部門に相談してください |

<details>
<summary>セットアップ本体の SHA-256 を手動確認する（Windows）</summary>

現在の `install.bat` が許可する値は次の通りです。

```powershell
(Get-FileHash "$env:TEMP\setup.ps1" -Algorithm SHA256).Hash
# 1a0cf414710c79daba01c969e56c7e22f461b788494285f1f28f785c4b98b781
```

一致しないファイルは実行せず削除してください。通常は `install.bat` がこの確認を自動で行います。

</details>

---

## 管理者・IT 担当者向け（複数台に配る場合）

**`install.bat` だけを配れば十分です。** セットアップ本体は実行時に GitHub から取得され、同梱の SHA-256 と一致した場合だけ動きます。共有フォルダ、Slack、Teams、メール添付など普段の経路で構いません。利用者への案内は「ダウンロードしてダブルクリック。WSL の UAC が出た場合だけ『はい』」で足ります。

配布前に確認しておくこと:

| 項目 | 満たさない場合 |
|---|---|
| **Windows 10 1809（ビルド 17763）以降**か | OS バージョン確認で中断します（1803 以前は `curl.exe` が無く `install.bat` の時点で停止します） |
| **ビルド 19041 以降**か | WSL2 だけがスキップされ、他のツールは導入されます |
| 各 PC で **UAC を承認できるか** | WSL2 の導入・更新ができません。IT 側で WSL を先に入れておくこともできます |
| **winget** が使えるか | Git / Node.js / GitHub CLI / Claude Desktop がスキップされ、AI ツールのみ導入されます |
| プロキシや**セキュリティ製品**が通信を書き換えないか | 改変を検知して安全に停止します |
| 各利用者の **AI サービス契約**があるか | ツールは入ってもログインできません |

- 失敗した端末は**再実行するだけで復旧**します（導入済みはスキップされるため）
- **WSL2 未導入の端末もセットアップは 1 回**で、最後に PC の再起動が必要です
- 各端末のデスクトップに `ai-setup-log.txt` が残ります。回収すれば原因を特定できます
- バージョンを固定して配りたい場合は、`install.bat` の `REPO_URL` を `main` からコミットハッシュへ変え、対象 `setup.ps1` の SHA-256 を `EXPECTED_SHA256` に設定します

```bat
rem 例: 特定バージョンに固定する
set "REPO_URL=https://raw.githubusercontent.com/kouki485/setup_ai/e410eff/windows/setup.ps1"
set "EXPECTED_SHA256=対象ファイルのSHA-256"
```

GitHub にアクセスできない環境では、`setup.ps1` と `wsl-setup.sh` を共有フォルダに置き、`REPO_URL` を社内 URL に差し替えてください。その際 `setup.ps1` は **UTF-8 BOM 付きのまま**扱う必要があります（BOM が失われると文字化けして動きません）。

---

## ファイル構成

```
windows/
  install.bat       配布用の起動ファイル（ダブルクリックで実行）
  setup.ps1         セットアップ本体
  wsl-setup.sh      WSL / Ubuntu 内のセットアップ

mac/
  mac-setup.sh      セットアップ本体（Homebrew の導入を含む）

prompts/            OS 共通。業務改善用のプロンプト → prompts/README.md
  business-discovery.md   業務ヒアリング（深掘り）
  ax-proposal.md          AX 提案（AI 活用の設計）

tests/
  static-checks.sh  危険な実行パターン・文字コード・配布用SHA-256の回帰テスト

.gitattributes      文字コードと改行を保護する設定
```

<details>
<summary>.gitattributes は何をしているか（技術的な補足）</summary>

`setup.ps1` は **UTF-8 BOM 付き・CRLF 改行**で保存されています。Windows PowerShell 5.1 は BOM が無い UTF-8 を日本語環境の文字コード（CP932）として読んでしまい、日本語のコメントや文字列が壊れるためです。

`wsl-setup.sh` は **BOM なし・LF 改行**です。bash は先頭の BOM を `#!` の一部と誤認するためです。`install.bat` は **ASCII・CRLF** で、日本語を含めません。

git は既定でこれらを自動変換してしまうので、`.gitattributes` で `-text` を指定して変換を止めています。拡張子で判定しているため、ディレクトリを分けても設定はそのまま効きます。

</details>
