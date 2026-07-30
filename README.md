# AI 開発環境 セットアップスクリプト（Windows / Mac）

新品の Windows または Mac に、AI でコードを書くための道具を**まとめて自動インストール**するスクリプトです。

ひとつずつ手作業で入れると 30 分以上かかる作業が、コマンド 2 行で終わります。

---

## 何がインストールされるの？

| 入るもの | これは何？ |
|---|---|
| **WSL2 (Ubuntu)** | Windows の中で Linux を動かす仕組み。開発作業が快適になります |
| **Git for Windows** | プログラムの変更履歴を管理する道具。ほぼ全ての開発で必要です |
| **Claude Code** | ターミナルで動く AI コーディング支援ツール（Anthropic製） |
| **Codex CLI** | ターミナルで動く AI コーディング支援ツール（OpenAI製） |
| **Claude Desktop** | Claude のデスクトップアプリ（画面から使うタイプ） |

あわせて `%USERPROFILE%\.local\bin` を **PATH** に追加します。PATH とは「コマンドを名前だけで呼び出せるようにする設定」です。これがないと `claude` と打っても「そんなコマンドは無い」と言われてしまいます。

---

## 始める前に確認すること

### 1. 管理者権限があること

WSL2 のインストールには管理者権限が必要です。会社から借りている PC などで権限が無い場合、スクリプトは途中で止まります。

### 2. 「アプリ インストーラー」が入っていること

Git と Claude Desktop のインストールに `winget` というコマンドを使います。これは Microsoft Store の「**アプリ インストーラー**」に含まれています。

通常 Windows 10/11 には最初から入っていますが、古いままだと動かないことがあります。うまくいかない場合は Microsoft Store で「アプリ インストーラー」を検索して更新してください。

### 3. AI サービスのアカウントが必要

スクリプトは**ツールを入れるところまで**を自動化します。実際に AI を使うには、あなた自身のアカウントでログインが必要です。

- Claude Code / Claude Desktop → **Claude Pro** または **Max** プラン
- Codex CLI → **ChatGPT Plus** など

無料プランでは使えない場合があります。

---

## 使い方（かんたん版・おすすめ）

**`install.bat` をダウンロードしてダブルクリックするだけ**です。コマンドを打つ必要はありません。

1. [install.bat をダウンロード](https://raw.githubusercontent.com/kouki485/setup_windwos/main/install.bat)（リンクを右クリック →「名前を付けてリンク先を保存」）
2. ダウンロードした `install.bat` を**ダブルクリック**
3. 「このアプリがデバイスに変更を加えることを許可しますか？」→「**はい**」

あとは自動で進みます。`install.bat` が次のことを代わりにやってくれます。

- 管理者権限への昇格（UAC の確認画面が出ます）
- セットアップ本体のダウンロードと、壊れていないかの検証
- スクリプトの実行（実行ポリシーの一時解除も自動）

終わると**デスクトップに `ai-setup-log.txt`** が作られます。うまくいかなかったときは、このファイルを担当者に送ってください。

> **Windows Defender や SmartScreen の警告が出た場合**: 「詳細情報」→「実行」を選んでください。インターネットから入手したバッチファイルには必ずこの警告が出ます。

---

## 使い方（Windows 側・コマンドで実行する場合）

`install.bat` を使わず自分でコマンドを打ちたい場合はこちらです。

### 手順 1. PowerShell を管理者として開く

1. スタートボタンを**右クリック**
2. 「**ターミナル (管理者)**」または「**Windows PowerShell (管理者)**」を選ぶ
3. 「このアプリがデバイスに変更を加えることを許可しますか？」→「**はい**」

> 通常の PowerShell では WSL2 を入れられません。必ず管理者として開いてください。

### 手順 2. 次の 2 行を貼り付けて実行

```powershell
curl.exe -fsSL -o "$env:TEMP\setup.ps1" https://raw.githubusercontent.com/kouki485/setup_windwos/main/setup.ps1
powershell -ExecutionPolicy Bypass -File "$env:TEMP\setup.ps1"
```

1 行目でスクリプトをダウンロードし、2 行目で実行します。

<details>
<summary>この 2 行の意味（クリックで開く）</summary>

- `curl.exe` … ファイルをダウンロードするコマンド
- `-o "$env:TEMP\setup.ps1"` … 一時フォルダに `setup.ps1` という名前で保存する
- `-ExecutionPolicy Bypass` … Windows は既定でスクリプトの実行をブロックするため、この 1 回だけ許可する設定。PC 全体の設定は変わりません
- `-File` … 保存したファイルを実行する

**`irm ... | iex` のような 1 行版は使わないでください。** このスクリプトは途中で `exit` を使うため、その書き方だと PowerShell の画面ごと閉じてしまいます。

</details>

### 手順 3. WSL2 が入っていない場合は 2 回実行する

まだ WSL2 が入っていない PC では、**1 回目で WSL2 を入れて再起動を求めて終了**します。慌てず次の流れで進めてください。

```
1回目を実行
  → WSL2 がインストールされる
  → 「今すぐ再起動しますか? (y/N)」と聞かれる → y を入力（または後で手動で再起動）

再起動したあと
  → スタートメニューから「Ubuntu」を開く
  → ユーザー名とパスワードを決めて入力（★これは必須。飛ばせません）
     ※パスワードは入力しても画面に何も表示されませんが、ちゃんと入力されています

もう一度、手順 2 の同じ 2 行を実行
  → 残り（Git / Claude Code / Codex CLI / Claude Desktop）が入る
```

WSL2 が既に入っている PC なら 1 回で終わります。

### 手順 4. 新しいターミナルを開いてログイン

インストール直後の画面では、まだ `claude` などのコマンドが認識されません。**必ず新しいターミナルを開き直してください**（PATH の設定を反映するため）。

そのうえで、順番にログインします。

```powershell
claude      # ブラウザが開くので Claude アカウントでログイン
codex       # ブラウザが開くので ChatGPT アカウントでログイン
```

Claude Desktop はスタートメニューから起動してサインインします。

---

## 使い方（WSL / Ubuntu 側）

WSL の中でも AI ツールを使いたい場合に実行します。Windows 側とは別に、Ubuntu の中にもインストールする作業です。

**Ubuntu のターミナル**を開いて、次の 2 行を実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/kouki485/setup_windwos/main/wsl-setup.sh -o wsl-setup.sh
bash wsl-setup.sh
```

入るものは次の 3 つです。

1. 基本パッケージ（`git` / `curl` / `unzip` / `build-essential`）
2. Claude Code（Linux 版）
3. Codex CLI（Linux 版）

終わったら設定を読み込み直してログインします。

```bash
source ~/.bashrc
claude
codex
```

> **ヒント**: WSL で作業するときは、ファイルを `/mnt/c/...`（Windows 側のフォルダ）ではなく `~/`（Ubuntu の中）に置いてください。読み書きの速度がはっきり変わります。

---

## このスクリプトの親切な仕様

### 何度実行しても安全です

すでに入っているものは `[SKIP]` と表示して飛ばします。途中で失敗したら、そのままもう一度実行してください。成功済みの部分はやり直しません。

### 通信エラーには自動で 3 回まで再挑戦します

ダウンロードが一時的に失敗しても、5 秒待って自動でやり直します。

### 一部が失敗しても最後まで進みます

途中で 1 つ失敗しても止まりません。最後に結果の一覧を表示します。

```
==> インストール結果
  [OK] git : git version 2.51.0.windows.1
  [OK] claude : 2.1.220
  [NG] codex が見つかりません（ターミナル再起動後に再確認してください）
```

`[NG]` が出た項目だけ、あとから対処すれば大丈夫です。

---

## うまくいかないときは

### 「式またはステートメントのトークン '}' を使用できません」のようなエラーが大量に出る

**文字化けが原因**です。ダウンロードの方法を間違えている可能性があります。

`irm`（Invoke-RestMethod）ではなく、必ず **`curl.exe`** を使ってください。`irm` はファイルの先頭にある「BOM」という目印を落としてしまうことがあり、そうなると Windows PowerShell が日本語部分を読み間違えてスクリプト全体が壊れます。

ダウンロードしたファイルが正しいかは、次のコマンドで確認できます（`True` と出れば正常）。

```powershell
[System.IO.File]::ReadAllBytes("$env:TEMP\setup.ps1")[0..2] -join ',' -eq '239,187,191'
```

`False` の場合は、いったんファイルを削除してから `curl.exe` でもう一度ダウンロードしてください。

### 「WSL2のインストールには管理者権限が必要です」と出て止まる

PowerShell を管理者として開いていません。手順 1 をやり直してください。

### 「winget が見つかりません」と出て止まる

Microsoft Store で「**アプリ インストーラー**」を検索して、インストールまたは更新してください。

### インストールしたのに `claude` コマンドが見つからない

ターミナルを開き直してください。PATH の変更は、新しく開いたターミナルにしか反映されません。

### スクリプトの実行がブロックされる

会社や学校の PC では、管理者がグループポリシーでスクリプト実行を禁止している場合があります。この場合 `-ExecutionPolicy Bypass` を付けても実行できません。IT 部門に相談してください。

---

## 使い方（Mac の場合）

Mac では **`mac-setup.sh`** を使います。`install.bat` や `setup.ps1` は Windows 専用なので使えません。

ターミナル（アプリケーション → ユーティリティ → ターミナル）を開いて、次の 2 行を実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/kouki485/setup_windwos/main/mac-setup.sh -o mac-setup.sh
bash mac-setup.sh
```

入るものは次の 6 つです。

| 入るもの | 説明 |
|---|---|
| **Xcode Command Line Tools** | Homebrew を動かすための前提。Apple 純正の開発ツール |
| **Homebrew** | Mac 用のソフト管理ツール。以降のインストールに使います |
| **Git** | 変更履歴の管理ツール（Command Line Tools に含まれるため通常はスキップされます） |
| **Claude Code** | ターミナルで動く AI コーディング支援ツール |
| **Codex CLI** | 同上（OpenAI 製） |
| **Claude Desktop** | Claude のデスクトップアプリ |

### Mac 特有の注意点

**パスワードを 1 回聞かれます**

Homebrew の導入時だけ、Mac のログインパスワードを求められます。入力しても**画面には何も表示されません**が、ちゃんと入力されています。そのまま Enter を押してください。

Homebrew が既に入っている場合、パスワードは聞かれません。

**Xcode Command Line Tools のダイアログが出ます**

初回のみ「ソフトウェアをインストールしますか？」というダイアログが表示されます。「**インストール**」を選んでください。数分かかります。スクリプトは完了を自動で待ちます。

**Apple Silicon と Intel でインストール先が変わります**

スクリプトが自動で判定します。

- Apple Silicon（M1〜M4）: `/opt/homebrew`
- Intel: `/usr/local`

Apple Silicon の Mac では Homebrew のコマンドが初期状態で認識されないため、`~/.zprofile` に設定を自動で追記します。

**終わったら新しいターミナルを開いてください**

設定の反映のためです。今の画面でそのまま試したい場合は次を実行します。

```bash
source ~/.zprofile
```

### ログイン

```bash
claude      # ブラウザが開くので Claude アカウントでログイン
codex       # ブラウザが開くので ChatGPT アカウントでログイン
```

Claude Desktop は Launchpad から起動してサインインします。

実行ログは**デスクトップの `ai-setup-log.txt`** に残ります。

---

## インストール後: 自分の業務を AI に手伝わせる

ツールを入れただけでは仕事は楽になりません。**Claude にあなたの業務を理解させる**ところから始めてください。そのためのプロンプトを `prompts/` に用意しています。

### 使う順番

| ステップ | プロンプト | やること | 所要時間 |
|---|---|---|---|
| 1 | [`prompts/business-discovery.md`](prompts/business-discovery.md) | Claude があなたの業務を**ヒアリングして深掘り**し、`業務プロファイル.md` と `業務プロファイル.html` を作る | 30〜40分 |
| 2 | [`prompts/ax-proposal.md`](prompts/ax-proposal.md) | その内容を元に、**AI で楽にできる部分**を洗い出して優先順位を付ける | 20〜30分 |

ステップ 1 では Claude が質問してくるので、答えていくだけです。**AI に何ができるか知らなくても構いません。** 普段の仕事をそのまま話してください。

成果物は **HTML と Markdown の 2 形式**で作られます。`業務プロファイル.html` はダブルクリックでブラウザで開けるので、上司や同僚への共有、印刷、PDF 化に使えます。外部のファイルを参照しない単一ファイルなので、オフラインでもメール添付でも崩れません。`業務プロファイル.md` は次の工程で Claude が読むためのものです。

### 使い方（かんたん）

1. ターミナルで `claude` を起動
2. プロンプトファイルの中身をコピーして貼り付ける
3. Claude が質問を始めるので、答えていく

```powershell
# プロンプトをダウンロードしておくと楽です
curl.exe -fsSL -o "%USERPROFILE%\Desktop\業務ヒアリング.md" https://raw.githubusercontent.com/kouki485/setup_windwos/main/prompts/business-discovery.md
```

### 使い方（スラッシュコマンドとして登録）

`~/.claude/commands/` に置くと、`/business-discovery` と打つだけで呼び出せます。

```powershell
mkdir "$env:USERPROFILE\.claude\commands" -Force
curl.exe -fsSL -o "$env:USERPROFILE\.claude\commands\business-discovery.md" https://raw.githubusercontent.com/kouki485/setup_windwos/main/prompts/business-discovery.md
curl.exe -fsSL -o "$env:USERPROFILE\.claude\commands\ax-proposal.md" https://raw.githubusercontent.com/kouki485/setup_windwos/main/prompts/ax-proposal.md
```

登録後、`claude` を起動して `/business-discovery` と入力すれば始まります。

### なぜ 2 段階に分けているのか

業務を聞きながら同時に AI 活用を提案させると、**提案の質が落ちます**。「AI にできそうなこと」に話が寄ってしまい、本当に時間を食っている作業が埋もれるためです。

そのためステップ 1 のプロンプトは、AI の話を意図的に禁止しています。まず業務を正確に理解し、それから提案する順序にしてください。

### 期待してよいこと・できないこと

| できること | できないこと |
|---|---|
| 文章の下書き、要約、分類、書き換え | 社内の最新情報や固有の事実を知ること（渡す必要あり） |
| 判断基準が言語化できる作業の支援 | 数値の計算・集計の精度保証（必ず検証が必要） |
| 過去の書き方に合わせた文章生成 | 責任を伴う最終判断 |
| 暗黙知の言語化・マニュアル化 | 社外に出せない情報の処理（扱い方の設計が必要） |

ステップ 2 のプロンプトは、**AI に任せるべきでない業務を「対象外」として明示する**よう指示しています。できないことを正直に出す方が、長く使える提案になります。

---

## 管理者・IT 担当者向け（複数台へ配布する場合）

社内の複数の PC に同じ環境を作る場合の推奨手順です。

### 配布方法

**`install.bat` だけを配れば十分です。** 社内の共有フォルダ、Slack、Teams、メール添付など、普段使っている経路で構いません。セットアップ本体（`setup.ps1`）は実行時に GitHub から取得されるので、配布物は 1 ファイルで済みます。

利用者への案内は「**ダウンロードしてダブルクリック、UAC が出たら「はい」**」の一文で足ります。

### 配布前に確認しておくこと

| 確認項目 | 理由 |
|---|---|
| 各 PC に**管理者権限**があるか | WSL2 の導入に必須。無い場合は事前に付与するか、IT 側で WSL を先に入れておく |
| **winget** が使えるか | Git と Claude Desktop の導入に使用。無い場合はその 2 つがスキップされ、AI ツールのみ導入される |
| **Windows 10 1803 以降**か | `curl.exe` が標準搭載されているバージョン。それ以前だと `install.bat` が停止する |
| プロキシや**セキュリティ製品**が通信を書き換えないか | ファイルが改変されると `install.bat` が「BOM が無い」と検知して安全に停止します |
| 各利用者の**AI サービス契約**があるか | Claude Pro/Max、ChatGPT Plus など。ツールは入っても未契約ではログインできません |

### 全台で結果を揃えるために

- **何度実行しても安全**です。導入済みの項目はスキップされるため、失敗した端末で再実行するだけで復旧します
- **WSL2 が未導入の端末では 2 回実行が必要**です（1 回目で WSL2 を入れて再起動 → Ubuntu の初期設定 → 2 回目で残りを導入）。すでに WSL2 が入っている端末は 1 回で完了します
- 各端末の**デスクトップに `ai-setup-log.txt`** が残ります。トラブル時はこれを回収すれば原因が特定できます
- 特定のバージョンに固定して配りたい場合は、`install.bat` の中の `REPO_URL` を `main` からコミットハッシュに書き換えてください。全台でまったく同じ内容が入ることを保証できます

```bat
rem 例: 特定バージョンに固定する
set "REPO_URL=https://raw.githubusercontent.com/kouki485/setup_windwos/4f3cc03/setup.ps1"
```

### GitHub にアクセスできない環境の場合

`setup.ps1` と `wsl-setup.sh` を共有フォルダに置き、`install.bat` の `REPO_URL` を社内 URL に差し替えるか、ダウンロード部分を共有フォルダからのコピーに変更してください。その際 `setup.ps1` は **UTF-8 BOM 付き**のまま扱う必要があります（BOM が失われると文字化けして動きません）。

---

## ファイル構成

| ファイル | 役割 |
|---|---|
| `install.bat` | **配布用の起動ファイル。** 管理者昇格・ダウンロード・検証・実行を自動化 |
| `setup.ps1` | Windows 側のセットアップ本体（PowerShell スクリプト） |
| `wsl-setup.sh` | WSL / Ubuntu 側のセットアップ（シェルスクリプト） |
| `mac-setup.sh` | **macOS 用のセットアップ。** Homebrew の導入から一括で行う |
| `prompts/business-discovery.md` | **業務ヒアリング用プロンプト。** Claude が業務を深掘りして業務プロファイルを作る |
| `prompts/ax-proposal.md` | **AX 提案用プロンプト。** 業務プロファイルから AI 活用案を優先順位付きで出す |
| `.gitattributes` | 文字コードと改行の設定を保護するための設定ファイル |

<details>
<summary>.gitattributes は何をしているの？（技術的な補足）</summary>

`setup.ps1` は **UTF-8 BOM 付き・CRLF 改行**で保存されています。Windows PowerShell 5.1 は BOM が無い UTF-8 ファイルを日本語環境の文字コード（CP932）として読んでしまい、日本語のコメントや文字列が壊れてしまうためです。

一方 `wsl-setup.sh` は **BOM なし・LF 改行**です。bash は先頭の BOM を `#!` の一部と誤認してしまうためです。

git は既定でこれらを自動変換してしまうので、`.gitattributes` で `-text` を指定して変換を止めています。この設定があるおかげで、ダウンロードしたファイルがそのまま正しく動きます。

</details>
