# 複数 Slack 機能で同一 URL を使用可能か確認

## 知りたいこと

0058についての更問い。つまり、Event Subscriptionもスラッシュコマンドもmanifest.jsonで同じURLを書いて良いということですか？

## 目的

複数の機能で同一のURLでいいのかを確認したい

## 調査サマリー

**結論: YES。Event Subscription もスラッシュコマンドも manifest.json で同一 URL を設定して良い。**

### ドキュメントの直接的な根拠

| 根拠 | 出典 |
|------|------|
| Events API は「アプリに1つの Request URL しかない」 | `docs/apis/events-api/using-http-request-urls.md` |
| スラッシュコマンドは「単一 URL で複数コマンドを処理できる」 | `docs/interactivity/implementing-slash-commands.md` |
| モーダル送信はアクションと「同一エンドポイント」に届く | `docs/interactivity/adding-interactive-modals-to-home-tab.md` |

Events API ドキュメント（`using-http-request-urls.md`）の明示的な記述:
> "Since your application will have only one Events API request URL, you'll need to do any additional dispatch or routing server-side after receiving event data."

スラッシュコマンドドキュメント（`implementing-slash-commands.md`）の明示的な記述:
> "`command` — This value can be useful if you want to use a **single Request URL** to service **multiple slash commands**"

### ルーティングの仕組み

Slack は全リクエストを同一 URL に POST する。Bolt は URL パスではなく**リクエストボディの `type` フィールド**（または `command` フィールド）で種別を判別してルーティングする。

| 送信元 | 識別フィールド | Bolt ハンドラー |
|--------|--------------|----------------|
| Events API | `event.type`（例: `app_mention`） | `app.event()` |
| Block Actions | `type: "block_actions"` | `app.action()` |
| Shortcuts | `type: "shortcut"` | `app.shortcut()` |
| Modal Submit | `type: "view_submission"` | `app.view()` |
| Slash Commands | `command: "/mycommand"` | `app.command()` |

### Lambda Function URL での manifest.json 設定例

```json
{
    "settings": {
        "event_subscriptions": {
            "request_url": "https://xxxx.lambda-url.us-east-1.on.aws/"
        },
        "interactivity": {
            "is_enabled": true,
            "request_url": "https://xxxx.lambda-url.us-east-1.on.aws/"
        }
    },
    "features": {
        "slash_commands": [
            {
                "command": "/mycommand",
                "url": "https://xxxx.lambda-url.us-east-1.on.aws/"
            }
        ]
    }
}
```

## 完了サマリー

- 調査完了日: 2026-04-24
- ログ: `logs/0059_single-url-for-multiple-slack-features.md`
- **同一 URL を全フィールドに使用可能**。Slack ドキュメントが明示的に確認している。
