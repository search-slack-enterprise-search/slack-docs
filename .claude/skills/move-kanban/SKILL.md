---
name: move-kanban
description: temp-kanban/ にある保留中のタスクファイルを kanban/ に移行して調査を開始します。Use when the user wants to move a file from temp-kanban to kanban, process a pending kanban task, or says /move-kanban. Also trigger when the user says "temp-kanban の〇〇を移行したい", "temp-kanban のものを kanban に追加したい", or similar.
argument-hint: [filename-or-keyword]
---

temp-kanban/ にある保留中のタスクファイルを kanban/ に移行し、/kanban で調査を開始します。

## 引数

$ARGUMENTS

引数としてファイル名またはキーワードを指定できます（例: `/move-kanban search-api` や `/move-kanban` で一覧表示）。

## 手順

### 0. git pull の実行

Bash ツールで `git pull origin master` を実行する。

- **成功した場合**: ステップ 1 へ進む
- **失敗した場合**: ユーザーに「git pull が失敗したため移行を中止します」と伝えて終了する

### 1. temp-kanban/ のファイル確認

`temp-kanban/*.md` を Glob で取得し、存在するファイルを確認する。

- ファイルがない場合: ユーザーに「temp-kanban/ にファイルが見つかりません」と伝えて終了する
- ファイルがある場合: ステップ 2 へ進む

### 2. 対象ファイルの特定

`$ARGUMENTS` の内容に応じて対象ファイルを決定する。

- **引数あり**: ファイル名またはキーワードが一致するファイルを選択する（部分一致でよい）
  - 一致するファイルが複数ある場合: 候補一覧をユーザーに提示して選択を求める
  - 一致するファイルがない場合: 全ファイル一覧を提示して選択を求める
- **引数なし**: temp-kanban/ の全ファイル一覧をユーザーに提示して選択を求める

### 3. ファイルの読み込み

Read ツールで対象ファイルの内容を読み込む。

### 4. 連番の計算

`kanban/[0-9][0-9][0-9][0-9]_*.md` のファイル一覧を Glob で取得し、ファイル名先頭の数字部分から最大値を求め、+1 した値を4桁ゼロパディングする。

- ファイルがひとつもない場合は `0000` から開始
- 例: `0039_enterprise-search-on-aws-lambda.md` が最大なら次は `0040`

### 5. kanban/ へのファイル作成

Write ツールで `kanban/{padded}_{元のファイル名}.md` を作成する。

- ファイルの内容は temp-kanban/ から読み込んだ内容をそのまま使用する
- 例: temp-kanban/ の `search-api-rate-limit.md` → `kanban/0040_search-api-rate-limit.md`

### 6. temp-kanban/ から削除

Bash ツールで `rm temp-kanban/{元のファイル名}.md` を実行して temp-kanban/ から削除する。

削除が完了したら、移行先のファイルパスをユーザーに伝える。

### 7. kanban タスクの実行

Skill ツールで `skill: "kanban"`, `args: "{xxxx}"` を呼び出して調査をただちに開始する。
