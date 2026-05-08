# Bolt実装での request_url はイベントサブスクリプションと同じURLか

## 知りたいこと

0076の更問い。request_urlはBolt実装の場合、event subscriptionと同じもので良いのか。

## 目的

urlとして指定すべき物を知りたい。

## 調査サマリー

### 結論：`interactivity.request_url` = `event_subscriptions.request_url` と同じ URL でよい

**Bolt for Python を使う場合、`settings.interactivity.request_url` に `settings.event_subscriptions.request_url` と全く同じ URL を設定する。**

Lambda + Bolt の場合の具体的な設定値:

```json
"settings": {
    "event_subscriptions": {
        "request_url": "https://YOUR_LAMBDA_URL/slack/events"
    },
    "interactivity": {
        "is_enabled": true,
        "request_url": "https://YOUR_LAMBDA_URL/slack/events"  // ← 同じURL
    }
}
```

### 技術的根拠

| 根拠 | 出典 |
|------|------|
| Events API は「アプリに1つの Request URL しかない」 | `docs/apis/events-api/using-http-request-urls.md` |
| Slack 公式 MCP サンプルが両フィールドに同じ URL を使用 | `docs/ai/slack-mcp-server/developing.md` |
| Bolt アダプターは全 POST を `app.dispatch()` に委譲し、`type` フィールドで内部ルーティング | `docs/tools/bolt-python/reference/adapter/aws_lambda.md` |
| モーダル送信はアクションと「同一エンドポイント」に届く | `docs/interactivity/adding-interactive-modals-to-home-tab.md` |

### Bolt のルーティング仕組み

Slack は全機能のリクエストを同一 URL に POST する。Bolt がペイロードの `type` フィールドで振り分ける:

| 送信元 | Bolt ハンドラー |
|--------|----------------|
| Events API（`function_executed` 等） | `@app.event()` |
| ボタン等の Block Actions | `@app.action()` |
| モーダル送信 | `@app.view()` |
| ショートカット | `@app.shortcut()` |

### マニフェストリファレンスの異なる URL について

`docs/reference/app-manifest.md` のサンプルでは `event_subscriptions.request_url` と `interactivity.request_url` に異なる URL が書かれているが、これは各フィールドが独立した設定であることを示す**説明目的のデモ**。同じ URL を使うことは明示的にサポートされている（0059 で確認済み）。

詳細ログ: `logs/0077_bolt-request-url-same-as-event-subscription.md`

## 完了サマリー

`settings.interactivity.request_url` は `settings.event_subscriptions.request_url` と同じ URL（Bolt の `/slack/events` エンドポイント）を指定してよいことを確認した。Bolt は単一エンドポイントで全 Slack リクエストを受け取り、ペイロードの `type` フィールドで各ハンドラー（`@app.action()`・`@app.event()` 等）に内部ルーティングする。Slack 公式の MCP Server サンプルマニフェストが両フィールドに同一 URL を設定していることが最も直接的な根拠。
