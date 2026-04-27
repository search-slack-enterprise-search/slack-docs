# Bolt Python App インスタンス化に必要な設定値（Lambda 環境向け）

## 知りたいこと

Enterprise SearchをLambdaで動かすときに必要になる、Boltフレームワーク(Python)のAppをインスタンス化するときに必要な設定値

## 目的

Appをインスタンス化するときに必要な設定値を知りたい。必要最低限のものと推奨項目両方知りたい。

## 調査サマリー

### 必須設定値（Lambda 環境）

| パラメータ | 値・取得先 | 根拠 |
|-----------|----------|------|
| `process_before_response` | `True` | Lambda は HTTP レスポンス後にスレッドを継続できないため必須（lazy-listeners.md） |
| `signing_secret` | `SLACK_SIGNING_SECRET`（Basic Information → App Credentials） | HTTP モードのリクエスト署名検証に必須 |
| `token` | `SLACK_BOT_TOKEN`（xoxb-...、OAuth & Permissions） | API 呼び出し用トークン（単一ワークスペースの場合） |

### 最小実装コード（公式ドキュメントの例）

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

# process_before_response must be True when running on FaaS
app = App(process_before_response=True)
# 環境変数 SLACK_SIGNING_SECRET / SLACK_BOT_TOKEN から自動読み込み

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

### 推奨: 明示的設定パターン

```python
import os
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(
    token=os.environ.get("SLACK_BOT_TOKEN"),
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    process_before_response=True
)

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

### マルチワークスペース（Enterprise Search のオーグ対応）の場合

`token` の代わりに `authorize` 関数を使ってワークスペースごとにトークンを動的に返す:

```python
app = App(
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    authorize=authorize,  # DB などからトークンを取得するカスタム関数
    process_before_response=True
)
```

`authorize` 関数は `AuthorizeResult` を返す必要があり、`bot_token`（または `user_token`）、`bot_id`、`bot_user_id`、`enterprise_id`、`team_id` を含める。

### OAuth 対応（配布アプリ向け）

注意: Enterprise Search は Slack Marketplace 配布不可のため通常は不要。

```python
app = App(
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    oauth_settings=OAuthSettings(
        client_id=os.environ["SLACK_CLIENT_ID"],
        client_secret=os.environ["SLACK_CLIENT_SECRET"],
        scopes=["..."],
        installation_store=...,
        state_store=...
    ),
    process_before_response=True
)
```

### App() 初期化時の重要な注意点

- `App` インスタンスはモジュールレベル（グローバル）で初期化する（ウォームスタート時の再初期化を避けるため）
- `SlackRequestHandler` は `handler()` 関数の中で毎リクエスト生成する（公式パターン）
- `signing_secret` は省略しても環境変数 `SLACK_SIGNING_SECRET` から自動読み込みされる（lazy-listener の Lambda 例より）
- Socket Mode では `signing_secret` は不要だが、Lambda は HTTP モードのため必須

### Lambda で Lazy Listener を使う場合の追加 IAM 権限

Enterprise Search では不要（10秒以内の同期処理のため）。カスタムエージェント等で必要な場合:

```json
{ "Action": ["lambda:InvokeFunction", "lambda:GetFunction"] }
```

## 完了サマリー

Lambda で Bolt Python App を動かすための必須設定値は `process_before_response=True`、`signing_secret`、`token`（または `authorize`）の3つ。`process_before_response=True` は FaaS 環境固有の必須パラメータで、他2つは HTTP モードのリクエスト検証・API 呼び出しに必要。マルチワークスペース対応（Enterprise のオーグ対応）が必要な場合は `token` の代わりに `authorize` 関数か `oauth_settings` を使用する。
