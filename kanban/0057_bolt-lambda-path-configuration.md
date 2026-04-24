# Bolt Lambda パス設定

## 知りたいこと

BoltフレームワークをLambdaで動かしている際にpathが `/slack/events`だった。Boltのコード側でパスを記述する必要があるのか

## 目的

Boltフレームワークで実装する際にパスの指定を記述する必要があるのかを知りたい

## 調査サマリー

**結論: Bolt のコード側でパスを記述する必要はない。**

`/slack/events` というパスは Bolt の `App` クラスや各 Receiver クラスには **存在しない**設定項目であり、インフラ・フレームワーク層で定義される。

### 構成ごとのパス設定箇所

| 構成 | パスを記述する場所 |
|------|------------------|
| Bolt.js + Lambda + Serverless Framework | `serverless.yml` の `path: slack/events` |
| Bolt Python + Lambda + Serverless Framework | `serverless.yml` や API Gateway 設定 |
| Bolt Python + Flask | `@flask_app.route("/slack/events", methods=["POST"])` |

### 仕組み

- **Bolt.js**: `AwsLambdaReceiver` は `signingSecret` のみで初期化。パス指定オプションなし。パスは Serverless Framework の `serverless.yml` で `path: slack/events` として設定し、API Gateway のエンドポイントとなる。
- **Bolt Python + Lambda**: `SlackRequestHandler` で Lambda handler を実装。パス指定なし。API Gateway 側がパスをルーティングして Lambda に渡す。
- **Bolt Python + Flask**: `SlackRequestHandler` は Bolt のインターフェースへの変換器として動作。パスは Flask のルート定義 `@flask_app.route("/slack/events")` に記述する（Bolt の `App` オブジェクトは「フレームワーク非依存」）。

### `/slack/events` は慣習的なデフォルトパス

固定の要件ではなく、Slack アプリ設定の「Request URL」と一致させれば任意のパスを使用可能。

## 完了サマリー

- 調査完了日: 2026-04-24
- ログ: `logs/0057_bolt-lambda-path-configuration.md`
- **Bolt コードにパス記述は不要**。パスはインフラ設定（serverless.yml）またはフレームワークのルーティング（Flask の `@route`）で定義する。
