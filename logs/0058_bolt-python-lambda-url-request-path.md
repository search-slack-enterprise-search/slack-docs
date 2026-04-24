# Bolt Python + Lambda URL 関数のリクエストパス — 調査ログ

## 調査概要

- **タスク番号**: 0058
- **調査日**: 2026-04-24
- **知りたいこと**: Bolt Python + Lambda URL Functions で動かす際の Request URL パス。manifest.json の Event Subscription などに指定するパスはルートで良いのか、特定のパスが必要なのか。他機能のパスも知りたい。
- **参照タスク**: 0057（Bolt Lambda パス設定）

---

## 調査アプローチ

以下の順序で調査した:
1. `aws_lambda_url` / `lambda_url` キーワードでドキュメント全体を検索 → 記述なし
2. Bolt Python の全アダプタードキュメントを確認
3. `BoltRequest` のパラメーター確認（カスタムアダプターのドキュメント）
4. app manifest のリファレンスで `request_url` の構造を確認
5. Interactivity の Request URL 設定ドキュメントを確認

---

## 調査ファイル一覧

- `docs/tools/bolt-python/concepts/adapters.md`
- `docs/tools/bolt-python/concepts/custom-adapters.md`
- `docs/tools/bolt-python/concepts/lazy-listeners.md`
- `docs/tools/bolt-python/concepts/async.md`
- `docs/tools/bolt-python/getting-started.md`
- `docs/reference/app-manifest.md`
- `docs/interactivity/handling-user-interaction.md`
- `docs/app-management/hosting-slack-apps.md`

---

## 調査結果

### 1. Lambda Function URL 専用アダプターは存在しない

`aws_lambda_url` / `lambda_url_functions` などのキーワードで検索した結果、**ドキュメントに Lambda Function URL 専用アダプターの記述はなかった**。

ドキュメントが参照している AWS Lambda 対応アダプターは `slack_bolt.adapter.aws_lambda` のみ:

```python
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

このアダプターは API Gateway Proxy イベント形式を想定して作られているが、**Lambda Function URL は API Gateway HTTP API v2.0 と同一のイベントペイロード形式を使用する**ため、同じ `SlackRequestHandler` が動作する。

### 2. Bolt Python は URL パスでルーティングしない

**`BoltRequest` のパラメーター**（`docs/tools/bolt-python/concepts/custom-adapters.md`）:

| パラメーター | 説明 | 必須 |
|-------------|------|------|
| `body: str` | リクエストボディ（生文字列） | **Yes** |
| `query: any` | クエリストリング | No |
| `headers: Dict` | リクエストヘッダー | No |
| `context: BoltContext` | リクエストのコンテキスト | No |

**`path`（URL パス）はパラメーターに存在しない**。

カスタムアダプターの `handle()` 実装（同ファイルより）:

```python
def handle(self, req: Request) -> Response:
    # この例では OAuth に関する部分は扱いません
    if req.method == "POST":
        # Bolt へのリクエストをディスパッチし、処理とルーティングを行います
        bolt_resp: BoltResponse = self.app.dispatch(to_bolt_request(req))
        return to_flask_response(bolt_resp)
    return make_response("Not Found", 404)
```

`method == "POST"` のみチェック。**パスのチェックなし**。

Bolt 内部のルーティングは `app.dispatch()` が担い、**リクエストボディの `type` フィールド**（`block_actions`、`view_submission`、`shortcut` 等）や `event.type` によって振り分ける。

### 3. Web フレームワーク（Flask・Sanic）でのパスは「フレームワーク側の設定」

Flask アダプターのドキュメント（`docs/tools/bolt-python/concepts/adapters.md`）:

```python
# Register routes to Flask app
@flask_app.route("/slack/events", methods=["POST"])  # ← Flask のルーティング設定
def slack_events():
    return handler.handle(request)
```

コメント:
> "There is nothing specific to Flask here! App is completely framework/runtime agnostic"

Bolt の `App` オブジェクトはフレームワーク完全非依存。`/slack/events` は **Flask のルーティング設定**であり、Bolt の `App` とは関係ない。

Sanic アダプター例（`docs/tools/bolt-python/concepts/async.md`）:

```python
@api.post("/slack/events")
async def endpoint(req: Request):
    return await app_handler.handle(req)
```

同様に `@api.post("/slack/events")` は Sanic 側の設定。

### 4. Lambda アダプターには「パスを指定するルーティング設定」がない

Lambda アダプター（`docs/tools/bolt-python/concepts/lazy-listeners.md`）:

```python
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(process_before_response=True)

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

Flask のような `@route("/slack/events")` に相当する記述が**一切ない**。

Lambda（API Gateway / Lambda Function URL）では、インフラ側でどのパスのリクエストをこの Lambda に送るかを制御する。Bolt の Lambda アダプター自体はパス非依存で全リクエストを処理する。

### 5. manifest.json の Request URL 構造

**`docs/reference/app-manifest.md`** より、各機能ごとに異なる `request_url` フィールドが存在する:

#### Event Subscriptions（イベントサブスクリプション）
```json
"settings": {
    "event_subscriptions": {
        "request_url": "https://example.com/slack/the_Events_API_request_URL"
    }
}
```

#### Interactivity（インタラクティビティ）
```json
"settings": {
    "interactivity": {
        "is_enabled": true,
        "request_url": "https://example.com/slack/message_action",
        "message_menu_options_url": "https://example.com/slack/message_menu_options"
    }
}
```

#### Slash Commands（スラッシュコマンド）
```json
"features": {
    "slash_commands": [
        {
            "command": "/z",
            "url": "https://example.com/slack/slash/please"
        }
    ]
}
```

**重要**: manifest.json の例では各フィールドが異なる URL を使っているが、これは説明的なデモのため。**Bolt を使う場合、すべて同一の URL を設定できる**。

### 6. 各 Request URL の意味（handling-user-interaction.md より）

**`settings.interactivity.request_url`**:
> "the URL we'll send the request payload to when **interactive components** or **shortcuts** are used"
> "This **Request URL** is also used by **modals** for `view_submission` event payloads"

**`settings.interactivity.message_menu_options_url`**:
> External select menu（外部データソースを使うセレクトメニュー）専用。他の機能には不要。

**`features.slash_commands[].url`**:
> 各スラッシュコマンドごとに個別 URL が設定できるが、全コマンドに同一 URL を使用可能。

**まとめ（機能別 Request URL 一覧）**:

| 機能 | manifest.json フィールド | Bolt での処理 |
|------|------------------------|--------------|
| Events API | `settings.event_subscriptions.request_url` | `app.event()` ハンドラー |
| Block Actions（ボタン等） | `settings.interactivity.request_url` | `app.action()` ハンドラー |
| Shortcuts（ショートカット） | `settings.interactivity.request_url` | `app.shortcut()` ハンドラー |
| Modals（モーダル送信） | `settings.interactivity.request_url` | `app.view()` ハンドラー |
| Slash Commands | `features.slash_commands[].url` | `app.command()` ハンドラー |
| External Select Menu | `settings.interactivity.message_menu_options_url` | `app.options()` ハンドラー |

---

## 結論

### Lambda Function URL + Bolt Python での Request URL 設定

#### 1. 使用するアダプター
```python
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(process_before_response=True)

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

Lambda Function URL は API Gateway HTTP API v2.0 と同一のイベント形式のため、`aws_lambda` アダプターがそのまま動作する。

#### 2. manifest.json への URL 設定

Lambda Function URL は `https://xxxxxxxxxxxx.lambda-url.us-east-1.on.aws/` のような形式。

**ルートパス（`/`）でOK**。Bolt は URL パスを使ってルーティングしないため、以下のすべてに同一 URL を設定できる:

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

#### 3. パスを付けることも可能

`https://xxxx.lambda-url.us-east-1.on.aws/slack/events` のようにパスを付けることも可能。Lambda Function URL はパスを含むすべてのリクエストを同じ Lambda 関数に転送するため、Bolt はパスに関係なく動作する。

#### 4. 「まとまったドキュメント」について

ドキュメントスナップショット内に **Lambda Function URL に特化したまとまったドキュメントはなかった**。

Bolt Python ドキュメントは以下の構成でパス情報が散在している:
- `docs/tools/bolt-python/concepts/adapters.md` - アダプター全般（Flask 例）
- `docs/tools/bolt-python/concepts/lazy-listeners.md` - Lambda 用アダプター
- `docs/tools/bolt-python/concepts/custom-adapters.md` - BoltRequest の仕様
- `docs/reference/app-manifest.md` - manifest.json の各 request_url フィールド

公式 GitHub の [`examples/aws_lambda`](https://github.com/slackapi/bolt-python/tree/main/examples/aws_lambda) フォルダに実際のサンプルコードが置かれているとドキュメントが参照しているため、そこを確認するのが最も詳細な情報源になる可能性がある。

---

## 問題・疑問点

- **Lambda Function URL 専用アダプターの有無**: ドキュメントには記述がないが、Bolt Python の GitHub リポジトリには `slack_bolt.adapter.aws_lambda_url` が存在する可能性がある（docs snapshot に含まれていないため未確認）。
- **ドキュメントの鮮度**: Lambda Function URL は 2022年リリースの AWS 機能。このドキュメントスナップショットがそれ以前の可能性あり。最新の Bolt Python ドキュメントや GitHub リポジトリの確認を推奨。
