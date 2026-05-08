# Bolt実装での request_url はイベントサブスクリプションと同じURLか — 調査ログ

## 調査情報

- タスクファイル: `kanban/0077_bolt-request-url-same-as-event-subscription.md`
- 調査日: 2026-05-08
- 前提タスク: 0076（Work Objects Task アクション実装）、0059（複数 Slack 機能で同一 URL を使用可能か）、0055（Enterprise Search manifest.json サンプル）

---

## 調査ファイル一覧

- `docs/apis/events-api/using-http-request-urls.md`
- `docs/interactivity/handling-user-interaction.md`
- `docs/reference/app-manifest.md`
- `docs/tools/bolt-python/concepts/adapters.md`
- `docs/tools/bolt-python/concepts/actions.md`
- `docs/tools/bolt-python/reference/adapter/aws_lambda.md`
- `docs/ai/slack-mcp-server/developing.md`
- `logs/0059_single-url-for-multiple-slack-features.md`（既存ログ）
- `logs/0055_enterprise-search-manifest-sample.md`（既存ログ）
- `logs/0054_enterprise-search-interactivity.md`（既存ログ）
- `logs/0076_work-objects-task-action-implementation.md`（既存ログ）

---

## 調査アプローチ

1. 0076・0059・0055・0054 の既存ログを読み込み、これまでの調査結果を確認
2. `docs/apis/events-api/using-http-request-urls.md` で Events API の Request URL の性質を確認
3. `docs/ai/slack-mcp-server/developing.md` で Bolt + HTTP モードのマニフェストサンプルを確認
4. `docs/tools/bolt-python/concepts/adapters.md` および `docs/tools/bolt-python/reference/adapter/aws_lambda.md` で Bolt のエンドポイント設計を確認
5. `docs/reference/app-manifest.md` で各 URL フィールドの仕様を確認

---

## 調査結果

### 1. 結論：YES — `interactivity.request_url` = `event_subscriptions.request_url` と同じ URL

**`settings.interactivity.request_url` には `settings.event_subscriptions.request_url` と全く同じ URL を設定してよい。**

Bolt for Python（および Bolt for JavaScript）は、単一の HTTP エンドポイントで Events API と Interactivity の両方を受け付ける。具体的には `https://YOUR_LAMBDA_URL/slack/events` を両フィールドに設定する。

---

### 2. 根拠 1：Events API のドキュメント

**ファイル**: `docs/apis/events-api/using-http-request-urls.md`（line 9〜11）

> "In the Events API, your Events API request URL is the target location where all of the events your application is subscribed to will be delivered, **regardless of the workspace or event type**."
>
> "Since your application will have **only one Events API request URL**, you'll need to do any additional dispatch or routing server-side after receiving event data."

**解釈**: Events API の Request URL はアプリ全体で1つしか持てない。すべてのイベントタイプがこの1つの URL に届く。サーバー側（=Bolt）が `event.type` フィールドで振り分ける。

---

### 3. 根拠 2：Slack MCP Server の公式マニフェストサンプル

**ファイル**: `docs/ai/slack-mcp-server/developing.md`（line 20 — manifest.json）

```json
"settings": {
    "event_subscriptions": {
        "request_url": "https://example.ngrok-free.app/slack/events",
        "bot_events": [
            "assistant_thread_context_changed",
            "assistant_thread_started",
            "message.im"
        ]
    },
    "interactivity": {
        "is_enabled": true,
        "request_url": "https://example.ngrok-free.app/slack/events"
    },
    ...
}
```

**解釈**: Slack の公式サンプルアプリ（Bolt for JavaScript 使用）が `event_subscriptions.request_url` と `interactivity.request_url` に**全く同じ URL**（`/slack/events`）を設定していることを明示している。

---

### 4. 根拠 3：Bolt for Python の単一エンドポイント設計

**ファイル**: `docs/tools/bolt-python/concepts/adapters.md`

```python
# Flask の例
from slack_bolt.adapter.flask import SlackRequestHandler
handler = SlackRequestHandler(app)

@flask_app.route("/slack/events", methods=["POST"])
def slack_events():
    return handler.handle(request)  # 全 POST リクエストをここで処理
```

**解釈**: Bolt は `/slack/events` という1つのルートで全ての Slack POST リクエストを処理する。ルーティングはパスではなくリクエストボディの `type` フィールドで行う。

---

### 5. 根拠 4：Bolt for Python の AWS Lambda アダプター

**ファイル**: `docs/tools/bolt-python/reference/adapter/aws_lambda.md`

`SlackRequestHandler.handle()` の実装:

```python
def handle(self, event, context):
    ...
    if method == "GET":
        # OAuth フロー（インストール・コールバック）
        ...
    elif method == "POST":
        bolt_req = to_bolt_request(event)
        bolt_resp = self.app.dispatch(bolt_req)  # 全 POST を dispatch に委譲
        return to_aws_response(bolt_resp)
```

**解釈**: `self.app.dispatch(bolt_req)` が全 POST リクエストを受け取り、ペイロードの `type` フィールドに基づいて内部ルーティングする:

| 送信元 | ペイロードの識別フィールド | Bolt ハンドラー |
|--------|--------------------------|----------------|
| Events API | `event.type`（例: `function_executed`） | `@app.event()` |
| Block Actions（ボタン等） | `type: "block_actions"` | `@app.action()` |
| ショートカット | `type: "shortcut"` / `"message_action"` | `@app.shortcut()` |
| モーダル送信 | `type: "view_submission"` | `@app.view()` |

---

### 6. 根拠 5：マニフェストリファレンスのサンプルの読み方

**ファイル**: `docs/reference/app-manifest.md`（JSON サンプル）

マニフェストリファレンスの例では:
```json
"event_subscriptions": {
    "request_url": "https://example.com/slack/the_Events_API_request_URL"
},
"interactivity": {
    "is_enabled": true,
    "request_url": "https://example.com/slack/message_action"  // ← 異なるURL
}
```

**異なる URL が書かれている理由**: 各フィールドが別々の設定であることを説明するためのデモ用表記。これは「別の URL にしなければならない」ことを意味しない。0059 の調査（`docs/interactivity/adding-interactive-modals-to-home-tab.md` 引用）で確認済み:

> "When the form in the modal is submitted, a payload is sent to the same endpoint of the action."

---

### 7. 0059 の既存調査で確認済みの事実

**ファイル**: `logs/0059_single-url-for-multiple-slack-features.md`（line 119-145）

0059 の結論（ドキュメント直接引用に基づく）:

| 根拠 | 出典 |
|------|------|
| Events API は「アプリに1つの Request URL しかない」 | `docs/apis/events-api/using-http-request-urls.md` |
| スラッシュコマンドは「単一 URL で複数コマンドを処理できる」 | `docs/interactivity/implementing-slash-commands.md` |
| モーダル送信はアクションと「同一エンドポイント」に届く | `docs/interactivity/adding-interactive-modals-to-home-tab.md` |

**Bolt のルーティング表**（0059 より）:

| 送信元 | 識別フィールド | Bolt ハンドラー |
|--------|--------------|----------------|
| Events API | `event.type` | `app.event()` |
| Block Actions | `type: "block_actions"` | `app.action()` |
| Shortcuts | `type: "shortcut"` | `app.shortcut()` |
| Modal Submit | `type: "view_submission"` | `app.view()` |
| Slash Commands | `command: "/mycommand"` | `app.command()` |

---

### 8. Interactivity の Request URL の役割

**ファイル**: `docs/interactivity/handling-user-interaction.md`（line 40-43）

> "**Request URL**: the URL we'll send the request payload to when **interactive components** or **shortcuts** are used."
>
> "This **Request URL** is also used by **modals** for `view_submission` event payloads."

**解釈**: `interactivity.request_url` は:
- ボタン等の Block Kit interactive component → `block_actions`
- ショートカット → `shortcut` / `message_action`
- モーダル送信 → `view_submission`
- モーダルキャンセル → `view_closed`

これらすべてが同じ URL に届く。

---

## 実際の設定値

Lambda + Bolt for Python の場合の manifest.json 設定:

```json
"settings": {
    "event_subscriptions": {
        "request_url": "https://YOUR_LAMBDA_URL/slack/events",
        "bot_events": [
            "function_executed",
            "entity_details_requested"
        ]
    },
    "interactivity": {
        "is_enabled": true,
        "request_url": "https://YOUR_LAMBDA_URL/slack/events"
    }
}
```

**注意**: Bolt Python のデフォルトのパスは `/slack/events`。Lambda Function URL だけの場合、パス無し（`https://YOUR_LAMBDA_URL/`）でも動作する（0058・0057 の調査参照）が、慣例として `/slack/events` を使うことが多い。

---

## 問題・疑問点

- 0058 の調査で「Lambda Function URL は `/slack/events` パスなしでも受け付ける」ことが確認されている。したがって、`https://YOUR_LAMBDA_URL/` だけ（パスなし）でも両フィールドに設定可能。ただしパス付き（`/slack/events`）の方が慣例的。
- `settings.interactivity.message_menu_options_url` は External Select Menu のオプション取得用で、通常は別タイミングで呼ばれるが、同一 URL を使うことも可能。
