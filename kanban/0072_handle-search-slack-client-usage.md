# handle_search内でのSlack Client利用方法

## 知りたいこと

0071の更問い。handle_searchの中でSlackのClientを使いたい。どうしたらいい？

## 目的

SlackのClientを使用してユーザーのメールアドレスを参照したい。どうやってクライアントを生成したらいい？

## 調査サマリー

`client: WebClient` は `@app.function` ハンドラーの引数に追加するだけで Bolt の DI により自動注入される。**クライアントを自分で生成する必要はない。**

### client の DI 方法

`docs/tools/bolt-python/reference/index.md` の `Args` クラスが「**any middleware / listeners**」で利用可能と明記しており、`@app.function` も対象。

```python
from slack_sdk import WebClient
from slack_bolt import Ack, Complete, Fail

@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(
    ack: Ack,
    inputs: dict,
    complete: Complete,
    fail: Fail,
    client: WebClient,  # 引数に追加するだけ（ボットトークンのクライアント）
) -> None:
    ...
```

### ユーザーのメールアドレスを取得する方法

#### ステップ1: マニフェストに `user_context` 型の入力パラメータを追加

```json
"input_parameters": {
    "query": {"type": "string", "is_required": true},
    "user_context": {"type": "slack#/types/user_context", "is_required": false}
}
```

`user_context` 型のパラメータは（名前に関わらず）Slack が自動でセット。`inputs["user_context"]["id"]` でユーザー ID を取得できる。

#### ステップ2: `users.info` でメールアドレスを取得

```python
user_id = inputs.get("user_context", {}).get("id")
if user_id:
    resp = client.users_info(user=user_id)
    email = resp["user"]["profile"]["email"]
```

#### ステップ3: 必要なスコープ

| スコープ | 用途 |
|---|---|
| `users:read` | `users.info` API の呼び出しに必要 |
| `users:read.email` | レスポンスの `email` フィールド取得に必要（`users:read` と同時に追加必須） |

両スコープをマニフェストの `oauth_config.scopes.bot` に追加すること。

## 完了サマリー

`handle_search` 内での Slack Client 利用は、引数に `client: WebClient` を追加するだけで Bolt DI が自動注入する。ユーザーのメールアドレス参照には、①マニフェストに `slack#/types/user_context` 型入力追加 → ②`client.users_info(user=user_id)` 呼び出し → ③`users:read` と `users:read.email` スコープの両方が必要。詳細は `logs/0072_handle-search-slack-client-usage.md` を参照。
