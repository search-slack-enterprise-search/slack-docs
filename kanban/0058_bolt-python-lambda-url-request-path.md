# Bolt Python + Lambda URL 関数のリクエストパス

## 知りたいこと

0057の更問い。パスの指定方法がないということは、Boltフレームワークで実装した場合のパスはどこで知ることができるのか？

## 目的

Bolt Python + Lambda + Lambda URL Functions で動かそうと思っている。manifest.json に書く URL として、Event Subscription の URL としてルートパスで良いのかパスを指定するのならどのパスになるのか、他の機能ならどのパスになるのか、まとまったドキュメントがあると思うからソレも知りたい。

## 調査サマリー

**結論: Lambda Function URL のルートパス（`/`）を全機能の Request URL に設定すれば良い。**

### Bolt Python はパスでルーティングしない

`BoltRequest` のパラメーターに `path`（URL パス）が存在しない。Bolt 内部のルーティングはリクエストボディの `type` フィールドで行う。アダプターの `handle()` メソッドも `method == "POST"` のみチェックし、パスを見ない。

### Lambda Function URL でのパス設定

Lambda Function URL（`https://xxxx.lambda-url.us-east-1.on.aws/`）を manifest.json の全 `request_url` フィールドに同一 URL として設定できる:

- **ルートパス（`/`）でOK**
- パス付き（`/slack/events`）も可能（Lambda はパスに関係なく同一関数に転送するため）
- 全機能に同一 URL を使用可能

### 機能別 manifest.json の Request URL フィールド

| 機能 | manifest.json フィールド |
|------|------------------------|
| Events API | `settings.event_subscriptions.request_url` |
| Block Actions / Shortcuts / Modals | `settings.interactivity.request_url` |
| External Select Menu | `settings.interactivity.message_menu_options_url` |
| Slash Commands（コマンドごと） | `features.slash_commands[].url` |

### 使用アダプター

Lambda Function URL は API Gateway HTTP API v2.0 と同一イベント形式のため、`slack_bolt.adapter.aws_lambda` の `SlackRequestHandler` がそのまま使用可能:

```python
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(process_before_response=True)

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

### まとまったドキュメントについて

ドキュメントスナップショット内に Lambda Function URL に特化したまとまったドキュメントはなかった。パス情報は以下に分散:
- `docs/tools/bolt-python/concepts/adapters.md` — アダプター全般
- `docs/tools/bolt-python/concepts/lazy-listeners.md` — Lambda 用アダプター  
- `docs/tools/bolt-python/concepts/custom-adapters.md` — BoltRequest の仕様
- `docs/reference/app-manifest.md` — manifest.json の request_url フィールド

Lambda Function URL 専用アダプター（`slack_bolt.adapter.aws_lambda_url`）がリポジトリに存在する可能性あり（docs snapshot 未収録のため未確認）。

## 完了サマリー

- 調査完了日: 2026-04-24
- ログ: `logs/0058_bolt-python-lambda-url-request-path.md`
- **ルートパス（`/`）をすべての Request URL に使用可能**。パスは Bolt が無視し、Lambda Function URL はパスに関係なく同一関数へ転送する。
