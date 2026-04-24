# Bolt Lambda パス設定 — 調査ログ

## 調査概要

- **タスク番号**: 0057
- **調査日**: 2026-04-24
- **知りたいこと**: BoltフレームワークをLambdaで動かしている際に path が `/slack/events` だった。Boltのコード側でパスを記述する必要があるのか
- **目的**: Boltフレームワークで実装する際にパスの指定を記述する必要があるのかを知りたい

---

## 調査アプローチ

1. `/slack/events` パスに関するドキュメントを `rg` で全体検索
2. Lambda + Bolt 関連ドキュメントを絞り込み
3. 以下のファイルを重点的に調査:
   - `docs/tools/bolt-js/deployments/aws-lambda.md`
   - `docs/tools/bolt-js/ja-jp/deployments/aws-lambda.md`
   - `docs/tools/bolt-python/concepts/adapters.md`
   - `docs/tools/bolt-python/concepts/lazy-listeners.md`
   - `docs/tools/bolt-js/concepts/receiver.md`

---

## 調査ファイル一覧

- `docs/tools/bolt-js/deployments/aws-lambda.md`
- `docs/tools/bolt-js/ja-jp/deployments/aws-lambda.md`
- `docs/tools/bolt-python/concepts/adapters.md`
- `docs/tools/bolt-python/concepts/lazy-listeners.md`
- `docs/tools/bolt-js/concepts/receiver.md`

---

## 調査結果

### 1. Bolt.js + Lambda (`AwsLambdaReceiver`)

**ドキュメント**: `docs/tools/bolt-js/deployments/aws-lambda.md`

#### Bolt コード側（`app.js`）の記述

```js
const { App, AwsLambdaReceiver } = require('@slack/bolt');

// カスタムレシーバーを初期化
const awsLambdaReceiver = new AwsLambdaReceiver({
    signingSecret: process.env.SLACK_SIGNING_SECRET,
});

// ボットトークンと Lambda 対応レシーバーでアプリを初期化
const app = new App({
    token: process.env.SLACK_BOT_TOKEN,
    receiver: awsLambdaReceiver,
});

// Lambda 関数のイベントを処理
module.exports.handler = async (event, context, callback) => {
    const handler = await awsLambdaReceiver.start();
    return handler(event, context, callback);
}
```

**重要**: `AwsLambdaReceiver` の初期化引数に **パス（path）の指定はない**。`signingSecret` のみを渡している。

#### パスが記述されている場所（`serverless.yml`）

```yaml
service: serverless-bolt-js
frameworkVersion: "4"
provider:
  name: aws
  runtime: nodejs22.x
  environment:
    SLACK_SIGNING_SECRET: ${env:SLACK_SIGNING_SECRET}
    SLACK_BOT_TOKEN: ${env:SLACK_BOT_TOKEN}
functions:
  slack:
    handler: app.handler
    events:
      - http:
          path: slack/events    # ← ここでパスを設定
          method: post
plugins:
  - serverless-offline
```

`/slack/events` パスは **Serverless Framework の設定ファイル（serverless.yml）** に記述されている。これは API Gateway のエンドポイントパスを設定するもので、Bolt のアプリケーションコードとは独立している。

ドキュメントの説明（英語版 p.229）:
> "After your app is deployed, you'll be given an **endpoint** which you'll use as your app's **Request URL**. The **endpoint** should end in `/slack/events`."

ドキュメントの説明（日本語版）:
> "アプリのデプロイが成功すると、**エンドポイント**が発行されます。... 発行された**エンドポイント**は、`/slack/events` で終わる文字列です。"

### 2. Bolt Python + Flask アダプター

**ドキュメント**: `docs/tools/bolt-python/concepts/adapters.md`

```python
from slack_bolt import App
app = App(
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    token=os.environ.get("SLACK_BOT_TOKEN")
)

# Flask アプリを初期化
from flask import Flask, request
flask_app = Flask(__name__)

# SlackRequestHandler: WSGI リクエストを Bolt のインターフェースに変換
from slack_bolt.adapter.flask import SlackRequestHandler
handler = SlackRequestHandler(app)

# ルートを Flask アプリに登録
@flask_app.route("/slack/events", methods=["POST"])  # ← ここでパスを設定
def slack_events():
    return handler.handle(request)
```

**重要**: Flask アダプターを使う場合、`/slack/events` パスは **Flask のルーティング設定**（`@flask_app.route`）に記述する。Bolt の `App` オブジェクト自体にパスは指定しない。

ドキュメントのコメントにも明記されている:
> "# There is nothing specific to Flask here! App is completely framework/runtime agnostic"

つまり、Bolt の `App` クラスはフレームワーク・ランタイム非依存であり、パスはフレームワーク側（Flask ルート、serverless.yml 等）で設定する。

### 3. Bolt Python + Lambda (`SlackRequestHandler`)

**ドキュメント**: `docs/tools/bolt-python/concepts/lazy-listeners.md`

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

# process_before_response は FaaS 実行時に True が必要
app = App(process_before_response=True)

# ... ハンドラー定義 ...

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

**重要**: `SlackRequestHandler` も `App` 初期化時もパスの指定はない。Lambda の handler 関数は API Gateway から渡された `event` を受け取り、`SlackRequestHandler.handle()` に渡すだけ。パスは API Gateway 側（serverless.yml やコンソール設定）で管理される。

### 4. Bolt.js Receiver の仕組み

**ドキュメント**: `docs/tools/bolt-js/concepts/receiver.md`

> "A receiver is responsible for handling and parsing any incoming requests from Slack then sending it to the app"

> "The built-in `HTTPReceiver`, `ExpressReceiver`, `AwsLambdaReceiver` and `SocketModeReceiver` accept several configuration options."

`AwsLambdaReceiver` は Receiver インターフェースの実装の一つ。Lambda の場合は HTTP リクエストを直接受けるのではなく、API Gateway から渡されたイベントオブジェクトを処理する。そのため、パスのルーティングは Lambda の上流（API Gateway / Serverless Framework）が担い、Bolt コードは関与しない。

---

## 結論

### Bolt コード側でパスを記述する必要はない

`/slack/events` という URL パスは **インフラ設定層（serverless.yml / API Gateway）またはフレームワークのルーティング層（Flask の `@app.route`）** で定義されるものであり、Bolt の `App` クラスや各 Receiver クラスには **パスを指定するオプションが存在しない**。

| 構成 | パスを記述する場所 | Bolt コードに記述要否 |
|------|-------------------|----------------------|
| Bolt.js + Lambda + Serverless Framework | `serverless.yml` の `path: slack/events` | **不要** |
| Bolt Python + Lambda + Serverless Framework | `serverless.yml` や API Gateway 設定 | **不要** |
| Bolt Python + Flask | `@flask_app.route("/slack/events")` | **不要**（Flask 側に記述） |
| Bolt Python + Django 等 | 各フレームワークの URL 設定 | **不要**（フレームワーク側に記述） |

### `/slack/events` は Slack の慣習的なデフォルトパス

`/slack/events` は Slack 公式ドキュメントの例で一貫して使われているデフォルト的なパスだが、**固定の要件ではない**。serverless.yml の `path:` や Flask の `@route()` で別のパスを指定することも可能。Slack アプリ設定の「Request URL」と一致させる必要があるだけ。

---

## 問題・疑問点

特になし。ドキュメントから明確に確認できた。

---

## 参考リンク（ドキュメント内）

- Bolt.js Lambda デプロイ: `docs/tools/bolt-js/deployments/aws-lambda.md`
- Bolt Python アダプター: `docs/tools/bolt-python/concepts/adapters.md`
- Bolt Python Lazy Listeners (FaaS): `docs/tools/bolt-python/concepts/lazy-listeners.md`
- Bolt.js Receiver: `docs/tools/bolt-js/concepts/receiver.md`
