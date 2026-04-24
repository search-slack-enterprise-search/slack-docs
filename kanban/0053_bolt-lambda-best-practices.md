# Bolt を Lambda で実装する際のベストプラクティス

## 知りたいこと

BoltをLambdaで実装するときのベストプラクティス

## 目的

ベストプラクティスを知ることで実装を最適化したい。とくにSnap Startなどを使うことも想定できるので、どうするのが良いかを知りたい (グローバルでappをインスタンス化するとSecret Managerなどからsecret取得するのに支障がでるかもしれない)

## 調査サマリー

### 公式ドキュメントのパターン（Bolt Python + Lambda）

`docs/tools/bolt-python/concepts/lazy-listeners.md` が示す公式パターン：

- `App(process_before_response=True)` を**モジュールレベル（グローバル）**で初期化
- `SlackRequestHandler(app=app)` は `handler()` 関数内で毎回インスタンス化
- リスナー登録もモジュールレベルで完結

`process_before_response=True` は Lambda では**必須**（HTTP レスポンス後にスレッドが継続できないため、完了まで応答を遅延させる）。

### Lazy Listener（3秒超の処理）

3秒を超える処理が必要な場合は Lazy Listener を使う：

```python
app.command("/my-command")(
    ack=respond_within_3_seconds,  # 3秒以内に ack()
    lazy=[long_process]            # 時間のかかる処理
)
```

Lazy Listener は Lambda の**自己 invoke** を使うため、IAM ロールに `lambda:InvokeFunction` + `lambda:GetFunction` が必要。Enterprise Search（10秒同期処理）では Lazy Listener は不要。

### Secret Manager との関係

Slack ドキュメントは `security.md` で AWS Secrets Manager を推奨（Lambda 環境変数への平文設定は非推奨）。

グローバル初期化で Secret Manager から取得するパターン：

```python
secrets = get_secret("my-slack-app/secrets")  # コールドスタート時のみ実行
app = App(token=secrets["SLACK_BOT_TOKEN"], signing_secret=secrets["SLACK_SIGNING_SECRET"], process_before_response=True)
```

**トレードオフ**:
- グローバル初期化 → ウォームスタートで再取得なし（速い）、ただしシークレットローテーション後の反映はコールドスタートまで遅れる
- 遅延初期化（ハンドラ内の初回のみ） → Snap Start 対応に適する

### Snap Start について

**Slack ドキュメントには Snap Start への言及は一切なし**。一般的な AWS の知識として：

- Snap Start の Init フェーズで外部ネットワーク（Secret Manager 等）にアクセスするのは安全でない可能性がある
- Snap Start 使用時は遅延初期化（シングルトンパターン）を推奨
- Python Lambda の Snap Start 対応状況は AWS ドキュメントを別途確認が必要

## 完了サマリー

- 調査日: 2026-04-24
- ログ: `logs/0053_bolt-lambda-best-practices.md`
- 主要ソース: `docs/tools/bolt-python/concepts/lazy-listeners.md`, `docs/tools/bolt-js/deployments/aws-lambda.md`
