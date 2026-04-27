# Bolt Python App インスタンス化に必要な設定値（Lambda 環境向け） — 調査ログ

## 調査概要

- **調査日**: 2026-04-27
- **タスクファイル**: kanban/0062_bolt-python-app-init-config.md
- **調査テーマ**: Enterprise Search を Lambda で動かすときに必要な Bolt(Python) の `App()` インスタンス化設定値

---

## 調査したファイル一覧

- `docs/tools/bolt-python/concepts/lazy-listeners.md` — FaaS/Lambda 向け Lazy Listener（process_before_response の根拠）
- `docs/tools/bolt-python/ja-jp/concepts/lazy-listeners.md` — 同日本語版
- `docs/tools/bolt-python/concepts/adapters.md` — Bolt Python アダプタ一覧・Flask 例
- `docs/tools/bolt-python/creating-an-app.md` — App 初期化の基本例（HTTP/Socket Mode 両方）
- `docs/tools/bolt-python/concepts/authorization.md` — カスタム認可（authorize 関数）パターン
- `docs/tools/bolt-python/concepts/authenticating-oauth.md` — OAuth 対応（oauth_settings）パターン
- `docs/tools/bolt-python/getting-started.md` — クイックスタートガイド
- `docs/tools/bolt-python/index.md` — Bolt Python 概要
- 既存ログ: `logs/0051_bolt-signing-secret-setup.md` — Signing Secret の渡し方（参照）
- 既存ログ: `logs/0053_bolt-lambda-best-practices.md` — Lambda ベストプラクティス（参照）
- 既存ログ: `logs/0039_enterprise-search-on-aws-lambda.md` — Enterprise Search on Lambda（参照）

---

## 調査結果

### 1. App() コンストラクタで使える主要パラメータ

ドキュメントの各所から確認できた `App()` のパラメータをまとめる。

#### 1-1. 認証・認可系

| パラメータ | 型 | 説明 |
|-----------|---|------|
| `token` | `str` | Bot Token（xoxb-...）。単一ワークスペースアプリで使用 |
| `signing_secret` | `str` | Signing Secret。HTTP モードで必須。署名検証に使用 |
| `authorize` | `Callable` | カスタム認可関数。マルチワークスペース対応時に `token` の代わりに使用 |
| `oauth_settings` | `OAuthSettings` | OAuth 設定オブジェクト。マルチワークスペース・配布アプリ向け |
| `installation_store` | `InstallationStore` | インストール情報の保存先（`oauth_settings` と組み合わせても使える） |

根拠:
- `docs/tools/bolt-python/concepts/adapters.md`:
  ```python
  app = App(
      signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
      token=os.environ.get("SLACK_BOT_TOKEN")
  )
  ```
- `docs/tools/bolt-python/concepts/authorization.md`:
  ```python
  app = App(
      signing_secret=os.environ["SLACK_SIGNING_SECRET"],
      authorize=authorize
  )
  ```
- `docs/tools/bolt-python/concepts/authenticating-oauth.md`:
  ```python
  app = App(
      signing_secret=os.environ["SLACK_SIGNING_SECRET"],
      oauth_settings=oauth_settings
  )
  ```

#### 1-2. FaaS / Lambda 向け

| パラメータ | 型 | デフォルト | 説明 |
|-----------|---|----------|------|
| `process_before_response` | `bool` | `False` | FaaS（Lambda 等）で必須。`True` にするとリスナー完了まで HTTP 200 を遅延させる |

根拠（`docs/tools/bolt-python/concepts/lazy-listeners.md`）:
```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

# process_before_response must be True when running on FaaS
app = App(process_before_response=True)
```

日本語版のコメント:
> FaaS で実行するときは process_before_response を True にする必要があります

#### 1-3. AI アシスタント向け

| パラメータ | 型 | 説明 |
|-----------|---|------|
| `ignoring_self_assistant_message_events_enabled` | `bool` | デフォルト `True`。`False` にするとボット自身のメッセージイベントも処理する（AI アシスタントで bot_message リスナーを使う場合に必要） |

根拠（`docs/tools/bolt-python/concepts/using-the-assistant-class.md`）:
```python
app = App(
    token=os.environ["SLACK_BOT_TOKEN"],
    # This must be set to handle bot message events
    ignoring_self_assistant_message_events_enabled=False,
)
```

---

### 2. Lambda 環境での必須設定値

#### 2-1. process_before_response=True（必須）

FaaS 環境では HTTP レスポンスを返した後にスレッドやプロセスを継続できないため、`process_before_response=True` が必須。

`docs/tools/bolt-python/concepts/lazy-listeners.md` より:
> when running your app on FaaS or similar runtimes which **do not allow you to run threads or processes after returning an HTTP response**, we cannot follow the typical pattern of acknowledgement first, processing later. To work with these runtimes, set the `process_before_response` flag to `True`.

| `process_before_response` | 動作 |
|--------------------------|------|
| `False`（デフォルト） | ack() → HTTP 200 送信 → バックグラウンド処理継続 |
| `True`（FaaS必須） | 全リスナー処理が完了するまで HTTP 200 を送らない |

#### 2-2. signing_secret（必須）

HTTP モード（Lambda は HTTP モードになる）ではリクエストの署名検証に必須。

明示指定:
```python
app = App(
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    process_before_response=True
)
```

環境変数による自動読み込み（Lambda の公式ドキュメント例）:
```bash
export SLACK_SIGNING_SECRET=***
export SLACK_BOT_TOKEN=xoxb-***
```
```python
app = App(process_before_response=True)
# ↑ signing_secret を省略しても環境変数 SLACK_SIGNING_SECRET から自動読み込みされる
```

`docs/tools/bolt-python/concepts/lazy-listeners.md` の Lambda 例では `signing_secret` を明示せず `App(process_before_response=True)` のみで初期化しており、環境変数から自動読み込みされることを示している。

#### 2-3. token または authorize/oauth_settings（どれか必須）

Slack の API を呼び出すためのトークンが必要。

- **単一ワークスペース**: `token=os.environ.get("SLACK_BOT_TOKEN")`
- **マルチワークスペース（カスタム）**: `authorize=authorize_func`
- **マルチワークスペース（OAuth）**: `oauth_settings=OAuthSettings(...)`

---

### 3. Enterprise Search 向けの考慮事項

既存ログ（`logs/0039_enterprise-search-on-aws-lambda.md`）より:

- Enterprise Search はオーグ（Org）レベルでインストールされる
- アプリは「オーグ対応（org-ready）」である必要がある
- Enterprise Search の `function_executed` イベントは **10秒以内に同期完了**が必要（Lazy Listener は不要）
- Enterprise Search アプリは Slack Marketplace への公開・配布不可

Enterprise Search で単一オーグ（固定トークン）の場合は `token` が使える。複数オーグ対応が必要な場合は `authorize` 関数で動的に解決する必要がある。

---

### 4. Lambda での実装パターン

#### パターン A: 最小構成（公式ドキュメント例そのまま）

`docs/tools/bolt-python/concepts/lazy-listeners.md` より:

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

# FaaS では process_before_response=True が必須
app = App(process_before_response=True)
# 環境変数 SLACK_SIGNING_SECRET / SLACK_BOT_TOKEN が設定されていること

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

環境変数:
- `SLACK_SIGNING_SECRET`: Signing Secret（Basic Information から取得）
- `SLACK_BOT_TOKEN`: Bot Token（xoxb-...）

#### パターン B: 明示的設定（可読性重視）

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

#### パターン C: カスタム認可（マルチワークスペース・Enterprise 向け）

`docs/tools/bolt-python/concepts/authorization.md` より:

```python
import os
from slack_bolt import App
from slack_bolt.authorization import AuthorizeResult
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

def authorize(enterprise_id, team_id, logger):
    # DB やシークレットストアからトークンを取得するカスタムロジック
    token = fetch_token_from_db(enterprise_id, team_id)
    if token:
        return AuthorizeResult(
            enterprise_id=enterprise_id,
            team_id=team_id,
            bot_token=token["bot_token"],
            bot_id=token["bot_id"],
            bot_user_id=token["bot_user_id"]
        )
    logger.error("No authorization information was found")

app = App(
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    authorize=authorize,
    process_before_response=True
)

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

`AuthorizeResult` の必要フィールド（`docs/tools/bolt-python/concepts/authorization.md` より）:
- `bot_token`（xoxb）または `user_token`（xoxp）のどちらか（必須）
- `bot_user_id` と `bot_id`（bot_token 使用時）
- `enterprise_id` と `team_id`
- `user_id`（user_token 使用時のみ）

#### パターン D: OAuth 対応（複数ワークスペースへの配布）

`docs/tools/bolt-python/concepts/authenticating-oauth.md` より:

```python
import os
from slack_bolt import App
from slack_bolt.oauth.oauth_settings import OAuthSettings
from slack_sdk.oauth.installation_store import FileInstallationStore
from slack_sdk.oauth.state_store import FileOAuthStateStore

oauth_settings = OAuthSettings(
    client_id=os.environ["SLACK_CLIENT_ID"],
    client_secret=os.environ["SLACK_CLIENT_SECRET"],
    scopes=["channels:read", "groups:read", "chat:write"],
    installation_store=FileInstallationStore(base_dir="./data/installations"),
    state_store=FileOAuthStateStore(expiration_seconds=600, base_dir="./data/states")
)

app = App(
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    oauth_settings=oauth_settings,
    process_before_response=True  # Lambda の場合
)
```

注意: Enterprise Search はマーケットプレイス配布不可のため、`FileInstallationStore` より DB や S3 への保存を検討。

---

### 5. 必要な IAM 権限（Lazy Listener 使用時）

`docs/tools/bolt-python/concepts/lazy-listeners.md` より:

Lazy Listener は Lambda が自分自身を invoke（self-invoke）する仕組みのため、以下の IAM 権限が必要:

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

**Enterprise Search の場合**: 処理が 10 秒以内に同期完了するため、Lazy Listener は不要（既存ログ 0039 より）。

---

### 6. 設定値のまとめ

#### 必須設定値

| パラメータ | 値・取得先 | 用途 |
|-----------|----------|------|
| `process_before_response` | `True` | FaaS（Lambda）環境で必須 |
| `signing_secret` | `SLACK_SIGNING_SECRET`（Basic Information → App Credentials） | HTTP リクエストの署名検証 |
| `token` | `SLACK_BOT_TOKEN`（xoxb-...、OAuth & Permissions） | API 呼び出し用トークン（単一ワークスペース） |

**または**（マルチワークスペース対応の場合）:

| パラメータ | 値 | 用途 |
|-----------|---|------|
| `signing_secret` | 上記と同じ | 署名検証 |
| `authorize` | カスタム認可関数 | ワークスペースごとにトークンを動的解決 |
| `process_before_response` | `True` | FaaS（Lambda）環境で必須 |

#### 推奨設定値（用途に応じて追加）

| パラメータ | 値 | 用途・推奨理由 |
|-----------|---|-------------|
| `oauth_settings` | `OAuthSettings(...)` | OAuth フローを Bolt に自動処理させたい場合 |
| `installation_store` | DB/S3 実装 | インストール情報をクラウドストレージに保存する場合 |
| `ignoring_self_assistant_message_events_enabled` | `False` | AI アシスタントでボット自身のメッセージを処理する場合 |

---

## 調査アプローチ

1. `docs/tools/bolt-python/concepts/lazy-listeners.md` で FaaS/Lambda の公式推奨コードを確認
2. `docs/tools/bolt-python/concepts/adapters.md` でアダプタパターン（Flask/Lambda）を確認
3. `docs/tools/bolt-python/creating-an-app.md` で HTTP/Socket Mode 両方の基本的な App() 初期化例を確認
4. `docs/tools/bolt-python/concepts/authorization.md` でマルチワークスペース対応の authorize パターンを確認
5. `docs/tools/bolt-python/concepts/authenticating-oauth.md` で OAuth 設定の全パラメータを確認
6. 既存ログ（0051、0053、0039）で過去の調査結果を参照

---

## 問題・疑問点

- `signing_secret` を省略したとき環境変数 `SLACK_SIGNING_SECRET` から自動読み込みされる挙動は公式ドキュメントの lazy-listener 例から推測している。明示的なドキュメント記述は確認できず（GitHub のソースコードで確認するとより確実）。
- Enterprise Search がオーグ対応（マルチワークスペース）である場合、`token` 単一トークンで対応できるかは `authorize` 関数の実装次第。オーグレベルのトークン管理の詳細は別途確認が必要。
- `App()` の全パラメータの完全なリファレンスはドキュメント上に存在しない（GitHub の `slack_bolt/app/app.py` ソースコードを確認する必要がある）。
