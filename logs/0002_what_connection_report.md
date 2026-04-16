# 0002_what_connection_report 作業ログ

## 基本情報

- **タスクファイル**: kanban/0002_what_connection_report.md
- **開始日時**: 2026-04-16T13:50:47+09:00
- **完了日時**: 2026-04-16T13:52:25+09:00

## タスク概要

Enterprise Search の Connection Report とは何か知りたい。
何を目的とした機能なのかがよくわからない。エンドポイントとの接続状況を見るだけなら、ユーザーの Permission を求める理由がわからない。

## 調査結果

### 1. `docs/enterprise-search/connection-reporting.md` — Connection Report の中核ドキュメント

#### 概要定義

> Slack's connection reporting feature allows your app to communicate a user's authentication status, or connection status, directly to Slack. By offloading the UI management for "connect/disconnect" states to Slack, you can ensure a consistent user experience while reducing development overhead.

Connection Report は「エンドポイントの死活監視」ではなく、**ユーザーの認証ステータス（authentication status）= 接続状態（connection status）をアプリが Slack に報告する機能**。Slack が「接続/切断」の UI 管理を引き受けることで、一貫した UX の提供と開発オーバーヘッドの削減を実現する。

#### イベント処理と状態更新

- アプリは `user_connection` イベントをリッスンする
- このイベントには `subtype` フィールドがあり、ユーザーが接続（connect）しようとしているか、切断（disconnect）しようとしているかを示す
- アプリは接続フロー内で必ず `apps.user.connection.update` API を呼び出し、ユーザーの接続ステータス変更を Slack に通知する必要がある
- この API を呼び出さない場合、Slack はユーザーのステータスが変更されていないと仮定する

#### 具体的なシーケンス（ドキュメント記載の例）

1. ユーザーが未接続の場合、Slack UI に「Connect」ボタンが表示される（スクリーンショット: `user-not-connected` 画像）
2. ユーザーが「Connect」をクリックすると、アプリが `user_connection` イベント（subtype: connect）を受信する。このイベントには `trigger_id` が含まれ、モーダルを開いてユーザーにアプリへの接続手順を案内できる（スクリーンショット: `connect-to-app` 画像）
3. ユーザーが接続完了後、アプリは `apps.user.connection.update` API を呼び出して接続ステータスの変更を Slack に報告し、UI が更新される（スクリーンショット: `user-connected` 画像）

#### ドキュメントの構成

- Event handling and status updating セクション
- Sequence of events セクション（シーケンス図画像あり）
- Example セクション（上記の 4 ステップの具体例）
- Developer Sandbox での試用案内あり

---

### 2. `docs/reference/events/user_connection.md` — user_connection イベントリファレンス

#### 基本情報

- **Required Scopes**: `users:write`
- **Compatible APIs**: Events API, RTM API（レガシー）
- **説明**: "A member's user connection status change requested"

#### subtype: connect

ユーザーがアプリとの接続をリクエストしていることを通知する。`trigger_id` が含まれており、アプリはこれを使ってモーダルを開き、接続フローのステップ・リンク・ボタンを表示できる。

ペイロード例:
```json
{
    "token": "P1GEyKehpM8yI998PLwq0P66",
    "team_id": "E012A3BC4DE",
    "api_app_id": "A012ABC34DE",
    "event": {
        "type": "user_connection",
        "subtype": "connect",
        "user": "U012A3BC4DE",
        "trigger_id": "1293638028594.1249184885746.0d121a0e01d2e7a795ecc7a62880a406",
        "event_ts": "1764264284.841251"
    },
    "type": "event_callback",
    "event_id": "Ev012A3BCDEF",
    "event_time": 1764264284
}
```

- `trigger_id` はモーダルを開くために使用される（接続フロー用）
- `user` フィールドで対象ユーザーを識別

#### subtype: disconnect

ユーザーがアプリからの切断をリクエストしていることを通知する。ユーザーを識別するための情報が含まれる。

ペイロード例:
```json
{
    "token": "P1GEyKehpM8yI998PLwq0P66",
    "team_id": "E012A3BC4DE",
    "api_app_id": "A012ABC34DE",
    "event": {
        "type": "user_connection",
        "subtype": "disconnect",
        "enterprise_id": "E012A3BC4DE",
        "user": "U012A3BC4DE",
        "event_ts": "1764264317.061589"
    },
    "type": "event_callback",
    "event_id": "Ev012A3BCDEF",
    "event_time": 1764264317
}
```

- disconnect には `trigger_id` がない（モーダル不要、即座に切断処理を行う）
- `enterprise_id` フィールドが含まれている

---

### 3. `docs/reference/methods/apps.user.connection.update.md` — API メソッドリファレンス

#### 基本情報

- **説明**: Updates the connection status between a user and an app.
- **メソッド**: `POST https://slack.com/api/apps.user.connection.update`
- **スコープ**: User token: `users:write`
- **Content types**: `application/x-www-form-urlencoded`, `application/json`
- **Rate Limits**: Tier 2: 20+ per minute

#### 必須引数

| パラメータ | 型 | 説明 | 例 |
|-----------|------|------|-----|
| `token` | string | 認証トークン | `xxxx-xxxxxxxxx-xxxx` |
| `user_id` | string | ステータス更新対象のユーザーID | `U12345678` |
| `status` | string | 設定すべきステータス。`connected` または `disconnected` | `connected` |

#### Bolt フレームワークでのアクセス方法

- **Bolt for JS**: `app.client.apps.user.connection.update`
- **Bolt for Python**: `app.client.apps_user_connection_update`
- **Bolt for Java**: `app.client().appsUserConnectionUpdate`

#### エラー一覧（主要なもの）

- `access_denied`: リソースへのアクセスが拒否
- `missing_scope`: 必要なスコープ権限がない
- `no_permission`: ワークスペーストークンに必要な権限がない
- `user_not_found`: 無効なユーザーID
- `invalid_auth`: トークンが無効
- `app_not_found`: アプリが見つからない
- `app_not_subscribed`: アプリが必要なイベントをサブスクライブしていない

成功レスポンス: `{ "ok": true }`

---

### 4. `docs/enterprise-search/developing-apps-with-search-features.md` — Enterprise Search 開発ガイド

Connection Report に関する記述はセクション末尾にあり:

> ## Connection reporting {#connection-reporting}
> Refer to the [connection reporting guide](/enterprise-search/connection-reporting) to learn more about building your own connection-enabled app using Enterprise Search.

Enterprise Search の開発ガイド全体の中で、Connection Reporting は独立したオプション機能として位置付けられている。Enterprise Search のコア機能（`function_executed` イベントで検索を受け取り → `functions.completeSuccess` で結果返却）とは別に、追加の機能として提供される。

また、このドキュメントでは検索関数の入力パラメータとして `slack#/types/user_context` 型のパラメータが任意で利用可能とされており、これは「検索を実行しているユーザーのコンテキスト」を渡すもの。Connection Report と組み合わせることで、ユーザーが外部システムに接続済みかどうかに応じた検索結果の制御が可能になる。

---

### 5. `docs/enterprise-search/enterprise-search-access-control.md` — エンドユーザーアクセス制御

- Enterprise Search アプリは org レベルでインストール・設定されても、デフォルトではエンドユーザーに利用可能にならない
- org admin がエンドユーザー向けに有効化する必要がある
- 有効化後、エンドユーザーはアプリがアクセス許可されたワークスペースのメンバーであれば検索結果を受け取れる
- エンドユーザーは個別にアプリを無効化できる（「Manage」から無効化、またはサイドバーで右クリック→「Disable」）

このドキュメントは Connection Report について直接言及していないが、エンドユーザーの「有効化/無効化」と Connection Report の「接続/切断」は異なる概念:
- **有効化/無効化**: アプリ自体を検索結果に含めるかどうか（admin レベル + ユーザーレベル）
- **接続/切断（Connection Report）**: ユーザーが外部データソースに認証済みかどうか

---

### 6. `docs/enterprise-search/index.md` — Enterprise Search 概要

> The Enterprise Search for apps feature enables real-time search for users across multiple external sources. Developers can use this feature to integrate their organization's internal data sources into Slack (for example, wikis and proprietary systems).

Connection Report は Enterprise Search の 4 つの主要トピック（開発ガイド・Connection Reporting・アクセス制御・Work Objects）の 1 つとして挙げられている:

> ➡️ Refer to [connection reporting](/enterprise-search/connection-reporting) to learn more about building your own connection-enabled app using Enterprise Search.

---

### 7. `kanban/0000_search_permission.md` — 前回タスクの調査結果（参考）

前回の Permission 調査で、Connection Reporting に関する Scope が整理済み:

- `users:write` は **任意**（Connection Reporting 使用時のみ必要）
- Enterprise Search のコア機能（`function_executed` → `functions.completeSuccess`）は OAuth Scope が一切不要
- Connection Reporting はオプション機能であり、使用する場合にのみ `users:write` スコープが必要

---

### 核心的な回答: なぜ Permission が必要なのか

ユーザーの疑問「エンドポイントとの接続状況を見るだけなら、ユーザーの Permission を求める理由がわからない」に対する回答:

**Connection Report は「エンドポイント（サーバー）との接続状況を見る」機能ではない。**

Connection Report の本質は以下の通り:

1. **ユーザーごとの認証管理**: 各ユーザーが外部データソース（Wiki、社内システムなど）に個別にログイン（認証）する仕組み
2. **接続状態の書き込み**: アプリが `apps.user.connection.update` API を使って、特定ユーザーの接続状態を `connected` / `disconnected` に変更する。これは**ユーザー情報の書き換え操作**
3. **Slack UI の委譲**: Slack が「Connect / Disconnect」ボタンを提供し、ユーザーが外部システムへの接続・切断を Slack 上で行える

`users:write` が必要な理由:
- アプリが**ユーザー個人の接続状態を書き換える**操作を行うため
- 「読み取り」ではなく「書き込み」操作（`update` = 更新）
- Slack のセキュリティモデルとして、ユーザー情報の変更には明示的な Permission が必要
- これにより、アプリがユーザーの同意なく接続状態を改ざんすることを防止

つまり「Connection」は「サーバーへの TCP/HTTP 接続」ではなく、「ユーザーが外部サービスにログイン済みかどうか」という認証状態を指している。

## 実装プラン

このタスクはドキュメント調査タスクであり、コード変更は不要。

1. ログファイル `logs/0002_what_connection_report.md` を作成し、調査結果を詳細に記録（本ファイル）
2. kanban ファイル `kanban/0002_what_connection_report.md` に完了サマリーを追記

完了サマリーには以下を含める:
- Connection Report の定義と目的
- Permission が必要な理由の説明
- 参照したドキュメント一覧

## プランニング経緯

### 初回提案

以下の内容でプランを提示:
- Connection Report は「エンドポイントの接続状況監視」ではなく「ユーザー個人の外部システム認証状態を Slack UI で管理する機能」
- `users:write` が必要な理由はユーザー情報の「書き込み」操作であるため
- 調査対象ドキュメント 5 点の一覧
- 成果物としてログファイルと kanban 完了サマリー

### ユーザーフィードバック

初回提案がそのまま承認された。

## 会話内容

### [13:45頃] ユーザー指示

`/kanban` コマンドを実行。引数なしのため、未完了タスクのうち番号最大の `0002_what_connection_report.md` が自動選択された。

### [13:46頃] Claude 対応 — タスクファイル読み込み・目的セクション確認

- `kanban/` ディレクトリを確認し、3 ファイル（0000, 0001, 0002）を発見
- `## 完了サマリー` の有無を確認し、0002 のみ未完了と判定
- タスクファイルを読み込み、`## 目的` セクションの存在を確認（「何を目的とした機能なのかがよくわからない。エンドポイントとの接続状況を見るだけなら、ユーザーのPermissionを求める理由がわからない。」）
- `.claude/kanban-workflow.md` を読み込み、ワークフロー手順を確認

### [13:47頃] Claude 対応 — プランモード突入・調査開始

- EnterPlanMode でプランモードに入った
- Explore エージェントを起動し、以下のドキュメントを調査:
  - `docs/enterprise-search/connection-reporting.md`
  - `docs/enterprise-search/` 配下の他ファイル
  - `docs/reference/events/user_connection.md`
  - `docs/reference/methods/apps.user.connection.update.md`
  - `docs/reference/scopes/users.write.md`
  - `docs/ja-jp/` 配下（日本語版）
  - `docs/apis/` 配下の関連 API ドキュメント

### [13:48頃] Claude 対応 — 追加の直接読み込み

Explore エージェントの結果を受けて、以下のファイルを直接読み込んで内容を確認:
- `docs/enterprise-search/connection-reporting.md` — 全文読み込み、Connection Report の定義・フロー・シーケンスを確認
- `docs/enterprise-search/enterprise-search-access-control.md` — アクセス制御との違いを確認
- `docs/enterprise-search/developing-apps-with-search-features.md` — 全文読み込み、Enterprise Search 全体における Connection Report の位置づけを確認
- `docs/reference/events/user_connection.md` — イベントペイロードの詳細を確認
- `docs/reference/methods/apps.user.connection.update.md` — API の引数・レスポンス・エラー一覧を確認
- `docs/enterprise-search/index.md` — 概要ページでの位置づけを確認
- `kanban/0000_search_permission.md` — 前回タスクの Permission 調査結果を参照

### [13:49頃] Claude 対応 — プラン作成・承認

- プランファイルを作成
- kanban ファイルに `## プラン` セクションを追記
- ExitPlanMode でユーザー承認をリクエスト
- ユーザーが承認

### [13:50頃] Claude 対応 — 実装フェーズ開始

- タイムスタンプ取得
- ログファイル作成（本ファイル）

## 編集したファイル

| ファイル | 変更内容 |
|---------|---------|
| `kanban/0002_what_connection_report.md` | `## プラン` セクションを追記、`## 完了サマリー` を追記 |
| `logs/0002_what_connection_report.md` | 新規作成（本ファイル）、完了日時を更新 |

## 実行したコマンド

```bash
TZ=Asia/Tokyo date +"%Y-%m-%dT%H:%M:%S+09:00"
```

## 判断・意思決定

- Connection Report の「Connection」を「サーバーとの TCP/HTTP 接続」ではなく「ユーザーの外部サービスへの認証状態」と解釈した。これはドキュメントの "a user's authentication status, or connection status" という定義に基づく
- ユーザーの疑問の核心は「なぜ `users:write` が必要か」であり、これに対して「読み取りではなく書き込み操作だから」という回答を導出した

## エラー・問題

- なし
