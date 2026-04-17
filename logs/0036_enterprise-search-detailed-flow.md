# Enterprise Search 詳細フロー 調査ログ

## 調査概要

- **タスク**: 0036_enterprise-search-detailed-flow
- **調査日**: 2026-04-17
- **目的**: Enterprise Searchを実装する上でフローを理解する

---

## 調査ファイル一覧

- `docs/enterprise-search/index.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/enterprise-search-access-control.md`
- `docs/enterprise-search/connection-reporting.md`
- `docs/messaging/work-objects-overview.md`
- `docs/messaging/work-objects-implementation.md`
- `docs/apis/web-api/real-time-search-api.md`
- `docs/apis/events-api/index.md`
- `docs/authentication/index.md`
- `docs/authentication/installing-with-oauth.md`
- `docs/authentication/tokens.md`
- `docs/reference/methods/functions.completeSuccess.md`
- `docs/reference/methods/functions.completeError.md`
- `docs/reference/methods/apps.user.connection.update.md`
- `docs/reference/methods/entity.presentDetails.md`

---

## 調査結果

### 1. Enterprise Search の全体フロー

ユーザーが検索してから結果が表示されるまでの流れ:

```
[ユーザーが検索]
    ↓
[Slack が query をパース/リライト]
    ↓
[キャッシュをチェック (3分間)]
    ↓
[Slack がアプリへ function_executed イベントを送信]
    ↓
[アプリが検索実行 (最大10秒)]
    ↓
[functions.completeSuccess で結果を返却]
    ↓
[Slack が検索結果を UI 表示]
    ↓
[ユーザーが結果をクリック → entity_details_requested イベント送信]
    ↓
[アプリが entity.presentDetails で Flexpane 詳細を返却]
```

**キャッシング戦略:**
- 検索結果: 各ユーザーと各クエリの組み合わせで最大3分間キャッシュ
- AI の回答: 同じく3分間キャッシュ（検索結果に基づく）
- フィルター: ユーザーごとに最大3分間キャッシュ

---

### 2. App Manifest の設定

```json
{
  "features": {
    "search": {
      "search_function_callback_id": "search_func_123",
      "search_filters_function_callback_id": "filter_func_456"
    }
  },
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "bot_events": [
        "function_executed",
        "entity_details_requested"
      ]
    },
    "app_type": "remote",
    "function_runtime": "remote"
  }
}
```

- `search_function_callback_id`: 必須
- `search_filters_function_callback_id`: オプション（フィルター機能が必要な場合）
- `entity_details_requested`: Work Objects（Flexpane）使用時に必須

---

### 3. 実装すべきカスタム関数（ステップ）

#### A. 検索関数（search_function）

**入力パラメータ:**

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `query` | string | ✓ | ユーザー入力の検索文字列（Slack でリライト済み） |
| `filters` | object | - | ユーザーが選択したフィルター（key-value） |
| `*` (user_context型) | user_context | - | ユーザーの文脈情報 |

**出力パラメータ:**

単一の出力パラメータ `search_results`（型: `slack#/types/search_results`）が必須:

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `external_ref` | object | ✓ | `{id: string, type?: string}` リソースを一意に識別 |
| `title` | string | ✓ | 簡潔な見出し |
| `description` | string | ✓ | 説明文（AI の回答生成に使用） |
| `link` | string | ✓ | ソースへの URI |
| `date_updated` | string | ✓ | "YYYY-MM-DD" 形式 |
| `content` | string | - | 詳細コンテンツ（AI がより詳細な回答を生成する場合に有用） |

最大50件まで返却可能。

#### B. フィルター関数（search_filters_function）

**入力パラメータ:**
- user_context 型の任意パラメータ

**出力パラメータ:**
- `filter`（型: `slack#/types/search_filters`）: 最大5個の filter オブジェクトの配列

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `name` | string | ✓ | 機械可読な一意の名前 |
| `display_name` | string | ✓ | 人間が読める名前 |
| `display_name_plural` | string | - | 複数選択時に使用（type: multi_select の場合推奨） |
| `type` | string | ✓ | "multi_select" または "toggle" |
| `options` | object[] | ◆ | type=multi_select の場合必須 |

---

### 4. イベントハンドラーの詳細

#### A. function_executed イベント

**処理要件:**
- 10秒以内に完了する必要がある
- `functions.completeSuccess` または `functions.completeError` を呼び出す
- HTTP 200 OK で受信を確認（ACK）
- ワークフロートークン（`xwfp-`）は `functions.complete*` 呼び出し後に無効化

**Bolt フレームワークでの制御:**
- Bolt for Python: `auto_acknowledge=False`, `ack_timeout=10`
- Bolt for Node: `auto_acknowledge=False`

**イベントペイロード構造:**
```json
{
  "type": "event_callback",
  "event": {
    "type": "function_executed",
    "function": {
      "id": "Ff12345ABCDE",
      "callback_id": "search_func_123"
    },
    "inputs": {
      "query": "project status update",
      "filters": {
        "team": "engineering",
        "date_range": "last_week"
      }
    },
    "execution_id": "Fx12345ABCDE"
  },
  "trigger_id": "1234567890.1234567890.abc...",
  "action_token": "actn-1234567..."
}
```

#### B. entity_details_requested イベント

**発火条件:**
- ユーザーが初めて Work Object unfurl を開く
- ユーザーが「更新」ボタンを明示的にクリック
- 前回の `entity_details_requested` から10分以上経過して再オープン
- 10分以内での再オープンやタブ切り替えは発火しない

**イベント構造:**
```json
{
  "type": "entity_details_requested",
  "user": "U0123456",
  "external_ref": {
    "id": "123",
    "type": "my-type"
  },
  "entity_url": "https://example.com/doc/123",
  "app_unfurl_url": "https://example.com/doc/123?myquery=param",
  "link": {
    "url": "https://example.com/document/123",
    "domain": "example.com"
  },
  "trigger_id": "1234567890.123.abc...",
  "user_locale": "en-US",
  "channel": "C123ABC456",
  "message_ts": "1755035323.759739",
  "thread_ts": "1755035323.759739",
  "event_ts": "123456789.1234566"
}
```

#### C. user_connection イベント（外部認証用）

```json
{
  "type": "user_connection",
  "user_id": "U123ABC456",
  "trigger_id": "1234567890123.1234567890123.abc...",
  "subtype": "connect"
}
```

---

### 5. Slack → アプリへのリクエスト詳細

**クエリの変換:**
- 入力: ユーザーが入力した生のテキスト
- 変換内容: セキュリティ解析、Slack標準検索との統一、改善
- アプリは「変換後のクエリ」を受け取る（元のテキストではない）

---

### 6. アプリ → Slack へのレスポンス形式

#### A. functions.completeSuccess

```
POST https://slack.com/api/functions.completeSuccess
```

| パラメータ | 型 | 必須 | 説明 |
|---|---|---|---|
| `token` | string | ✓ | ワークフロートークン（イベントから取得） |
| `function_execution_id` | string | ✓ | イベントの `execution_id` |
| `outputs` | object | ✓ | 出力パラメータオブジェクト |

**レスポンス例:**
```json
{
  "outputs": {
    "search_results": [
      {
        "external_ref": {"id": "doc-456", "type": "document"},
        "title": "Q4 Planning Document",
        "description": "Quarterly planning summary with budget and timeline",
        "content": "Full document content for AI processing...",
        "link": "https://example.com/docs/q4-planning",
        "date_updated": "2026-04-15"
      }
    ]
  }
}
```

#### B. functions.completeError

```
POST https://slack.com/api/functions.completeError
```

| パラメータ | 型 | 必須 | 説明 |
|---|---|---|---|
| `token` | string | ✓ | ワークフロートークン |
| `function_execution_id` | string | ✓ | イベントの `execution_id` |
| `error` | string | ✓ | ユーザーに表示するエラーメッセージ（プレーンテキスト、リンク可） |

#### C. entity.presentDetails

```
POST https://slack.com/api/entity.presentDetails
```

| パラメータ | 型 | 必須 | 説明 |
|---|---|---|---|
| `token` | string | ✓ | Bot or workflow token |
| `trigger_id` | string | ✓ | entity_details_requested イベントから取得 |
| `metadata` | object | - | Work Object のメタデータ |
| `user_auth_required` | boolean | - | 認証が必要な場合 true |
| `user_auth_url` | string | - | 認証ページの URL |
| `error` | object | - | エラー情報 |

**metadata 内の entity_payload 構造:**
```json
{
  "entity_type": "slack#/entities/task",
  "url": "https://example.com/tasks/123",
  "external_ref": {"id": "123", "type": "task"},
  "entity_payload": {
    "attributes": {
      "title": {"text": "Implement new search feature"},
      "display_type": "Task",
      "product_name": "Example App",
      "product_icon": {"url": "https://example.com/icon.png", "alt_text": "App Icon"},
      "metadata_last_modified": 1741164235
    },
    "fields": {
      "description": {"value": "Add enterprise search capability", "format": "markdown"},
      "status": {"value": "in_progress", "tag_color": "blue"},
      "assignee": {"type": "slack#/types/user", "user": {"user_id": "U123ABC456"}},
      "due_date": {"value": "2026-05-01", "type": "slack#/types/date"}
    },
    "custom_fields": [],
    "display_order": ["description", "status", "assignee", "due_date"],
    "actions": {
      "primary_actions": [{"text": "Open in App", "action_id": "open_task", "style": "primary"}],
      "overflow_actions": []
    }
  }
}
```

**サポートされる Entity Type:**

| Entity Type | 用途 |
|---|---|
| `slack#/entities/file` | ドキュメント、スプレッドシート、画像など |
| `slack#/entities/task` | チケット、TODO など |
| `slack#/entities/incident` | インシデント、サービス中断など |
| `slack#/entities/content_item` | コンテンツページ、記事など |
| `slack#/entities/item` | 汎用エンティティ |

#### D. apps.user.connection.update

```
POST https://slack.com/api/apps.user.connection.update
```

| パラメータ | 型 | 必須 | 説明 |
|---|---|---|---|
| `token` | string | ✓ | User token (scope: users:write) |
| `user_id` | string | ✓ | ユーザー ID |
| `status` | string | ✓ | "connected" または "disconnected" |

---

### 7. 認証フロー

#### A. OAuth 2.0 フロー（標準インストール）

```
[ユーザーが "Add to Slack" をクリック]
    ↓
[Slack が https://slack.com/oauth/v2/authorize へリダイレクト]
パラメータ:
  - client_id, scope, user_scope, redirect_uri, state
    ↓
[ユーザーがスコープを承認]
    ↓
[Slack が redirect_uri にリダイレクト]
URL: https://example.com/slack/oauth_callback?code=xXxX&state=xxxxx
    ↓
[アプリが oauth.v2.access を呼び出し]
    ↓
[Slack がトークンを返却]
{
  "access_token": "xoxb-...",    // Bot token
  "authed_user": {
    "access_token": "xoxp-..."   // User token (user_scope 要求時)
  }
}
```

#### B. トークンタイプ

| トークン | プレフィックス | 有効期限 | 用途 |
|---|---|---|---|
| Bot Token | `xoxb-` | 無制限 | メッセージ送信、API 呼び出し |
| Workflow Token | `xwfp-` | 15分 or 関数完了 | 関数実行時の一時トークン |
| User Token | `xoxp-` | 無制限 | ユーザーの代わりにアクション実行 |

- Workflow Token は `functions.complete*()` 呼び出し後に無効化

#### C. Enterprise Search 用スコープ

検索実行自体にはスコープ不要（ワークフロートークン使用）。
Real-time Search API 使用時のみ以下が必要:

| スコープ | 用途 |
|---|---|
| `search:read.public` | 公開チャネル検索（必須） |
| `search:read.private` | プライベートチャネル検索（User token） |
| `search:read.mpim` | マルチユーザー DM 検索（User token） |
| `search:read.im` | DM 検索（User token） |
| `search:read.files` | ファイル検索 |
| `search:read.users` | ユーザー検索 |

#### D. 外部認証フロー（ユーザー接続管理）

```
[Slack で Enterprise Search 結果を見る]
    ↓
[未認証の場合、"Connect" ボタン表示]
    ↓
[ユーザーが "Connect" をクリック]
    ↓
[Slack が user_connection イベント送信 (subtype: connect)]
    ↓
[アプリが trigger_id を使ってモーダルを表示]
    ↓
[ユーザーが認証完了]
    ↓
[アプリが apps.user.connection.update を呼び出し]
→ status: "connected"
    ↓
[Slack UI が "Connected" に更新]
```

---

### 8. Work Objects との関係

- Enterprise Search の検索結果が Work Object として Slack 内で表示される
- Flexpane 詳細は `entity_details_requested` → `entity.presentDetails` のフローで実現
- AI 回答の引用元として Work Object のメタデータが使われる
- **external_ref は変更してはいけない**（Related Conversations が壊れる）

---

### 9. タイムアウト・制約

| 制約 | 値 | 説明 |
|---|---|---|
| 検索関数実行 | 10秒 | function_executed ～ functions.complete*() |
| フィルター関数実行 | 10秒 | 同上 |
| Flexpane データ更新 | 10分 | entity_details_requested の再発火 |
| イベント ACK | 3秒（デフォルト） | HTTP 200 OK |
| 検索結果最大数 | 50件 | search_results 配列 |
| フィルター最大数 | 5個 | filter 配列 |
| Primary Actions | 2個 | Work Object の primary_actions |
| Overflow Actions | 5個 | Work Object の overflow_actions |
| Authorization Code 有効期限 | 10分 | OAuth の code パラメータ |
| Workflow Token 有効期限 | 15分 or 関数完了 | 先に来た方 |
| 検索結果キャッシュ | 3分 | user × query ごと |
| フィルターキャッシュ | 3分 | user 単位 |
| Flexpane キャッシュ | 10分 | entity_details_requested 再発火まで |

---

### 10. 全体データフロー図

```
┌────────────────────────────────────────────────────┐
│                  ユーザー操作層                      │
└──────────────┬─────────────────────────────────────┘
               │
               ① ユーザーが検索入力
               │
               ↓
┌────────────────────────────────────────────────────┐
│                    Slack 層                         │
├────────────────────────────────────────────────────┤
│ ② query をリライト（セキュリティ解析、統一化）       │
│ ③ キャッシュ確認 (3分間)                            │
│   HIT → そのまま結果表示                            │
│   MISS → function_executed イベント送信             │
└──────────────┬─────────────────────────────────────┘
               │
               ④ function_executed イベント送信
               │  {query, filters, execution_id, trigger_id}
               ↓
┌────────────────────────────────────────────────────┐
│               アプリケーション層                     │
├────────────────────────────────────────────────────┤
│ ⑤ 検索ロジック実行（10秒以内）                      │
│   外部システムへクエリ → 結果セット生成              │
│                                                    │
│ ⑥ functions.completeSuccess 呼び出し               │
│   search_results[] 送信（最大50件）                 │
│   各結果: external_ref, title, description,        │
│           link, date_updated, [content]            │
└──────────────┬─────────────────────────────────────┘
               │
               ↓
┌────────────────────────────────────────────────────┐
│                    Slack 層                         │
├────────────────────────────────────────────────────┤
│ ⑦ 結果をキャッシュ（3分）                           │
│ ⑧ 検索結果リスト表示                               │
│ ⑨ AI 生成回答（description + content 参照）        │
│ ⑩ Work Object Unfurl 表示                          │
└──────────────┬─────────────────────────────────────┘
               │
               ⑪ ユーザーが結果をクリック
               │  entity_details_requested イベント送信
               │  {external_ref, trigger_id, user, user_locale}
               ↓
┌────────────────────────────────────────────────────┐
│               アプリケーション層                     │
├────────────────────────────────────────────────────┤
│ ⑫ 詳細データ取得・権限確認                          │
│ ⑬ entity.presentDetails 呼び出し                   │
│   entity_payload: {attributes, fields,             │
│                    custom_fields, actions}          │
└──────────────┬─────────────────────────────────────┘
               │
               ↓
┌────────────────────────────────────────────────────┐
│                    Slack 層                         │
├────────────────────────────────────────────────────┤
│ ⑭ Flexpane 詳細表示                                │
│   attributes, fields, actions, Related Convo       │
│ ⑮ 10分後 → entity_details_requested 再発火         │
└────────────────────────────────────────────────────┘
```

---

### 11. 具体的な実装フロー例

#### 検索関数実装パターン

```
function_executed イベント受信
→ inputs.query + inputs.filters で外部 DB 検索
→ 結果を search_results オブジェクトに変換
   external_ref.id = DB の document_id
   title         = ドキュメントタイトル
   description   = 最初の 200 文字（AI 用）
   content       = 全文（AI 用、任意）
   link          = 外部システムの URL
   date_updated  = "YYYY-MM-DD"
→ functions.completeSuccess 呼び出し
→ Slack が結果をキャッシュ（3分）して表示
```

#### Flexpane 詳細表示パターン

```
entity_details_requested イベント受信
→ user_locale 確認（ローカライズ対応）
→ external_ref.id から詳細データ取得
→ ユーザーのアクセス権限確認
   権限あり  → entity_payload を組み立てて entity.presentDetails 呼び出し
   権限なし  → user_auth_required=true で entity.presentDetails 呼び出し
   接続なし  → error.status="custom_partial_view" で entity.presentDetails 呼び出し
→ Slack が Flexpane を詳細表示
```

#### 外部認証フロー実装パターン

```
user_connection イベント受信 (subtype: connect)
→ trigger_id で views.open（認証 URL を含む modal 表示）
→ ユーザーが外部システムで認可完了
→ アプリが callback 受け取り
→ apps.user.connection.update 呼び出し (status: "connected")
→ Slack UI が "Connected" に更新
```

---

## 問題・疑問点

特になし。ドキュメントから必要な情報を網羅的に確認できた。

---

## 調査アプローチ

- `enterprise-search/developing-apps-with-search-features.md` を中心に、全体フローを把握
- `messaging/work-objects-implementation.md` で Flexpane 詳細フローを確認
- `authentication/` 系ファイルで認証フローを補完
- `reference/methods/` 以下の各 API リファレンスで具体的なパラメータを確認
