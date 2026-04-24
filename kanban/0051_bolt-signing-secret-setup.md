# Bolt フレームワークにおける Signing Secret の渡し方

## 知りたいこと

Boltフレームワークにおいてsignature verifyのためのsecretはどうやって渡すのか

## 目的

Boltフレームワークにおいて、EventSubscriptionをHTTPで行う際に安全のためにsignature verifyが必要。だがsecretをどうやって渡したら良いかがわからない。

## 調査サマリー

Bolt for Python では `App()` コンストラクタの `signing_secret` 引数に Signing Secret を渡すことで、署名検証が自動的に有効になる。

### 基本的な渡し方（HTTP モード）

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

### 環境変数からの自動読み込み

`SLACK_SIGNING_SECRET` 環境変数を設定しておけば、明示的に渡さなくても Bolt が自動読み込みする（Lambda FaaS の lazy-listener 例より）。

```bash
export SLACK_SIGNING_SECRET=your-signing-secret
```

### Lambda 環境の場合

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(process_before_response=True)  # FaaS では必須

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

Lambda の環境変数に `SLACK_SIGNING_SECRET` を設定すれば OK。

### ポイント

- Bolt の署名検証は `slack_bolt/middleware/request_verification` として**自動的に**処理される — 自前で検証コードを書く必要なし
- Signing Secret の取得場所: Slack アプリ設定 **Basic Information** → **App Credentials** → **Signing Secret**
- **Socket Mode の場合は `signing_secret` 不要**（WebSocket 接続のため）
- Flask アダプターや Lambda アダプター等を使う場合も、`App()` に渡す方法は同じ

### 参照ドキュメント

- `docs/authentication/verifying-requests-from-slack.md` — 署名検証の仕組み詳細
- `docs/tools/bolt-python/concepts/adapters.md` — Flask アダプター使用例
- `docs/tools/bolt-python/creating-an-app.md` — HTTP モードと Socket Mode の比較
- `docs/tools/bolt-python/concepts/lazy-listeners.md` — Lambda/FaaS 対応例

## 完了サマリー

Bolt for Python で HTTP モードの署名検証に必要な Signing Secret は、`App(signing_secret=os.environ.get("SLACK_SIGNING_SECRET"))` として `App()` コンストラクタに渡すだけで自動的に有効になる。署名検証ロジックは Bolt のミドルウェアとして組み込み済みのため、自前実装は不要。Lambda 等の FaaS 環境では環境変数 `SLACK_SIGNING_SECRET` を設定すれば `App()` が自動読み込みする。
