# Enterprise Search 外部サービス認証の実装方法 調査ログ

## 調査概要

- **タスクファイル**: `kanban/0016_enterprise-search-external-auth-implementation.md`
- **調査日**: 2026-04-16
- **目的**: 0015番で「Connection Reporting は Slack の外部 OAuth トークン管理機能ではなく UI scaffolding である」と確認した。ならば Enterprise Search で外部サービスへの認証を実際にどのように実装するのかを明らかにする。

---

## 調査ファイル一覧

| ファイルパス | 内容 |
|---|---|
| `kanban/0016_enterprise-search-external-auth-implementation.md` | タスクファイル |
| `docs/enterprise-search/developing-apps-with-search-features.md` | Enterprise Search 開発ガイド |
| `docs/enterprise-search/connection-reporting.md` | Connection Reporting 公式ドキュメント |
| `docs/enterprise-search/enterprise-search-access-control.md` | End User Access Control |
| `docs/authentication/binding-accounts-across-services.md` | サービス間アカウントバインディング |
| `docs/authentication/installing-with-oauth.md` | OAuth フロー詳細 |
| `docs/reference/events/user_connection.md` | user_connection イベントリファレンス |
| `docs/reference/methods/apps.user.connection.update.md` | apps.user.connection.update API リファレンス |
| `docs/reference/methods/views.open.md` | views.open API リファレンス |
| 過去ログ: `logs/0009_enterprise-search-external-auth-integration.md` | 外部認証統合アーキテクチャ（詳細） |
| 過去ログ: `logs/0010_oauth-token-refresh-in-own-db.md` | トークン管理・リフレッシュ |
| 過去ログ: `logs/0015_user-report-disconnect-always.md` | Connection Reporting の仕組みの確認 |

---

## 調査アプローチ

1. 0015番で確認した「Connection Reporting = Push モデルの UI scaffolding」を前提に整理
2. 主要ドキュメントを精読し、外部認証実装に必要な構成要素を網羅する
3. 過去ログ（0009・0010・0015）を参照し、既確認事項を統合
4. 実装手順を 3 フェーズで体系化する

---

## 調査結果

### 1. 前提の整理（0015番からの継続）

0015番で確認した通り：

- **Connection Reporting は Push モデル**: Slack が OAuth トークンの有無を確認するのではなく、アプリが Slack に接続状態を通知（`apps.user.connection.update`）する
- **Connection Reporting が提供するもの**: 「Connect / Connected / Disconnect」ボタンの UI、`user_connection` イベントの通知
- **Connection Reporting が提供しないもの**: OAuth フロー、トークンの保存・管理、外部サービスへのアクセス

したがって「外部サービスへの認証をどう実装するか」は、Connection Reporting の外側にある問題であり、**アプリが独自に実装する部分**である。

---

### 2. 全体アーキテクチャの概要

Enterprise Search で外部サービス認証を実装するための構成要素:

| 構成要素 | 提供者 | 役割 |
|---|---|---|
| `user_connection` イベント | Slack | ユーザーが「Connect / Disconnect」ボタンを押したことをアプリに通知 |
| `trigger_id` | Slack | モーダルを開くためのトークン（`user_connection: connect` イベントに含まれる） |
| `views.open` | Slack API | `trigger_id` を使ってモーダルをユーザーに表示 |
| OAuth 認可 URL | **アプリが生成** | 外部サービスへの認可リクエスト URL（nonce/state を含む） |
| OAuth callback エンドポイント | **アプリが実装** | 外部サービスから認可コードを受け取り、トークンに交換 |
| トークンストア | **アプリが管理** | Slack user_id をキーに外部 OAuth トークンを保存 |
| `apps.user.connection.update` | Slack API | 接続状態（`connected` / `disconnected`）を Slack UI に反映 |
| `user_context` | Slack | 検索実行ユーザーの Slack user_id を search_function に渡す |
| `functions.completeError` | Slack API | 未認証ユーザーへの認証要求メッセージを検索画面に表示 |
| `functions.completeSuccess` | Slack API | 検索結果を Slack に返す |

---

### 3. 実装フェーズの詳細

#### フェーズ 1: 接続フロー（user_connection: connect）

**ファイル**: `docs/enterprise-search/connection-reporting.md` 行 29-33、`docs/reference/events/user_connection.md`

ユーザーが Slack 検索 UI の「Connect」ボタンをクリックしたときの流れ:

```
1. ユーザー → Slack: 「Connect」ボタンをクリック

2. Slack → アプリ: user_connection イベント (subtype: connect) を送信
   {
     "event": {
       "type": "user_connection",
       "subtype": "connect",
       "user": "U012A3BC4DE",          ← Slack user_id
       "trigger_id": "1293638028594...  ← モーダルを開くためのトークン（有効時間: 数秒）"
     }
   }

3. アプリ → Slack: views.open を呼び出してモーダルを表示
   - trigger_id を使ってモーダルを開く
   - モーダルに外部サービスへの OAuth 認可 URL を表示
   - URL には state パラメータに Slack user_id を埋め込む（またはサーバー側で nonce を生成）

4. ユーザー → 外部サービス: モーダルのリンクをクリック → OAuth フロー実行

5. 外部サービス → アプリ (OAuth callback エンドポイント): 認可コードを送信
   - callback URL の state から Slack user_id を取得

6. アプリ → 外部サービス: 認可コード → アクセストークンに交換

7. アプリ: トークンをデータストアに保存
   - キー: Slack user_id（例: "U012A3BC4DE"）
   - バリュー: { access_token, refresh_token, expires_at }

8. アプリ → Slack: apps.user.connection.update (user_id, status: "connected") 呼び出し

9. Slack → ユーザー: 検索 UI が「Connected」表示に更新
```

**nonce / state パラメータの役割**（`docs/authentication/binding-accounts-across-services.md` 行 19-21）:

> "the app generates a unique token (a nonce), stores it in a database alongside the Slack user ID, and passes it to the URL of a page behind authentication on the internal system."

セキュリティのため:
- アプリはランダムな nonce を生成し、DB に `{ nonce: ..., slack_user_id: "U012A3BC4DE" }` として保存
- OAuth 認可 URL に `state=nonce` を付与して外部サービスへリダイレクト
- callback で `state` から nonce を取り出し、DB から対応する Slack user_id を取得

---

#### フェーズ 2: 切断フロー（user_connection: disconnect）

**ファイル**: `docs/reference/events/user_connection.md`

ユーザーが「Disconnect」ボタンをクリックしたときの流れ:

```
1. ユーザー → Slack: 「Disconnect」ボタンをクリック

2. Slack → アプリ: user_connection イベント (subtype: disconnect) を送信
   {
     "event": {
       "type": "user_connection",
       "subtype": "disconnect",
       "enterprise_id": "E012A3BC4DE",
       "user": "U012A3BC4DE"            ← Slack user_id
     }
   }

3. アプリ: データストアからトークンを削除（または無効化）
   - オプション: 外部サービスの token revoke エンドポイントを呼ぶ

4. アプリ → Slack: apps.user.connection.update (user_id, status: "disconnected") 呼び出し

5. Slack → ユーザー: 検索 UI が「Connect」表示に戻る
```

---

#### フェーズ 3: 検索フロー（function_executed）

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md` 行 51-83、行 296-308

ユーザーが Slack で検索を実行したときの流れ:

```
1. ユーザー → Slack: 検索クエリを入力

2. Slack → アプリ: function_executed イベント
   {
     "event": {
       "type": "function_executed",
       "function": { "callback_id": "search_results_function" },
       "inputs": {
         "query": "検索キーワード",
         "user_context": { "id": "U012A3BC4DE", ... }  ← Slack user_id を含む
       },
       "function_execution_id": "Fx1234567O9L"
     }
   }

3. アプリ: user_context.id でデータストアからトークンを取得
   access_token = db.get("U012A3BC4DE")

   [トークンが見つからない場合]
   → アプリ → Slack: functions.completeError
     {
       "function_execution_id": "Fx...",
       "error": "Authentication Required: Please connect at https://your-app.example.com/connect"
     }
   → Slack が検索画面にエラーメッセージを表示

   [トークンが見つかった場合]
   → アプリ → 外部サービス: 外部 API 呼び出し
     Authorization: Bearer {access_token}

4. 外部サービス → アプリ: 検索結果

5. アプリ → Slack: functions.completeSuccess
   {
     "function_execution_id": "Fx...",
     "outputs": {
       "search_results": [
         {
           "external_ref": { "id": "doc123" },
           "title": "ドキュメントタイトル",
           "description": "説明文",
           "link": "https://external.example.com/doc/123",
           "date_updated": "2026-04-01"
         }
       ]
     }
   }

6. Slack → ユーザー: 検索結果を表示
```

**functions.completeError の認証エラーメッセージ**（`developing-apps-with-search-features.md` 行 303）:

> "The error message provided by your app will be displayed to the user on the search page. It can be any plain text value with links you think could be insightful to the user. For example: **Authentication Required: Please visit https://getauthhere.slack.dev to authenticate your account.**"

Slack の公式ドキュメントが認証エラーのメッセージ例を提示しており、このパターンが明示的にサポートされている。

---

### 4. App Manifest の必要な設定

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md` 行 44-46、0009番ログ

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
      "search_function_callback_id": "search_results_function"
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

**必要なスコープ**:
- `users:write`: `apps.user.connection.update` を呼ぶために必要

---

### 5. Bolt フレームワーク（Python）での実装スケルトン

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md` 行 314-330

```python
from slack_bolt import App
import secrets  # nonce 生成用

app = App(token=os.environ["SLACK_BOT_TOKEN"])

# ----- フェーズ 1: 接続フロー -----

@app.event("user_connection")
def handle_user_connection(event, client):
    subtype = event.get("subtype")
    user_id = event.get("user")

    if subtype == "connect":
        trigger_id = event.get("trigger_id")
        
        # nonce を生成し DB に保存（CSRF 対策）
        nonce = secrets.token_urlsafe(32)
        nonce_store.save(nonce, slack_user_id=user_id, expires_in=300)
        
        # OAuth 認可 URL を組み立て
        oauth_url = (
            "https://external-service.example.com/oauth/authorize"
            f"?client_id={CLIENT_ID}"
            f"&redirect_uri={CALLBACK_URL}"
            f"&response_type=code"
            f"&state={nonce}"
        )
        
        # モーダルを開いて認可 URL を表示
        client.views_open(
            trigger_id=trigger_id,
            view={
                "type": "modal",
                "title": {"type": "plain_text", "text": "外部サービスに接続"},
                "blocks": [
                    {
                        "type": "section",
                        "text": {
                            "type": "mrkdwn",
                            "text": f"<{oauth_url}|こちらをクリックして接続>"
                        }
                    }
                ]
            }
        )

    elif subtype == "disconnect":
        # トークンをデータストアから削除
        token_store.delete(user_id)
        
        # Slack UI に切断状態を通知
        client.apps_user_connection_update(
            user_id=user_id,
            status="disconnected"
        )


# ----- OAuth callback エンドポイント（例: Flask） -----

@flask_app.route("/oauth/callback")
def oauth_callback():
    code = request.args.get("code")
    nonce = request.args.get("state")
    
    # nonce から Slack user_id を取得
    slack_user_id = nonce_store.get(nonce)
    if not slack_user_id:
        return "Invalid or expired nonce", 400
    
    # 認可コード → アクセストークンに交換
    token_response = requests.post(
        "https://external-service.example.com/oauth/token",
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": CALLBACK_URL,
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
        }
    ).json()
    
    # トークンを自社 DB に保存
    token_store.save(
        user_id=slack_user_id,
        access_token=token_response["access_token"],
        refresh_token=token_response.get("refresh_token"),
        expires_at=int(time.time()) + token_response.get("expires_in", 3600)
    )
    
    # Slack UI に接続状態を通知
    app.client.apps_user_connection_update(
        user_id=slack_user_id,
        status="connected"
    )
    
    return "接続が完了しました。このウィンドウを閉じてください。"


# ----- フェーズ 3: 検索フロー -----

@app.event("function_executed")
def handle_search(event, client):
    if event.get("function", {}).get("callback_id") != "search_results_function":
        return
    
    inputs = event.get("inputs", {})
    query = inputs.get("query")
    user_id = inputs.get("user_context", {}).get("id")
    execution_id = event.get("function_execution_id")
    
    # トークンを取得
    token_data = token_store.get(user_id)
    
    if not token_data:
        # 未接続 → 認証要求エラー
        client.functions_completeError(
            function_execution_id=execution_id,
            error=(
                "Authentication Required: "
                "Please connect your account at https://your-app.example.com/connect"
            )
        )
        return
    
    # トークン有効期限の確認
    access_token = token_data["access_token"]
    if token_data["expires_at"] < time.time() + 60:
        # 期限切れまたはそれに近い → リフレッシュ
        try:
            access_token = refresh_token(user_id, token_data["refresh_token"])
        except Exception:
            client.apps_user_connection_update(user_id=user_id, status="disconnected")
            client.functions_completeError(
                function_execution_id=execution_id,
                error="Session expired. Please reconnect at https://your-app.example.com/connect"
            )
            return
    
    # 外部 API 呼び出し
    results = external_service.search(query=query, token=access_token)
    
    # 検索結果を返す（10秒以内に完了必須）
    client.functions_completeSuccess(
        function_execution_id=execution_id,
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

### 6. Deno SDK External Auth との比較（なぜ使えないのか）

**ファイル**: 0009番ログ

| 観点 | Enterprise Search + Connection Reporting | Deno SDK External Auth |
|---|---|---|
| トークン管理者 | アプリ（自社 DB） | Slack |
| OAuth フロー | アプリが実装 | Slack が提供 |
| トークン取得方法 | DB からの読み取り | `apps.auth.external.get` API |
| トークンリフレッシュ | アプリが実装 | Slack が自動実行 |
| Enterprise Search で使用可能か | **YES** | **NO**（Link Trigger 専用） |

Deno SDK の `credential_source: "END_USER"` / `oauth2` 型は **Link Trigger からのみ動作**する。Enterprise Search の search_function は Slack が直接呼び出す仕組みであり、ワークフローのステップではないため適用できない（0009番確認済み）。

---

### 7. 10秒制約への対応（トークンリフレッシュ戦略）

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md` 行 307

> "Your app must complete the function execution within 10 seconds."

search_function は 10 秒以内に完了しなければならないため、検索時のリアクティブリフレッシュは時間的リスクがある。

**推奨: プロアクティブリフレッシュ（バックグラウンドジョブ）**

```
バックグラウンドジョブ（1分ごとなど定期実行）:
  - expires_at が 現在時刻 + 5分 以内のトークンを検索
  - 対象ユーザーのリフレッシュトークンフロー実行
  - DB の access_token・expires_at を更新

search_function:
  - DB からトークンを取得（すでにリフレッシュ済みで安全）
  - 外部 API 呼び出し
  - 401 が返った場合のみリアクティブリフレッシュ（フォールバック）
```

---

## 判断・意思決定

### 0016番の本質的な問いへの答え

「Enterprise Search において外部サービスに認証を行う場合どういう実装をしなければならないか」

**答え**: アプリが自前の OAuth フロー + トークンストアを実装する必要がある。Slack が提供するのは以下のみ:
1. `user_connection` イベント（ユーザーが Connect/Disconnect ボタンを押したことの通知）
2. `apps.user.connection.update` API（UI の状態更新）
3. `functions.completeError`（認証要求メッセージの表示）

OAuth のコアロジック（認可 URL 生成・callback 処理・トークン交換・DB 保存・リフレッシュ）はすべてアプリの責任。

### 0015番の「UI scaffolding」理解との接続

0015番で確認した「Connection Reporting = UI scaffolding」は正確。Connection Reporting は：
- ユーザーが認証フローを開始するための「入口（Connect ボタン）」を提供する
- ユーザーが認証状態を確認するための「表示（Connected/Disconnected）」を提供する
- 認証フローのキックオフイベント（`user_connection: connect`）を提供する

しかし認証フロー本体（OAuth）はアプリが実装する。Connection Reporting はその「前後の UI と通知」の部分を担う。

---

## 問題・疑問点

1. **views.open の trigger_id 有効時間**: `user_connection` イベントを受け取ってから `views.open` を呼ぶまでに許容される時間が正確に何秒かは未確認（通常は 3 秒と言われるが、ドキュメントに明記なし）。

2. **OAuth 認可ページからのモーダル閉じ方**: ユーザーが外部サービスで OAuth を完了したあと、Slack のモーダルを自動的に閉じる仕組みはドキュメントに記載されていない。実装上は callback ページでウィンドウを閉じる JavaScript を使うか、OAuth 完了後に DM やエフェメラルメッセージを送るパターンが考えられる。

3. **token_store の実装詳細**: トークンの暗号化方法・KMS 利用・セキュリティ要件については Slack のドキュメントに記載がなく、開発者に委ねられている。

4. **apps.user.connection.update の Bot token 対応**: ドキュメント上は User token（`users:write` スコープ）と記載されているが、Bot token でも動作すると 0014番で推定している。

---

## まとめ

### Enterprise Search 外部認証の実装 = Connection Reporting + 自前 OAuth

| フェーズ | トリガー | アプリの実装内容 | Slack API |
|---|---|---|---|
| **接続フロー** | ユーザーが「Connect」クリック | `user_connection: connect` 受信 → nonce 生成 → モーダル表示 | `views.open` |
| | ユーザーが外部サービスで OAuth 完了 | callback 処理 → トークン交換 → DB 保存 | `apps.user.connection.update(connected)` |
| **切断フロー** | ユーザーが「Disconnect」クリック | `user_connection: disconnect` 受信 → DB からトークン削除 | `apps.user.connection.update(disconnected)` |
| **検索フロー** | ユーザーが検索クエリを入力 | `function_executed` 受信 → user_context.id で DB からトークン取得 → 外部 API 呼び出し（10秒以内） | `functions.completeSuccess` / `functions.completeError` |

**Slack が提供するもの**: UI（Connect ボタン/Connected 表示）・イベント通知・検索関数の呼び出し

**アプリが実装するもの**: OAuth 認可 URL の生成・callback エンドポイント・トークン交換・トークン DB・トークンリフレッシュ

**Deno SDK External Auth は Enterprise Search では使用不可**（Link Trigger 専用）。
