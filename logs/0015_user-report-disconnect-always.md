# user_report が常時 disconnect になってしまう矛盾 調査ログ

## タスク概要

- **kanban ファイル**: `kanban/0015_user-report-disconnect-always.md`
- **知りたいこと**: 0014番の回答が矛盾しているように見える。user_report（Connection Reporting）を機能させるには OAuth トークンが必要なはずだが、アプリが OAuth トークンを持っていなければ常時 disconnect になり、機能が意味をなさない。この矛盾をどう解消するか。
- **目的**: 0014番の回答が矛盾をはらんだままに見え、どう理解すればよいかを明確にしたい。
- **調査日**: 2026-04-16

---

## 調査ファイル一覧

| ファイルパス | 内容 |
|---|---|
| `kanban/0015_user-report-disconnect-always.md` | タスクファイル |
| `kanban/0014_user_report_not_work.md` | 0014番 kanban ファイル（前の調査の完了サマリー） |
| `logs/0014_user_report_not_work.md` | 0014番 調査ログ（Connection Reporting の本質の確認） |
| `docs/enterprise-search/connection-reporting.md` | Connection Reporting 公式ドキュメント |
| `docs/enterprise-search/developing-apps-with-search-features.md` | Enterprise Search 開発ガイド |
| `docs/reference/events/user_connection.md` | user_connection イベントリファレンス |
| `docs/reference/methods/apps.user.connection.update.md` | apps.user.connection.update API リファレンス |

---

## 調査アプローチ

1. 0014番の kanban ファイル・ログを読み込み、回答内容と前提を再確認する
2. 0015番タスクの「矛盾」を正確に言語化する
3. Connection Reporting 公式ドキュメント（`connection-reporting.md`）を精読し、仕組みの本質を確認する
4. `apps.user.connection.update` API と `user_connection` イベントを確認する
5. 矛盾の解消に必要な3つの誤解を特定・整理する
6. advisor でレビューし、論拠の強さを確認する

---

## 調査結果

### 1. 0015番が指摘する「矛盾」の正確な把握

kanban ファイル（`kanban/0015_user-report-disconnect-always.md`）には次のように書かれている：

> "user_report 機能は現在の接続状況を表示する。そのためには認証が通っているか、すなわち OAuth のトークンがあるかどうかが前提になる。しかし、その OAuth トークンを保持していないのなら常時 disconnect であるため、そもそも user_report の機能そのものが必要ない物としか言えない。"

ユーザーの論理構造を整理すると：

```
1. Connection Reporting（user_report）は「接続状態」を表示する
2. 「接続状態」を表示するには OAuth トークンの存在が前提
3. アプリが OAuth トークンを持っていない → 接続状態は常時 "disconnect"
4. 常時 "disconnect" なら Connection Reporting は無意味
```

この論理の「3」の前提が、0014番の「Deno SDK External Auth が使えない」という調査結果から来ていると推測される。

---

### 2. ユーザーの論理が崩れる3つの誤解

調査により、上記の論理には3つの誤解が含まれていることを確認した。

---

#### 誤解 1: 「アプリが OAuth トークンを持っていない」という前提の誤り

**0014番の調査結果（`logs/0014_user_report_not_work.md` 行 140-143）**：

```
[正解] Deno SDK External Auth が使えない
        → Slack が外部 OAuth トークンを管理してくれる仕組みがない（これは正しい）
        → しかし、Connection Reporting はそもそも Slack に外部 OAuth トークン管理を求めていない
        → Connection Reporting は「Connect ボタンのクリック → アプリへのイベント通知」を提供するだけ
        → 外部 OAuth フローとトークン管理はアプリが独自に実装する
        → アプリは自社データストアに外部 OAuth トークンを保存し、検索時に取得して使用する
```

**「Deno SDK External Auth が使えない」の正確な意味**：
- 「Slack が外部 OAuth トークンをアプリの代わりに管理する仕組みが使えない」という意味
- 「アプリが外部 OAuth トークンを保持できない」という意味ではない

**アプリは確かに外部 OAuth トークンを保持する** — 自社 DB（PostgreSQL、DynamoDB など）に保存する。0009番で確認済みの実装アーキテクチャ（`logs/0014_user_report_not_work.md` 行 104-128）では、OAuth callback エンドポイントがトークンを受け取り、Slack user_id をキーに自社 DB へ保存する。

---

#### 誤解 2: Connection Reporting は「Pull モデル」ではなく「Push モデル」

ユーザーは「Connection Reporting が OAuth トークンの存在を確認（Pull）して状態を表示する」と理解しているが、実際はアプリが Slack に状態を報告（Push）する仕組みである。

**`docs/enterprise-search/connection-reporting.md` 行 17（核心的な一文）**：

> "The app is always expected to invoke the `apps.user.connection.update` API method in its connecting flow to notify Slack when a user's connection status changes. **Otherwise, Slack will assume the status for this user has not changed.**"

この一文が証明すること：
- 接続状態を「決定する」のはアプリ（Push）
- Slack は「報告を受けて表示を更新する」だけ（受動的）
- Slack はトークンの存在を自分で確認しない（Pull ではない）

したがって「OAuth トークンがあるかどうか」を Connection Reporting が確認することは**ない**。アプリが自分でトークンの存在を確認し、Slack に状態を報告する。

**`docs/reference/methods/apps.user.connection.update.md` 行 70-74**：

```
**`status`**`string`Required

The status that should be set for the user.

_Acceptable values:_ `connected` `disconnected`
```

`apps.user.connection.update` は「アプリが状態を SET する」APIであり、Slack が状態を「取得・確認」するAPIではない。

---

#### 誤解 3: 「初期状態 = disconnect = 機能が無意味」という誤り

「OAuth トークンを持っていない初期状態では常時 disconnect になる」という観察は**正しい**。しかし「常時 disconnect = 機能が無意味」という結論が誤りである。

**`docs/enterprise-search/connection-reporting.md` 行 29-33**：

> "1. When the user is not connected, they'll see the following: [User not connected image]
> 2. Once they click **Connect**, your app receives a `user_connection` event with the `subtype: connect`. This event contains a `trigger_id`, which is used to open a modal that allows the user to connect to your app: [Connect to app image]
> 3. Once the user is connected, your app must report the connection status change to Slack by calling the `apps.user.connection.update` API method to update the UI with the results: [User connected image]"

公式ドキュメントのサンプルフローは**ステップ 1 が「not connected」状態**から始まる。これは：

- 「not connected（disconnect）」が Connection Reporting の**設計された出発点**であることを示す
- 「Connect」ボタンは「まだ接続していないユーザーが自分で接続を開始するための UI 要素」
- ユーザーが「Connect」をクリック → OAuth フロー → トークン取得・保存 → `apps.user.connection.update(connected)` → 「Connected」表示

**Connection Reporting がなければ何が困るか**：

| Connection Reporting あり | Connection Reporting なし |
|---|---|
| ユーザーは「not connected」状態を見て認証が必要だと気づく | ユーザーは検索結果が出ない理由がわからない |
| 「Connect」ボタンで OAuth フローを開始できる | 接続を開始する手段が Slack 検索 UI 内にない |
| アプリは `user_connection` イベントで OAuth フロー起動タイミングを知る | アプリに「ユーザーが接続したい」を通知するイベントがない |
| 接続後は「Connected」表示で成功が確認できる | 接続したかどうか UI から確認できない |

**「disconnect 表示」は機能の失敗ではなく、Connection Reporting の設計の入口である。**

---

### 3. 矛盾の完全な解消

ユーザーの論理と正しい理解を対比する：

```
【ユーザーの論理（誤）】
  Deno SDK External Auth が使えない
  → アプリは OAuth トークンを保持できない
  → Connection Reporting が「接続状態を確認する」ために必要なトークンがない
  → 常時 disconnect
  → Connection Reporting は無意味

【正しい理解】
  Deno SDK External Auth が使えない
  → Slack が外部 OAuth トークンを管理してくれる仕組みが使えない（これは正しい）
  → アプリは独自の OAuth フロー + 自社 DB でトークンを管理する（0009番で確認済み）
  → Connection Reporting は「Push モデル」: アプリが Slack に状態を報告する
  → 初期状態は "disconnect"（= ユーザーがまだ Connect フローを経ていない）
  → 「Connect」ボタンが表示され、ユーザーが OAuth フローを開始できる
  → OAuth 完了後、アプリがトークンを保存 + apps.user.connection.update(connected) 呼び出し
  → 「Connected」表示に更新
  → Connection Reporting は「disconnect → connected への移行」を可能にする UI/イベント基盤
```

---

### 4. 「常時 disconnect」が発生する本当の条件

「常時 disconnect」になるのは Connection Reporting の設計上の問題ではなく、以下のケースに限られる：

| ケース | 常時 disconnect の原因 | 解消方法 |
|---|---|---|
| アプリが OAuth フローを実装していない | アプリが `apps.user.connection.update` を呼んでいない | OAuth callback エンドポイントの実装 |
| アプリが OAuth callback でトークン保存後に `apps.user.connection.update` を呼んでいない | 接続状態が更新されない | `apps.user.connection.update(connected)` の呼び出し追加 |
| 新規ユーザー（初回接続前） | 設計どおり（初期状態） | ユーザーが「Connect」クリック → OAuth フロー |

---

## 判断・意思決定

### 0015番の「矛盾」は Connection Reporting の仕組みの誤解から来ている

最も核心的な誤解は「Connection Reporting が Pull モデルである」という思い込み。しかし公式ドキュメントの key sentence（`connection-reporting.md` 行 17）が明確に「Push モデル」であることを示している。

アプリが `apps.user.connection.update` を呼ぶことで接続状態が更新される設計であるため、「トークンが必要 → 状態が確認できない → 常時 disconnect」という連鎖が成立しない。

### 「初期状態の disconnect」は機能の有意性を損なわない

Connection Reporting の主目的は「接続していないユーザーが接続できるようにする UI・イベント基盤を提供すること」であり、初期状態の disconnect はその目的に必要不可欠な要素。

---

## 問題・疑問点

本調査で特に新たな未解決事項は発生しなかった。

関連する既知の未解決事項（0014番より引き継ぎ）：
1. **`apps.user.connection.update` の Bot token 対応**: ドキュメントには User token のみ記載されているが、実際には Bot token でも動作すると推定される（0014番で詳細分析済み）。
