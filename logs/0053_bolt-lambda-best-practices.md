# Bolt を Lambda で実装する際のベストプラクティス — 調査ログ

## 調査概要

- **調査日**: 2026-04-24
- **タスクファイル**: kanban/0053_bolt-lambda-best-practices.md
- **調査テーマ**: Bolt を Lambda で実装するときのベストプラクティス（Snap Start・Secret Manager との関係を含む）

---

## 調査したファイル一覧

- `docs/tools/bolt-python/concepts/lazy-listeners.md` — FaaS 対応 Lazy Listener（中核）
- `docs/tools/bolt-python/ja-jp/concepts/lazy-listeners.md` — 同日本語版
- `docs/tools/bolt-js/deployments/aws-lambda.md` — Bolt JS AWS Lambda デプロイガイド
- `docs/tools/bolt-js/ja-jp/deployments/aws-lambda.md` — 同日本語版
- `docs/tools/bolt-python/concepts/adapters.md` — Bolt Python アダプタ
- `docs/tools/bolt-python/concepts/authorization.md` — 認可パターン
- `docs/tools/bolt-python/concepts/async.md` — 非同期処理
- `docs/tools/bolt-python/concepts/listener-middleware.md` — リスナーミドルウェア
- `docs/tools/bolt-js/concepts/receiver.md` — Receiver カスタマイズ
- `docs/app-management/hosting-slack-apps.md` — ホスティング選択肢
- 既存ログ: `logs/0031_lambda-bolt-custom-agent.md` — Lambda + Bolt カスタムエージェント（参照）
- 既存ログ: `logs/0039_enterprise-search-on-aws-lambda.md` — Enterprise Search on Lambda（参照）
- 既存ログ: `logs/0052_lambda-env-secret-plaintext-risk.md` — Lambda 環境変数とシークレット管理（参照）

---

## 調査結果

### 1. 公式ドキュメントが示す基本パターン

#### Bolt for Python の Lambda ハンドラ実装

`docs/tools/bolt-python/concepts/lazy-listeners.md`（および ja-jp 版）の例：

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

# FaaS で実行するときは process_before_response を True にする必要があります
app = App(process_before_response=True)  # ← モジュールレベル（グローバル）で初期化

# リスナー登録も同様にモジュールレベルで定義
def respond_to_slack_within_3_seconds(body, ack):
    text = body.get("text")
    if text is None or len(text) == 0:
        ack(":x: Usage: /start-process (description here)")
    else:
        ack(f"Accepted! (task: {body['text']})")

import time
def run_long_process(respond, body):
    time.sleep(5)
    respond(f"Completed! (task: {body['text']})")

app.command("/start-process")(
    ack=respond_to_slack_within_3_seconds,
    lazy=[run_long_process]
)

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)  # ← ハンドラ内で毎回インスタンス化
    return slack_handler.handle(event, context)
```

**重要なポイント：**

- `App` インスタンスはモジュールレベル（グローバル）で初期化する
- `SlackRequestHandler` は `handler()` 関数の中で毎回インスタンス化する
- リスナー関数の登録も全てモジュールレベルで行う

これが公式の推奨パターン。

---

### 2. process_before_response=True の必要性

`docs/tools/bolt-python/ja-jp/concepts/lazy-listeners.md` より：

> しかし、FaaS 環境や類似のランタイムで実行されるアプリでは、 **HTTP レスポンスを返したあとにスレッドやプロセスの実行を続けることができない** ため、確認の応答を送信した後で時間のかかる処理をするという通常のパターンに従うことができません。こうした環境で動作させるためには、 `process_before_response` フラグを `True` に設定します。このフラグが `True` に設定されている場合、Bolt はリスナー関数での処理が完了するまで HTTP レスポンスの送信を遅延させます。

**なぜこれが必要か：**

| 環境 | HTTP レスポンス後の動作 |
|------|----------------------|
| 通常のサーバー | プロセスが継続して動く → バックグラウンド処理が可能 |
| Lambda（FaaS） | HTTP レスポンスを返すと Lambda の実行コンテキストが凍結 → 後続処理が不可能 |

`process_before_response=True` にすることで、Bolt はリスナーが全て完了するまで HTTP 200 を送らず、Lambda が早期終了しないようにする。

---

### 3. Lazy Listener パターン（3秒を超える処理）

Slack は 3 秒以内に ACK を要求する。Lambda で長時間処理が必要な場合（カスタムエージェントの LLM 呼び出しなど）は Lazy Listener を使う。

```python
app.command("/start-process")(
    ack=respond_to_slack_within_3_seconds,  # 3 秒以内に ack() を呼ぶ担当
    lazy=[run_long_process]                  # 時間のかかる処理（ack() には触れない）
)
```

**Lazy Listener の仕組み：**

Bolt が Lambda を自己 invoke（self-invoke）することで長時間処理を別 Lambda 実行として切り出す。

**必要な IAM 権限（Lazy Listener 使用時に必須）：**

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction",
                "lambda:GetFunction"
            ],
            "Resource": "*"
        }
    ]
}
```

ドキュメントの注記:
> lazy リスナーの実行には lambda:InvokeFunction と lambda:GetFunction が必要です

Enterprise Search の場合（10秒同期処理）は Lazy Listener は不要（既存ログ 0039 参照）。

---

### 4. Bolt for JavaScript の場合

`docs/tools/bolt-js/deployments/aws-lambda.md` より：

```javascript
const { App, AwsLambdaReceiver } = require('@slack/bolt');

// カスタムレシーバーを初期化（モジュールレベル）
const awsLambdaReceiver = new AwsLambdaReceiver({
    signingSecret: process.env.SLACK_SIGNING_SECRET,
});

// App を初期化（モジュールレベル）
const app = new App({
    token: process.env.SLACK_BOT_TOKEN,
    receiver: awsLambdaReceiver,
    // AwsLambdaReceiver を利用する場合は processBeforeResponse は省略可能
});

// Lambda 関数のイベントを処理
module.exports.handler = async (event, context, callback) => {
    const handler = await awsLambdaReceiver.start();
    return handler(event, context, callback);
}
```

**JS の特記事項：**

- `AwsLambdaReceiver` を使う場合は `processBeforeResponse` は省略可能
- OAuth を実装する場合は `ExpressReceiver` を使い、`processBeforeResponse: true` が必須
- `awsLambdaReceiver.start()` はハンドラ内で毎回呼び出す

---

### 5. グローバル初期化と Secret Manager の関係

#### 公式ドキュメントの立場

**グローバル初期化パターン（公式ドキュメント例）：**

```python
app = App(
    token=os.environ.get("SLACK_BOT_TOKEN"),
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    process_before_response=True
)
```

`docs/tools/bolt-python/concepts/adapters.md` の Flask 例でも同様に `os.environ.get()` でグローバル初期化。

**Slack security.md の推奨（既存ログ 0052 より）：**

> For production: Use a dedicated, industry-standard secrets management solution, such as GitHub Actions Secrets, **AWS Secrets Manager**, or HashiCorp Vault.

**Secret Manager からシークレットを取得してグローバル初期化する場合：**

```python
import boto3, json

def get_secret(secret_name):
    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])

# モジュールロード時（コールドスタート時）に実行される
secrets = get_secret("my-slack-app/secrets")

app = App(
    token=secrets["SLACK_BOT_TOKEN"],
    signing_secret=secrets["SLACK_SIGNING_SECRET"],
    process_before_response=True
)
```

#### Lambda のライフサイクルと初期化タイミング

| 起動種別 | モジュール初期化（グローバル変数）の実行 |
|---------|--------------------------------------|
| コールドスタート | 実行される → Secret Manager から取得可能 |
| ウォームスタート | スキップ（グローバル変数はキャッシュされる） |

グローバルにシークレットを取得しておけば、ウォームスタート時は再取得せずキャッシュを使用するため、レスポンスが速くなる。ただし、シークレットをローテーションした場合はコールドスタートまで古い値が使われる点に注意。

---

### 6. Snap Start について

#### Slack ドキュメントへの言及

Slack 公式ドキュメント（本調査で確認した全ファイル）には **Snap Start への言及は一切ない**。

#### Snap Start の基本知識（Slack ドキュメント外の情報）

- Snap Start は AWS Lambda の機能（2022年11月リリース）
- **現時点（2026年時点）での対応ランタイム**: Java（Corretto 11/17/21）が中心
- Python Lambda の Snap Start 対応は一部リージョン・バージョンで拡充中（AWS ドキュメント要確認）

#### Snap Start 使用時の注意点（Slack ドキュメント外の観点）

Snap Start ではスナップショット取得フェーズ（`Init` フェーズ）の状態を保存し、以降の起動時に復元する。

**問題になりうるシナリオ：**

1. **Init フェーズで Secret Manager に接続する場合**: Snap Start の Init フェーズでは一部のネットワーク接続が制限される可能性がある（AWS の制約に依存）
2. **シークレットの有効期限・ローテーション**: スナップショット取得時のシークレットが復元後も使われるため、ローテーション後の反映が遅れる

**Snap Start での推奨パターン（AWS 一般知識ベース）：**

```python
# Option A: ハンドラ内で遅延初期化（Snap Start 対応）
_app = None

def get_app():
    global _app
    if _app is None:
        secrets = get_secret("my-slack-app/secrets")
        _app = App(
            token=secrets["SLACK_BOT_TOKEN"],
            signing_secret=secrets["SLACK_SIGNING_SECRET"],
            process_before_response=True
        )
    return _app

def handler(event, context):
    slack_handler = SlackRequestHandler(app=get_app())
    return slack_handler.handle(event, context)
```

ただし、この遅延初期化パターンを採用すると Snap Start のメリット（コールドスタート時間の短縮）が一部失われる。

---

### 7. ベストプラクティスのまとめ（調査結果）

#### Bolt for Python + Lambda の必須設定

| 項目 | 設定値 | 根拠 |
|------|--------|------|
| `process_before_response` | `True` | FaaS では HTTP レスポンス後にスレッドが継続できないため |
| `App` の初期化場所 | モジュールレベル（グローバル） | 公式ドキュメントのパターン。ウォームスタート時の再初期化を避ける |
| `SlackRequestHandler` の初期化場所 | `handler()` 関数内 | 毎リクエストで新しいハンドラを生成（公式パターン） |
| Lazy Listener 使用条件 | 3秒超の処理が必要な場合 | 自己 invoke で長時間処理を実現 |
| Lazy Listener 使用時の IAM 権限 | `lambda:InvokeFunction` + `lambda:GetFunction` | 自己 invoke に必要 |

#### シークレット管理パターン（Slack security.md 推奨ベース）

| パターン | 説明 | トレードオフ |
|---------|------|------------|
| **Lambda 環境変数** | シンプルだが AWS Console で平文表示 | 手軽だが Slack 推奨に完全準拠しない |
| **Secret Manager + グローバル初期化** | コールドスタート時に取得 | 推奨パターン。ウォームスタートは速いが、ローテーション後の反映が遅れる可能性 |
| **Secret Manager + 遅延初期化** | ハンドラ内で初回のみ取得 | Snap Start 対応に適するが、最初のリクエストが遅い |
| **Secret Manager + 毎リクエスト取得** | 毎回取得（コスト高・遅い） | 非推奨 |

#### Snap Start 利用時の考慮事項

Slack ドキュメントには記載なし。一般的な AWS Lambda のベストプラクティスとして：

- Snap Start を使う場合、Init フェーズで外部ネットワーク（Secret Manager 等）にアクセスするのは安全でない可能性
- 遅延初期化パターン（`if _app is None:` でのシングルトン）を採用することで、Snap Start の制約と Lambda の再利用を両立できる
- ただし Snap Start のメリット（コールドスタート短縮）を最大化するには、できる限り Init フェーズで初期化する方が良い

#### Lambda タイムアウト設定

| ユースケース | 推奨タイムアウト |
|------------|----------------|
| Enterprise Search のみ | 15〜30 秒（10秒処理 + オーバーヘッド） |
| カスタムエージェント（Lazy Listener あり） | 30秒以上 |
| Lazy Listener 使用時の個別ハンドラ | 最大 15 分まで（長時間処理に応じて） |

---

## 調査アプローチ

1. `docs/tools/bolt-python/concepts/lazy-listeners.md` で FaaS（Lambda）の基本パターンを確認
2. `docs/tools/bolt-js/deployments/aws-lambda.md` で Bolt JS の Lambda パターンを確認
3. 既存ログ（0031, 0039, 0052）から Lambda + Bolt の既知情報を参照
4. Snap Start に関する Slack ドキュメントの記載を検索（`rg -i "snap.start"` 等）→ 記載なし
5. Secret Manager 初期化パターンとの関係を整理

---

## 問題・疑問点

- **Snap Start + Python Lambda**: Slack ドキュメントに記載なし。AWS の実際の対応状況は AWS ドキュメントを別途確認が必要
- **グローバル初期化でのシークレットローテーション**: コールドスタート時のみ再取得するグローバル初期化パターンでは、Secret Manager でシークレットをローテーションしても次のコールドスタートまで古い値が使われる。これをどう対処するかはアーキテクチャの選択（許容する or 定期的にコールドスタートを強制する等）
- **`SlackRequestHandler` の毎回インスタンス化コスト**: 公式ドキュメントのパターンは `handler()` 内で毎回 `SlackRequestHandler(app=app)` を生成しているが、これを `app = App(...)` と同様にグローバルに持つパターン（`slack_handler = SlackRequestHandler(app=app)` をモジュールレベルで定義）が使えるかは未確認
