# Bolt フレームワークにおける Signing Secret の渡し方 — 調査ログ

## 調査アプローチ

- キーワード `signing_secret`, `signing.secret`, `SigningSecret`, `signature verif` で docs/ 全体を rg 検索
- `docs/tools/bolt-python/` 配下のファイル一覧を確認
- `docs/authentication/verifying-requests-from-slack.md` を読む
- `docs/tools/bolt-python/concepts/adapters.md` を読む
- `docs/tools/bolt-python/creating-an-app.md` を読む
- `docs/tools/bolt-python/concepts/authorization.md` を読む
- `docs/tools/bolt-python/concepts/lazy-listeners.md` を読む（Lambda/FaaS 向け）
- `docs/tools/bolt-js/deployments/aws-lambda.md` を読む（JS 版 Lambda 参考）
- `docs/tools/bolt-python/concepts/socket-mode.md` を読む（Socket Mode との比較）

---

## 調査ファイル一覧

- `docs/authentication/verifying-requests-from-slack.md`
- `docs/tools/bolt-python/concepts/adapters.md`
- `docs/tools/bolt-python/creating-an-app.md`
- `docs/tools/bolt-python/concepts/authorization.md`
- `docs/tools/bolt-python/concepts/lazy-listeners.md`
- `docs/tools/bolt-js/deployments/aws-lambda.md`
- `docs/tools/bolt-python/concepts/socket-mode.md`
- `docs/tools/bolt-python/getting-started.md`
- `docs/tools/bolt-python/index.md`

---

## 調査結果

### 1. Signing Secret（署名検証）の仕組み

**ファイル**: `docs/authentication/verifying-requests-from-slack.md`

Slack は HTTP リクエストを送信する際、各リクエストに `X-Slack-Signature` ヘッダーを付与する。このシグネチャは：

- リクエストボディを SHA-256 でハッシュし、Signing Secret を使った HMAC で生成
- バージョン番号 `v0`、タイムスタンプ、リクエストボディをコロン区切りで連結した文字列を署名
- タイムスタンプ検証でリプレイアタックを防止（5分以上古いリクエストは拒否）

SDK のサポート（自動処理）:

> Some SDKs perform signature verification automatically, accessible via a drop-in replacement of your signing secret for your old verification token.

ドキュメントに明記されている組み込みサポート:
- Bolt for JavaScript: `bolt-js/src/receivers/verify-request.ts`
- **Bolt for Python**: `slack_bolt/middleware/request_verification`（ミドルウェアとして組み込み済み）
- Bolt for Java: `bolt/src/main/java/com/slack/api/bolt/middleware/builtin/RequestVerification.java`

推奨される設定方法:
> Set your Signing Secret as an environment variable: `export SLACK_SIGNING_SECRET=abc123`. Then, initialize the package with the secret.

---

### 2. Bolt Python での Signing Secret の渡し方

#### 方法 1: App コンストラクタで明示的に渡す（最も一般的）

**ファイル**: `docs/tools/bolt-python/concepts/adapters.md`（Flask アダプター例）

```python
from slack_bolt import App

app = App(
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    token=os.environ.get("SLACK_BOT_TOKEN")
)
```

`signing_secret` パラメータに値を渡すだけで、Bolt が自動的に署名検証ミドルウェアを有効化する。

#### 方法 2: 環境変数 `SLACK_SIGNING_SECRET` から自動読み込み

**ファイル**: `docs/tools/bolt-python/concepts/lazy-listeners.md`（Lambda 例）

```bash
export SLACK_SIGNING_SECRET=***
export SLACK_BOT_TOKEN=xoxb-***
```

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

# process_before_response must be True when running on FaaS
app = App(process_before_response=True)
# signing_secret を明示的に渡していないが、環境変数から自動読み込みされる
```

Lambda デプロイ用の `config.yaml` では環境変数として設定する想定。

---

### 3. HTTP モード（内蔵サーバー）での起動

**ファイル**: `docs/tools/bolt-python/creating-an-app.md`（HTTP タブ）

```python
import os
from slack_bolt import App

# Initializes your app with your bot token and signing secret
app = App(
    token=os.environ.get("SLACK_BOT_TOKEN"),
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET")
)

@app.message("hello")
def message_hello(message, say):
    say(f"Hey there <@{message['user']}>!")

if __name__ == "__main__":
    app.start(port=int(os.environ.get("PORT", 3000)))
```

`app.start()` で Bolt 内蔵の HTTPServer が起動し、`/slack/events` エンドポイントで受け付ける。

ドキュメントのコメント:
> Initializes your app with your bot token and signing secret

ソケットモードとの比較（SocketModeHandler 使用時は `signing_secret` は不要）:

```python
# Socket Mode: signing_secret 不要（コメントアウトされている）
app = App(
    token=os.environ.get("SLACK_BOT_TOKEN"),
    # signing_secret=os.environ.get("SLACK_SIGNING_SECRET") # not required for socket mode
)
```

---

### 4. Flask アダプターを使う場合（フル実装例）

**ファイル**: `docs/tools/bolt-python/concepts/adapters.md`

```python
from slack_bolt import App
app = App(
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    token=os.environ.get("SLACK_BOT_TOKEN")
)

# Bolt アプリはフレームワーク非依存
@app.command("/hello-bolt")
def hello(body, ack):
    ack(f"Hi <@{body['user_id']}>!")

# Flask アプリを初期化
from flask import Flask, request
flask_app = Flask(__name__)

# SlackRequestHandler: WSGI リクエストを Bolt のインタフェースに変換
from slack_bolt.adapter.flask import SlackRequestHandler
handler = SlackRequestHandler(app)

@flask_app.route("/slack/events", methods=["POST"])
def slack_events():
    return handler.handle(request)
```

---

### 5. AWS Lambda アダプターを使う場合

**ファイル**: `docs/tools/bolt-python/concepts/lazy-listeners.md`

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

# FaaS 環境では process_before_response=True が必須
app = App(process_before_response=True)

# ハンドラー定義...
app.command("/start-process")(
    ack=respond_to_slack_within_3_seconds,
    lazy=[run_long_process]
)

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

環境変数 `SLACK_SIGNING_SECRET` を Lambda の環境変数として設定する。Bolt は自動的に読み込む。

必要な IAM 権限（lazy listener 使用時）:
```json
{
    "Action": [
        "lambda:InvokeFunction",
        "lambda:GetFunction"
    ]
}
```

---

### 6. マルチワークスペース（OAuth）対応アプリの場合

**ファイル**: `docs/tools/bolt-python/concepts/authorization.md`

```python
app = App(
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    authorize=authorize  # カスタム認証関数
)
```

`signing_secret` は単一ワークスペース・マルチワークスペースのどちらの場合も同様に渡す。

---

### 7. Signing Secret の取得場所

**ファイル**: `docs/authentication/verifying-requests-from-slack.md`

> Grab your Slack Signing Secret, available in the app admin panel under Basic Info.

- Slack アプリの設定ページ（https://api.slack.com/apps）
- **Basic Information** → **App Credentials** → **Signing Secret**
- "Regenerate" ボタンで再生成可能

---

## まとめ・回答

### Bolt Python で Signing Secret を渡す方法

| 方法 | コード | 推奨場面 |
|------|--------|---------|
| 明示的に `signing_secret` 引数で渡す | `App(signing_secret=os.environ.get("SLACK_SIGNING_SECRET"), ...)` | 最も一般的・明確 |
| 環境変数 `SLACK_SIGNING_SECRET` から自動読み込み | `App(...)` のみ（環境変数を設定） | Lambda 等の FaaS |

**重要ポイント**:
1. `App()` コンストラクタの `signing_secret` パラメータに渡すのが基本
2. 値は `os.environ.get("SLACK_SIGNING_SECRET")` で環境変数から取得するのが推奨
3. 明示的に渡さなくても、環境変数 `SLACK_SIGNING_SECRET` が設定されていれば Bolt が自動読み込みする（lazy-listener Lambda 例より確認）
4. Bolt は署名検証を `slack_bolt/middleware/request_verification` として**自動的に**処理する — 自前で検証コードを書く必要はない
5. **Socket Mode の場合は `signing_secret` 不要**（WebSocket 接続のため）
6. Lambda/FaaS では `process_before_response=True` が必要、`signing_secret` は環境変数から自動読み込み

### HTTP モード最小実装例

```python
import os
from slack_bolt import App

app = App(
    token=os.environ.get("SLACK_BOT_TOKEN"),
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET")  # ← ここで渡す
)

if __name__ == "__main__":
    app.start(port=3000)
```

### Lambda 最小実装例

```python
import os
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

# 環境変数 SLACK_SIGNING_SECRET / SLACK_BOT_TOKEN を Lambda 環境変数に設定
app = App(process_before_response=True)  # signing_secret は自動読み込み

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

---

## 問題・疑問点

- Bolt Python が `signing_secret` を省略したとき環境変数 `SLACK_SIGNING_SECRET` を自動読み込みする挙動は、ドキュメントでは lazy-listener の例から推測したもの。公式には「環境変数を設定してから `App()` を初期化する」と書かれているが、明示的に自動読み込みの仕様として記述している箇所は確認できなかった（GitHub のソースコードを確認するとより確実）
- JavaScript 版 Bolt の Lambda では `AwsLambdaReceiver` を別途生成して `signingSecret` を渡す設計だが、Python 版は `App()` に直接渡す or 環境変数から自動読み込みという設計で若干異なる
