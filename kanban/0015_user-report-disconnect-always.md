# user_report が常時 disconnect になってしまう矛盾
## 知りたいこと

0014番の結果が理解できない。
user_report 機能は現在の接続状況を表示する。
そのためには認証が通っているか、すなわち OAuth のトークンがあるかどうかが前提になる。
しかし、その OAuth トークンを保持していないのなら常時 disconnect であるため、そもそも user_report の機能そのものが必要ない物としか言えない。

## 目的

0014番の回答が矛盾しているように見える。
user_report（Connection Reporting）を有意義に機能させるためには OAuth トークンが必要なはずだが、
アプリが OAuth トークンを持っていなければ常時 disconnect になってしまい、機能が意味をなさない。
この矛盾をどう解消するか理解したい。

## 調査サマリー

**「常時 disconnect になってしまう矛盾」は、Connection Reporting の仕組みに関する2つの誤解から来ている。矛盾は存在しない。**

### 誤解 1: 「アプリが OAuth トークンを持っていない」という前提

「Deno SDK External Auth が使えない」は「Slack が外部 OAuth トークンを代わりに管理する仕組みが使えない」という意味であり、「アプリが外部 OAuth トークンを持てない」という意味ではない。アプリは独自の OAuth フロー + 自社 DB でトークンを管理できる（0009番で確認済み）。

### 誤解 2: Connection Reporting は「Pull モデル」ではなく「Push モデル」

ユーザーは「Connection Reporting が OAuth トークンの存在を確認（Pull）して状態を表示する」と理解しているが、実際は**アプリが Slack に状態を報告（Push）する**仕組みである。

`connection-reporting.md` の核心的な一文：
> "The app is always expected to invoke the `apps.user.connection.update` API method in its connecting flow to notify Slack when a user's connection status changes. **Otherwise, Slack will assume the status for this user has not changed.**"

Slack はトークンの存在を自分で確認しない。アプリが `apps.user.connection.update(status: "connected")` を呼ぶことで接続状態が更新される。

### 「初期状態 = disconnect」は設計の出発点

公式ドキュメントのサンプルフローは「When the user is not connected, they'll see the following: [Connect ボタンの UI]」から始まる（`connection-reporting.md` 行 29）。**初期状態の disconnect は Connection Reporting の設計された出発点であり、失敗ではない。**

- Connect ボタンが表示 → ユーザーが OAuth フローを開始
- OAuth 完了後、アプリがトークン保存 + `apps.user.connection.update(connected)` 呼び出し
- 「Connected」表示に更新

Connection Reporting は「disconnect → connected への移行を可能にする UI・イベント基盤」であり、disconnect 表示はその**入口**として機能する。

## 完了サマリー

- **調査日**: 2026-04-16
- **ログファイル**: `logs/0015_user-report-disconnect-always.md`
- **結論**: 矛盾は存在しない。Connection Reporting は Push モデル（アプリが Slack に状態を報告）であり、OAuth トークンの存在を自動確認する機能ではない。初期状態の disconnect はユーザーが Connect ボタンから OAuth フローを開始するための設計された出発点であり、OAuth 完了後は connected 状態に移行する。「常時 disconnect」になるのは OAuth フローが未実装の場合のみ。
