# Enterprise Search と外部認証機能の組み合わせ実装方法 調査ログ

## 調査概要

- **タスクファイル**: `kanban/0009_enterprise-search-external-auth-integration.md`
- **調査日**: 2026-04-16
- **目的**: Enterprise Search の Connection Reporting 機能と外部認証を組み合わせて、外部サービスへの検索時に認可を効かせる実装方法を明らかにする

---

## 調査したファイル一覧

1. `docs/enterprise-search/developing-apps-with-search-features.md`
2. `docs/enterprise-search/connection-reporting.md`
3. `docs/enterprise-search/enterprise-search-access-control.md`
4. `docs/enterprise-search/index.md`
5. `docs/reference/events/user_connection.md`
6. `docs/reference/methods/apps.user.connection.update.md`
7. `docs/reference/methods/functions.completeError.md`
8. `docs/reference/methods/apps.connections.open.md`
9. `docs/authentication/binding-accounts-across-services.md`
10. 過去ログ: `logs/0004_slack-external-auth.md`
11. 過去ログ: `logs/0007_enterprise-search-user-context-fields.md`
12. 過去ログ: `logs/0008_enterprise-search-oauth-token-from-user-context.md`

---

## 調査アプローチ

1. 過去ログ (0007, 0008) の内容を確認し、user_context / External Auth の既知事項を整理
2. Enterprise Search のメインドキュメント (`developing-apps-with-search-features.md`) を精読
3. Connection Reporting ドキュメント (`connection-reporting.md`) を精読
4. `user_connection` イベントと `apps.user.connection.update` API を確認
5. `functions.completeError` の認証エラー対応パターンを確認
6. Deno SDK の `credential_source: "END_USER"` が Enterprise Search に適用できるか検討
7. advisor に確認

---

## 調査結果

### 1. Enterprise Search の search_function で使用できる入力パラメータ

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`（行 51–83）

search_function のドキュメントに記載されている入力パラメータは以下のみ:

| フィールド | 型 | 説明 | 必須 |
|---|---|---|---|
| `query` | string | エンドユーザーが検索時に入力したクエリ文字列 | Required |
| `filters` | object | ユーザーが選択したフィルターのキーバリューペア | Optional |
| `*` (任意名) | `slack#/types/user_context` | 検索を実行しているユーザーの user_context が自動注入される | Optional |

**重要**: `oauth2` 型のパラメータは search_function のドキュメントに記載されていない。

#### 対比: Deno Workflow Function では oauth2 型が使用可能

```typescript
// Deno SDK ワークフロー関数では oauth2 型を使えるが、
// Enterprise Search の search_function では文書化されていない
googleAccessTokenId: {
  type: Schema.slack.types.oauth2,
  oauth2_provider_key: "google",
},
```

Deno SDK の `credential_source: "END_USER"` は **Link Trigger** からのみ動作するため、Enterprise Search 専用のトリガーには適用できない。

---

### 2. Connection Reporting の仕組み

**ファイル**: `docs/enterprise-search/connection-reporting.md`

Connection Reporting は Slack の UI でユーザーの「接続/切断」状態を管理する機能。

> "Slack's connection reporting feature allows your app to communicate a user's authentication status, or connection status, directly to Slack. By offloading the UI management for 'connect/disconnect' states to Slack, you can ensure a consistent user experience while reducing development overhead."

**重要な境界**: `apps.user.connection.update` は UI の表示状態のみを更新する。**OAuth トークンの管理は行わない**。

#### Connection Reporting の役割と限界

| 役割 | Slack が管理するもの | アプリが管理するもの |
|---|---|---|
| UI | 「Connect」/「Connected」ボタン表示 | - |
| イベント通知 | `user_connection` イベント発火 | イベントハンドラの実装 |
| OAuth フロー | - | OAuth フロー全体（認可 URL の生成・リダイレクト・コールバック処理） |
| トークン管理 | - | トークンの保存・取得・リフレッシュ・失効処理 |
| 接続状態 | UI の表示更新のみ | アプリ独自のデータストアでの状態管理 |

---

### 3. user_connection イベント

**ファイル**: `docs/reference/events/user_connection.md`

`user_connection` イベントには `subtype: connect` と `subtype: disconnect` の2種類がある。

#### subtype: connect（接続要求）

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

- `event.user`: Slack user_id（例: `U012A3BC4DE`）
- `event.trigger_id`: **モーダルを開くための trigger_id**（これを使って `views.open` でモーダルを開く）

#### subtype: disconnect（切断要求）

```json
{
  "event": {
    "type": "user_connection",
    "subtype": "disconnect",
    "enterprise_id": "E012A3BC4DE",
    "user": "U012A3BC4DE",
    "event_ts": "1764264317.061589"
  }
}
```

- `event.user`: 切断するユーザーの Slack user_id
- `event.enterprise_id`: Enterprise ID

**必要なスコープ**: `users:write`

---

### 4. apps.user.connection.update API

**ファイル**: `docs/reference/methods/apps.user.connection.update.md`

```
POST https://slack.com/api/apps.user.connection.update
```

**必須引数**:

| 引数 | 型 | 説明 |
|---|---|---|
| `token` | string | 認証トークン |
| `user_id` | string | 接続状態を更新するユーザーの ID（例: `U12345678`） |
| `status` | string | 設定するステータス: `connected` または `disconnected` |

**レスポンス**:
```json
{ "ok": true }
```

**スコープ**: `users:write`（User token）

---

### 5. functions.completeError での認証エラー対応

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`（行 303）

> "The `functions.completeError` API method provides Slack with a user-friendly error message and informs Slack that the `function_executed` event completed with an error. The error message provided by your app will be displayed to the user on the search page. It can be any plain text value with links you think could be insightful to the user. **For example: _Authentication Required: Please visit https://getauthhere.slack.dev to authenticate your account._**"

この例が示すように、ユーザーが外部サービスに接続していない場合、`functions.completeError` でリンク付きの認証要求メッセージを返すことが Slack によって明示的に想定されている。

---

### 6. 全体的な実装アーキテクチャ

Enterprise Search + 外部認証の統合パターンは、以下の3フェーズで構成される。

#### フェーズ1: 接続フロー（user_connection: connect）

```
ユーザー → Slack検索UI:「Connect」クリック
    ↓
Slack → アプリ: user_connection イベント (subtype: connect)
  - event.user = Slack user_id
  - event.trigger_id = モーダル開始用 trigger_id
    ↓
アプリ → Slack: views.open (trigger_id 使用)
  - モーダルに外部サービスへの OAuth 認可 URL を表示
    ↓
ユーザー → 外部サービス: OAuth フロー完了
    ↓
外部サービス → アプリ: OAuth callback (認可コード)
    ↓
アプリ → 外部サービス: トークン交換（認可コード → アクセストークン）
    ↓
アプリ: アクセストークンを自社データストアに保存
  - キー: Slack user_id
  - バリュー: アクセストークン（+ リフレッシュトークン + 有効期限）
    ↓
アプリ → Slack: apps.user.connection.update (user_id, status: "connected")
    ↓
Slack → ユーザー: 検索UI が「Connected」表示に更新
```

#### フェーズ2: 切断フロー（user_connection: disconnect）

```
ユーザー → Slack検索UI:「Disconnect」クリック
    ↓
Slack → アプリ: user_connection イベント (subtype: disconnect)
  - event.user = Slack user_id
    ↓
アプリ: データストアからトークンを削除（または無効化）
  - オプション: 外部サービスの token revoke エンドポイントを呼ぶ
    ↓
アプリ → Slack: apps.user.connection.update (user_id, status: "disconnected")
    ↓
Slack → ユーザー: 検索UI が「Connect」表示に戻る
```

#### フェーズ3: 検索フロー（function_executed: search_function）

```
ユーザー → Slack: 検索クエリを入力
    ↓
Slack → アプリ: function_executed イベント
  - inputs.query = 検索クエリ
  - inputs.user_context = { id: "U012A3BC4DE", secret: "..." }
    ↓
アプリ: user_context.id でデータストアからトークンを取得
    ↓
[トークンが見つからない場合]
アプリ → Slack: functions.completeError
  - error: "Authentication Required: Please connect your account at https://..."
  → Slack がユーザーの検索画面にエラーメッセージを表示
    ↓
[トークンが見つかった場合]
アプリ → 外部サービス: 外部API リクエスト
  - Authorization: Bearer {accessToken}
  ↓
外部サービス → アプリ: 検索結果
    ↓
アプリ → Slack: functions.completeSuccess
  - outputs.search_results = [{ title, description, link, date_updated, external_ref }]
    ↓
Slack → ユーザー: 検索結果を表示
```

---

### 7. App Manifest の設定

Enterprise Search + Connection Reporting + 外部認証を組み合わせる場合の Manifest 設定:

```json
{
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "bot_events": [
        "function_executed",
        "user_connection"
      ]
    },
    "app_type": "remote",
    "function_runtime": "remote"
  },
  "features": {
    "search": {
      "search_function_callback_id": "search_results_function",
      "search_filters_function_callback_id": "search_filters_function"
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

**注意**: `externalAuthProviders` (Deno SDK の機能) は含まない。外部認証は完全にアプリ独自で管理する。

---

### 8. Bolt を使った実装スケルトン（Python の例）

```python
from slack_bolt import App

app = App(token=os.environ["SLACK_BOT_TOKEN"])

# ユーザーが「Connect」をクリックしたとき
@app.event("user_connection")
def handle_user_connection(event, client, logger):
    subtype = event.get("subtype")
    user_id = event.get("user")
    
    if subtype == "connect":
        trigger_id = event.get("trigger_id")
        # モーダルを開いて OAuth フロー開始を案内
        client.views_open(
            trigger_id=trigger_id,
            view={
                "type": "modal",
                "title": {"type": "plain_text", "text": "Connect to External Service"},
                "blocks": [
                    {
                        "type": "section",
                        "text": {
                            "type": "mrkdwn",
                            "text": "Click the button below to connect your account:\n<https://your-service.example.com/oauth/start?slack_user_id={user_id}|Connect Now>"
                        }
                    }
                ]
            }
        )
    
    elif subtype == "disconnect":
        # トークンをデータストアから削除
        token_store.delete(user_id)
        # 接続状態を Slack に通知
        client.apps_user_connection_update(
            user_id=user_id,
            status="disconnected"
        )

# OAuth callback: 外部サービスから認可コードを受け取る
# （Bolt の HTTP ハンドラーや Flask などで実装）
@flask_app.route("/oauth/callback")
def oauth_callback():
    code = request.args.get("code")
    slack_user_id = request.args.get("state")  # state に slack_user_id を渡す
    
    # 認可コードをアクセストークンに交換
    token_response = exchange_code_for_token(code)
    access_token = token_response["access_token"]
    
    # トークンをデータストアに保存
    token_store.save(slack_user_id, access_token)
    
    # 接続状態を Slack に通知
    app.client.apps_user_connection_update(
        user_id=slack_user_id,
        status="connected"
    )
    
    return "Connected successfully! You can close this window."


# 検索が実行されたとき
@app.event("function_executed")
def handle_function_executed(event, client, logger):
    function_callback_id = event.get("function", {}).get("callback_id")
    
    if function_callback_id == "search_results_function":
        inputs = event.get("inputs", {})
        query = inputs.get("query")
        user_context = inputs.get("user_context", {})
        user_id = user_context.get("id")
        function_execution_id = event.get("function_execution_id")
        
        # ユーザーのアクセストークンを取得
        access_token = token_store.get(user_id)
        
        if not access_token:
            # 未接続の場合: 認証要求エラーを返す
            client.functions_completeError(
                function_execution_id=function_execution_id,
                error="Authentication Required: Please connect your account at https://your-service.example.com/connect"
            )
            return
        
        # 外部APIに検索リクエスト
        try:
            results = external_service.search(
                query=query,
                token=access_token
            )
        except TokenExpiredError:
            # トークン期限切れの場合
            client.functions_completeError(
                function_execution_id=function_execution_id,
                error="Your session has expired. Please reconnect at https://your-service.example.com/connect"
            )
            return
        
        # 検索結果を返す
        client.functions_completeSuccess(
            function_execution_id=function_execution_id,
            outputs={
                "search_results": [
                    {
                        "external_ref": {"id": r["id"]},
                        "title": r["title"],
                        "description": r["description"],
                        "link": r["url"],
                        "date_updated": r["updated_at"],
                    }
                    for r in results
                ]
            }
        )
```

---

## 判断・意思決定

### Deno SDK の credential_source が使えない理由

Deno SDK の `credential_source: "END_USER"` は Link Trigger（ユーザーがリンクをクリックして起動するワークフロー）でのみ動作する。Enterprise Search の search_function は Slack が直接呼び出すもので、ワークフローのステップとして実行されるわけではないため、この仕組みが適用できない。

また、search_function のドキュメントに記載されている入力パラメータは `query`、`filters`、`user_context` のみで、`oauth2` 型は文書化されていない。

**結論**: Enterprise Search + 外部認証の統合では、Connection Reporting を活用しつつ、OAuth フローとトークン管理をアプリ独自で実装するのが、ドキュメントで明示的にサポートされているアプローチ。

### Connection Reporting の位置づけ

Connection Reporting は認証状態の「見た目」を Slack に委譲する機能。実際のトークン管理はすべてアプリ側の責任。

- Slack が管理するもの: 「Connect」/「Connected」/「Disconnect」ボタンの表示
- アプリが管理するもの: OAuth フロー、トークンの保存・取得・更新・削除

---

## 問題・疑問点

1. **モーダルの OAuth フロー**: `user_connection: connect` で開くモーダルに外部サービスへのリンクを表示するのは確認できたが、モーダルから直接リダイレクトして戻ってきた後、自動的にモーダルを閉じる仕組みの具体的な実装は不明。（通常は `views.update` や WebSocket を使うパターンが考えられる）

2. **trigger_id の有効期限**: `user_connection` イベントの `trigger_id` の有効期限（通常は3秒以内に `views.open` を呼ぶ必要がある）については未確認。

3. **search_function での oauth2 型**: `oauth2` 型パラメータが search_function で使えないとドキュメントには明示されていない（単に記載がないだけ）。実際に使えるかどうかは未検証。

4. **token_store の実装**: アプリ独自のトークンストアの実装（暗号化、KMS 管理など）は開発者の責任。Slack はガイドラインを提供していない。

5. **Bolt フレームワークでのトークン管理**: Bolt Python/JS の bolt-python-search-template や bolt-ts-search-template の実際のコードが外部 GitHub にあり、そこに実装例があると考えられるが、ドキュメント内には含まれていない。

---

## まとめ

### Enterprise Search + 外部認証 の組み合わせ実装方法

Enterprise Search では Deno SDK の `credential_source: "END_USER"` は使えず、**Connection Reporting** + **アプリ独自の OAuth トークン管理** の組み合わせが公式ドキュメントで想定されているアプローチ。

**主要コンポーネント**:

| コンポーネント | 役割 |
|---|---|
| `user_connection` イベント (`subtype: connect`) | ユーザーの接続開始要求の通知。`trigger_id` を使ってモーダルを開く |
| `views.open` + `trigger_id` | ユーザーに OAuth フロー開始の UI を提示 |
| アプリの OAuth callback エンドポイント | 外部サービスからの認可コードを受け取り、トークンを取得 |
| アプリ独自のデータストア | `user_id` をキーにしてアクセストークンを安全に保存 |
| `apps.user.connection.update` | Slack の UI に接続状態を通知（`connected` / `disconnected`） |
| `user_connection` イベント (`subtype: disconnect`) | ユーザーの切断要求。トークン削除 + `disconnected` 通知 |
| search_function 内での `user_context.id` | 検索時にデータストアからトークンを取得するキー |
| `functions.completeError` | 未接続ユーザーへの認証要求メッセージ表示 |
| `functions.completeSuccess` | 検索結果の返却 |

**Slack が明示的に想定している認証エラーパターン**（`developing-apps-with-search-features.md` 行 303）:
> "Authentication Required: Please visit https://getauthhere.slack.dev to authenticate your account."
