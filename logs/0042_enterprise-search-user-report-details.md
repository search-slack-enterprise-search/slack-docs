# Enterprise Search User Report 詳細 調査ログ

## タスク概要

- **kanban ファイル**: `kanban/0042_enterprise-search-user-report-details.md`
- **知りたいこと**: Enterprise SearchのUser Reportの詳細
- **目的**: User Reportで何ができるのか、何を実装しないといけないのかを詳しく知りたい。特に接続と切断で何を実装しないといけないかを知りたい。
- **調査日**: 2026-04-20

---

## 調査ファイル一覧

| ファイルパス | 内容 |
|---|---|
| `docs/enterprise-search/connection-reporting.md` | Connection Reporting 公式ドキュメント（メイン） |
| `docs/enterprise-search/developing-apps-with-search-features.md` | Enterprise Search 開発ガイド |
| `docs/reference/events/user_connection.md` | user_connection イベントリファレンス |
| `docs/reference/methods/apps.user.connection.update.md` | apps.user.connection.update API リファレンス |
| `kanban/0002_what_connection_report.md` | 0002番 kanban: Connection Reportとは何か |
| `logs/0002_what_connection_report.md` | 0002番 調査ログ |
| `kanban/0014_user_report_not_work.md` | 0014番 kanban: user_reportが動かない矛盾 |
| `logs/0014_user_report_not_work.md` | 0014番 調査ログ（Connection Reportingの本質） |
| `kanban/0015_user-report-disconnect-always.md` | 0015番 kanban: 常時disconnectになる矛盾 |
| `logs/0015_user-report-disconnect-always.md` | 0015番 調査ログ（Push モデルの説明） |

---

## 調査アプローチ

1. メインドキュメント（`connection-reporting.md`）を読み込み、User Report（Connection Reporting）の全体像を把握
2. イベントリファレンス（`user_connection.md`）と API リファレンス（`apps.user.connection.update.md`）で実装の詳細を確認
3. 過去の kanban ログ（0002, 0014, 0015）を読み込み、過去の調査結果を統合
4. 接続フロー・切断フロー別に必要な実装を整理

---

## 調査結果

### 1. User Report（Connection Reporting）とは何か

**ファイル**: `docs/enterprise-search/connection-reporting.md` 行 4-7

> "Slack's connection reporting feature allows your app to communicate a user's authentication status, or connection status, directly to Slack. By offloading the UI management for 'connect/disconnect' states to Slack, you can ensure a consistent user experience while reducing development overhead."

**定義**: Connection Reporting（User Report）は、Enterprise Search アプリがユーザーごとの「接続状態（外部データソースへの認証状態）」を Slack に報告する機能。Slack が "Connect / Connected / Disconnect" ボタンなどの UI 表示を管理する。

**重要な特性**:
- **Push モデル**: アプリが Slack に状態を「報告（Push）」する。Slack がアプリに状態を「問い合わせる（Pull）」のではない
- **オプション機能**: Enterprise Search のコア機能（検索結果の返却）とは独立したオプション機能
- **UI の委譲**: Slack が Connect/Disconnect ボタンの表示を管理することで、開発オーバーヘッドを削減

---

### 2. Connection Reporting が提供するもの・しないもの

| 項目 | Slack が担当 | アプリが担当 |
|------|-------------|-------------|
| Connect/Connected ボタンの UI 表示 | ✓ | — |
| `user_connection` イベントの発火 | ✓ | — |
| `trigger_id` の提供（Connectフロー） | ✓ | — |
| 外部 OAuth フロー | — | ✓（独自実装が必要） |
| 外部 OAuth トークンの取得・保存・リフレッシュ | — | ✓（自社 DB で管理） |
| 接続状態の Slack への報告 | — | ✓（`apps.user.connection.update` を呼ぶ） |

---

### 3. 全体フロー（ドキュメントのシーケンス例）

**ファイル**: `docs/enterprise-search/connection-reporting.md` 行 29-36

1. ユーザーが未接続の場合、Slack 検索 UI に "Connect" ボタンが表示される
2. ユーザーが "Connect" をクリックすると、アプリが `user_connection` イベント（subtype: connect）を受信する。このイベントに `trigger_id` が含まれており、アプリはモーダルを開いてユーザーに接続フローを案内できる
3. ユーザーが接続完了後、アプリは `apps.user.connection.update` API を呼び出して接続状態の変更を Slack に報告し、UI が "Connected" に更新される

---

### 4. user_connection イベントの詳細

**ファイル**: `docs/reference/events/user_connection.md`

#### 基本情報

- **Required Scopes**: `users:write`
- **Compatible APIs**: Events API, RTM API（レガシー）
- **説明**: "A member's user connection status change requested"

#### subtype: connect（接続リクエスト）

ユーザーがアプリとの接続を要求したことを通知する。

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

**重要フィールド**:
- `event.user`: 接続を要求したユーザーの Slack user_id
- `event.trigger_id`: モーダルを開くための trigger_id（`views.open` に使用）

#### subtype: disconnect（切断リクエスト）

ユーザーがアプリからの切断を要求したことを通知する。

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

**重要フィールド**:
- `event.user`: 切断を要求したユーザーの Slack user_id
- `event.enterprise_id`: エンタープライズ ID
- **`trigger_id` がない**（モーダル不要、即座に切断処理を行う）

---

### 5. apps.user.connection.update API の詳細

**ファイル**: `docs/reference/methods/apps.user.connection.update.md`

#### 基本情報

- **説明**: Updates the connection status between a user and an app.
- **エンドポイント**: `POST https://slack.com/api/apps.user.connection.update`
- **スコープ**: User token: `users:write`（注: Bot token でも動作すると推定 — 後述）
- **Rate Limits**: Tier 2: 20+ per minute

#### 必須引数

| パラメータ | 型 | 説明 | 例 |
|-----------|------|------|-----|
| `token` | string | 認証トークン | `xxxx-xxxxxxxxx-xxxx` |
| `user_id` | string | ステータス更新対象のユーザーID | `U12345678` |
| `status` | string | 設定するステータス。`connected` または `disconnected` | `connected` |

#### Bolt SDK でのアクセス方法

- **Bolt for JS**: `app.client.apps.user.connection.update`
- **Bolt for Python**: `app.client.apps_user_connection_update`
- **Bolt for Java**: `app.client().appsUserConnectionUpdate`

#### 成功レスポンス

```json
{ "ok": true }
```

#### 主要なエラー

- `missing_scope`: 必要なスコープ権限がない（`users:write` が付与されていない）
- `user_not_found`: 無効なユーザーID
- `app_not_subscribed`: アプリが必要なイベントをサブスクライブしていない
- `invalid_auth`: トークンが無効

---

### 6. 接続（Connect）フローで実装が必要なもの

`user_connection` イベント（subtype: connect）を受信した時の実装：

1. **イベントハンドラの実装**: `user_connection` イベント（subtype: connect）をリッスンする
2. **モーダルを開く**: `event.trigger_id` を使って `views.open` でモーダルを表示する
   - モーダルの中に外部サービスへの OAuth 認可 URL や接続手順を表示する
3. **OAuth callback エンドポイントの実装**: 外部サービスからの認可コードを受け取る HTTP エンドポイント
4. **トークン交換**: 認可コードをアクセストークン（+ リフレッシュトークン）に交換する
5. **トークンの保存**: アクセストークンを自社データストアに保存する（キー: `event.user` = Slack user_id）
6. **接続状態の報告**: `apps.user.connection.update(user_id: event.user, status: "connected")` を呼び出してSlackに報告する

```
ユーザー → Slack検索UI: "Connect" クリック
    ↓
Slack → アプリ: user_connection イベント (subtype: connect, trigger_id付き)
    ↓
アプリ → Slack: views.open (trigger_id使用) → モーダルに外部サービスのOAuth URLを表示
    ↓
ユーザー → 外部サービス: OAuth認証（ブラウザ）
    ↓
外部サービス → アプリ: OAuth callback (認可コード)
    ↓
アプリ → 外部サービス: トークン交換（認可コード → アクセストークン）
    ↓
アプリ: アクセストークンを自社DBに保存 (キー: Slack user_id)
    ↓
アプリ → Slack: apps.user.connection.update(user_id, status: "connected")
    ↓
Slack → ユーザー: 検索UIが "Connected" 表示に更新
```

---

### 7. 切断（Disconnect）フローで実装が必要なもの

`user_connection` イベント（subtype: disconnect）を受信した時の実装：

1. **イベントハンドラの実装**: `user_connection` イベント（subtype: disconnect）をリッスンする
2. **トークンの削除・失効**: 自社データストアから `event.user` に紐付いたアクセストークンを削除する
   - 外部サービスの API でトークンを失効させることも推奨（サービスによる）
3. **切断状態の報告**: `apps.user.connection.update(user_id: event.user, status: "disconnected")` を呼び出してSlackに報告する

**注意**: disconnect には `trigger_id` が含まれないため、モーダルを開く必要はない。

```
ユーザー → Slack検索UI: "Disconnect" クリック
    ↓
Slack → アプリ: user_connection イベント (subtype: disconnect, trigger_idなし)
    ↓
アプリ: 自社DBからアクセストークンを削除 (キー: event.user)
    ↓（任意）
アプリ → 外部サービス: トークン失効 API 呼び出し
    ↓
アプリ → Slack: apps.user.connection.update(user_id, status: "disconnected")
    ↓
Slack → ユーザー: 検索UIが "Connect" ボタン表示に戻る
```

---

### 8. 必要な設定・スコープ

**マニフェストへの追加が必要なもの**:

```json
{
  "settings": {
    "event_subscriptions": {
      "bot_events": [
        "user_connection"
      ]
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "users:write"
      ]
    }
  }
}
```

**スコープ**:
- `users:write`: `user_connection` イベントの受信と `apps.user.connection.update` の呼び出しに必要

---

### 9. 初期状態と「常時 disconnect」について

**ファイル**: `docs/enterprise-search/connection-reporting.md` 行 17

> "The app is always expected to invoke the `apps.user.connection.update` API method in its connecting flow to notify Slack when a user's connection status changes. **Otherwise, Slack will assume the status for this user has not changed.**"

**重要ポイント**:
- 初期状態は「disconnected」（接続していない）
- これは Connection Reporting の**設計された出発点**であり、機能の失敗ではない
- 「Connect」ボタンはまだ接続していないユーザーが接続を開始するための UI 要素
- 全ユーザーが初期状態から OAuth フローを経て接続状態になっていく設計
- Slack はアプリからの Push（`apps.user.connection.update` 呼び出し）でのみ状態を更新する。Slack 自身がトークンの存在を確認するわけではない

---

### 10. Bot token vs User token の問題

**ファイル**: `docs/reference/methods/apps.user.connection.update.md` 行 41-44

```
Scopes
User token: users:write
```

ドキュメントには "User token" のみ記載されているが、実際には Bot token でも動作すると推定される理由：

- Connection Reporting の唯一のユースケースは Enterprise Search（Bolt アプリ = Bot token）
- Bolt SDK の `app.client.apps_user_connection_update` はデフォルトで Bot token を使用する
- `users:write` スコープ自体は Bot token でも使用可能（`docs/reference/scopes/users.write.md` に "Supported token types: Bot, User, Legacy Bot" と記載）
- ドキュメントの不完全性の可能性が高い

---

## 判断・意思決定

### Connection Reporting はオプション機能

Enterprise Search のコア機能（`function_executed` イベントを受けて `functions.completeSuccess` で検索結果を返す）は `users:write` スコープ不要。Connection Reporting は追加で実装するオプション機能。

### 接続フローと切断フローの実装要件の違い

| フロー | trigger_id | モーダル | トークン操作 | `apps.user.connection.update` |
|--------|------------|---------|------------|-------------------------------|
| connect | あり | 必要（OAuth URL表示） | 取得・保存 | `status: "connected"` |
| disconnect | なし | 不要 | 削除 | `status: "disconnected"` |

---

## 問題・疑問点

1. **`apps.user.connection.update` の Bot token 対応**: ドキュメントには User token のみ記載されているが、実際に Bot token で動作するかどうかはドキュメントスナップショットの範囲では確認できない。公式サンプルアプリ（`bolt-python-search-template` / `bolt-ts-search-template`）のコードで確認可能と推定。

2. **モーダルの自動クローズ**: OAuth 認証をユーザーが別ブラウザで完了した後、Slack のモーダルを自動的に閉じる方法（`views.update` 等）は本調査の範囲外。
