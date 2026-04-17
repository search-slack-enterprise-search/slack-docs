# Enterprise SearchのAWS Lambda動作可否 - 調査ログ

## 調査概要

- **調査日**: 2026-04-17
- **タスクファイル**: kanban/0039_enterprise-search-on-aws-lambda.md
- **調査テーマ**: Enterprise Search の実装において AWS Lambda を動作環境として使えるか

---

## 調査したファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md` — Enterprise Search 実装ガイド（中心的資料）
- `docs/tools/bolt-python/concepts/adapters.md` — Bolt for Python アダプタ（SlackRequestHandler）
- `docs/tools/bolt-python/concepts/lazy-listeners.md` — FaaS 対応 Lazy Listener
- `docs/tools/bolt-python/concepts/acknowledge.md` — ack() の詳細
- `docs/tools/bolt-python/concepts/custom-steps.md` — complete/fail ヘルパー
- `docs/tools/bolt-python/concepts/custom-steps-dynamic-options.md` — auto_acknowledge フラグ
- `docs/enterprise-search/enterprise-search-access-control.md` — アクセス制御
- `docs/enterprise-search/connection-reporting.md` — 接続状態管理
- `docs/tools/bolt-python/concepts/async.md` — 非同期処理
- 既存ログ: `logs/0031_lambda-bolt-custom-agent.md` — Lambda + Bolt カスタムエージェント（参考）
- 既存ログ: `logs/0036_enterprise-search-detailed-flow.md` — Enterprise Search 詳細フロー（参考）

---

## 調査結果

### 1. 結論: AWS Lambda で Enterprise Search は動かせる（YES）

Enterprise Search は Event Subscriptions（HTTP エンドポイント）を使用する。
HTTP エンドポイントは API Gateway または Lambda Function URL 経由で Lambda に向けることができるため、**AWS Lambda を動作環境として使用することは可能**。

---

### 2. Enterprise Search のイベント受信の仕組み

`docs/enterprise-search/developing-apps-with-search-features.md` より：

App Manifest の `event_subscriptions` に `function_executed` を登録することで、Slack がアプリの HTTP エンドポイントへイベントを POST する。

```json
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
```

- `app_type: "remote"` および `function_runtime: "remote"` が必須
- `event_subscriptions` の Request URL に Lambda の API Gateway URL や Function URL を指定する
- この URL への Slack からの POST リクエストを Lambda で処理すれば良い

---

### 3. Enterprise Search イベント処理の制約（カスタムエージェントとの違い）

`docs/enterprise-search/developing-apps-with-search-features.md`「Handling events」セクションより：

> To ensure fast search results delivery, apps must handle `function_executed` events synchronously. This means the app must complete the function's execution and provide output parameters before acknowledging the event.

**処理フロー（必須手順）:**

1. アプリが `function_executed` イベントリクエストを受け取る
2. アプリが `functions.completeSuccess` または `functions.completeError` を呼び出して、関数実行の完了を Slack に通知する
3. アプリがイベントリクエストに対して ACK（HTTP 200 応答）を返す
4. **制限時間: 関数実行完了まで 10 秒以内**

**カスタムエージェントとの重要な違い:**

| 項目 | カスタムエージェント（Assistant） | Enterprise Search |
|------|----------------------------------|-------------------|
| ACK タイムアウト | 3秒以内 | 10秒以内 |
| 処理方式 | 非同期（Lazy listener で長時間処理） | 同期（10秒以内に complete() まで完了） |
| Lazy listener の必要性 | 必要（3秒超の処理に対応） | **不要**（10秒で同期完了） |
| `process_before_response` | 必須（True） | 関係する（後述） |

---

### 4. Bolt for Python の Lambda アダプタ

`docs/tools/bolt-python/concepts/adapters.md` より：

Bolt for Python は `SlackRequestHandler` を使って AWS Lambda と統合する。

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    token=os.environ.get("SLACK_BOT_TOKEN"),
    process_before_response=True  # FaaS 環境では必須
)

def lambda_handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

`process_before_response=True` の役割:
- 通常の Bolt: `ack()` 後すぐに HTTP レスポンスを送信し、後続処理をバックグラウンドで実行
- `process_before_response=True`: リスナー関数が完全に完了するまで HTTP レスポンスを送らない
- FaaS 環境（Lambda）では HTTP レスポンス後に処理を継続できないため必須

---

### 5. Enterprise Search + Bolt for Python の実装パターン

`docs/enterprise-search/developing-apps-with-search-features.md`「Bolt for Python」セクションより：

```python
# Bolt for Python で Enterprise Search を実装する場合の設定
@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack, complete, fail, inputs):
    try:
        query = inputs.get("query", "")
        filters = inputs.get("filters", {})
        
        # 外部データソースを検索（10秒以内に完了させること）
        results = search_external_data(query, filters)
        
        # 検索結果を Slack の形式に変換して complete() で通知
        complete(outputs={
            "search_results": [
                {
                    "external_ref": {"id": r["id"], "type": r["type"]},
                    "title": r["title"],
                    "description": r["summary"],
                    "link": r["url"],
                    "date_updated": r["updated_at"],
                    "content": r.get("full_content")  # optional
                }
                for r in results
            ]
        })
    except Exception as e:
        fail(error=str(e))
    finally:
        ack()  # complete()/fail() の後に ack()
```

**パラメータの説明:**
- `auto_acknowledge=False`: ack() の自動呼び出しを無効化し、手動で制御する
- `ack_timeout=10`: デフォルト 3 秒のタイムアウトを Enterprise Search の上限 10 秒に延長
- `complete(outputs=...)`: `functions.completeSuccess` API を呼び出す Bolt ヘルパー
- `fail(error=...)`: `functions.completeError` API を呼び出す Bolt ヘルパー

**処理順序の注意:** `ack()` は `complete()` または `fail()` の**後**に呼び出す。先に呼ぶと Slack へのレスポンスが先行してしまう。

---

### 6. Lazy Listener との関係

Enterprise Search は **10 秒以内に同期的に完了**させるため、Lazy Listener は**不要**（使わない）。

Lazy Listener が必要になるのは:
- 3 秒を超える処理が必要な場合（カスタムエージェントの `user_message` など）
- Enterprise Search では `ack_timeout=10` で 10 秒まで延長しているため、Lazy Listener なしで対応できる

ただし、Lazy Listener を使う他のハンドラ（例: カスタムエージェントを同一アプリに統合する場合）では、引き続き IAM 権限 (`lambda:InvokeFunction`, `lambda:GetFunction`) が必要になる。

---

### 7. Lambda の推奨設定

**Lambda 関数のタイムアウト設定:**
- Enterprise Search: 10 秒以内 + ACK のオーバーヘッド → **15〜30 秒を推奨**
- カスタムエージェントも同一 Lambda に載せる場合: より長い設定が必要

**serverless.yml / SAM 設定例:**

```yaml
functions:
  slack-enterprise-search:
    handler: app.lambda_handler
    timeout: 30          # Enterprise Search の 10 秒 + 余裕
    memorySize: 256
    environment:
      SLACK_BOT_TOKEN: ${ssm:/slack/bot-token}
      SLACK_SIGNING_SECRET: ${ssm:/slack/signing-secret}
    events:
      - http:
          path: slack/events
          method: post
```

**IAM ロール:**
- Enterprise Search のみなら Lazy Listener 不要のため、特別な Lambda 権限は不要
- 外部データソースへのアクセスに必要な権限（DynamoDB, S3, Secrets Manager など）は別途付与

---

### 8. Bolt for Node.js の場合

`docs/enterprise-search/developing-apps-with-search-features.md`「Bolt for Node」セクションより：

Node.js でも同様に Lambda で動作させることが可能。

```typescript
// Bolt for Node の設定
@app.function("search_function", { autoAcknowledge: false })
async function handleSearch({ ack, complete, fail, inputs }) {
    try {
        const results = await searchExternalData(inputs.query, inputs.filters);
        await complete({ outputs: { search_results: results } });
    } catch (e) {
        await fail({ error: String(e) });
    } finally {
        await ack();
    }
}
```

Node.js 版では `ack_timeout` パラメータはなく、Socket Mode での利用時か、デフォルト 3 秒以内に処理が完了しない場合に `auto_acknowledge=False` が特に有用。

---

### 9. Event Subscriptions の URL 設定

Slack App の設定画面（Event Subscriptions）で、Request URL に Lambda のエンドポイントを設定する:

- **API Gateway**: `https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/slack/events`
- **Lambda Function URL**: `https://{function-url}.lambda-url.{region}.on.aws/slack/events`

Slack から URL 検証リクエスト（`url_verification` チャレンジ）が来るため、Bolt の `SlackRequestHandler` がこれを自動的に処理する（特別な実装不要）。

---

### 10. 全体アーキテクチャ

```
[Slack]
  │  function_executed イベント (HTTP POST)
  ↓
[API Gateway または Lambda Function URL]
  │
  ↓
[AWS Lambda]
  ├── SlackRequestHandler が受信・署名検証
  ├── @app.function("search_function", auto_acknowledge=False, ack_timeout=10)
  │     ├── 外部データソース検索（10秒以内）
  │     ├── complete(outputs={"search_results": [...]})
  │     └── ack()
  └── HTTP 200 を Slack に返す

[Slack]
  ← 検索結果を受け取り、UI に表示
```

---

## 調査アプローチ

1. `docs/enterprise-search/developing-apps-with-search-features.md` で Enterprise Search の HTTP イベント受信方式を確認
2. 既存ログ（0031, 0036）から Lambda + Bolt の基本パターンと Enterprise Search 詳細フローを参照
3. Bolt for Python の adapters, lazy-listeners, custom-steps ドキュメントで Lambda 固有の設定を確認
4. カスタムエージェント（3秒ACK + Lazy listener）と Enterprise Search（10秒同期）の差異を整理

---

## 問題・疑問点

- `process_before_response=True` と `auto_acknowledge=False` の組み合わせ時の正確な挙動: `complete()` の後 `ack()` が呼ばれ、そこで初めて HTTP 200 が返るという理解で良いかは要確認
- カスタムエージェントと Enterprise Search を同一 Lambda アプリに統合する場合: Lazy Listener を混在させると複雑になるため、別 Lambda 関数に分けるか同一にするかはアーキテクチャの選択
- Node.js Bolt + Lambda でのアダプタ（`@slack/bolt` の `AwsLambdaReceiver`）の詳細は本調査では未確認
