# handle_search内でのSlack Client利用方法

## 調査情報

- タスクファイル: `kanban/0072_handle-search-slack-client-usage.md`
- 調査日: 2026-05-07

## 調査ファイル一覧

- `kanban/0071_python-type-annotations-for-search-args.md`（前回タスク）
- `logs/0071_python-type-annotations-for-search-args.md`（前回ログ）
- `docs/tools/bolt-python/reference/index.md`（`Args` クラス・`app.function` 定義）
- `docs/tools/bolt-python/concepts/web-api.md`（WebClient の利用方法）
- `docs/tools/bolt-python/concepts/custom-steps.md`（`app.function` リスナーの DI 例）
- `docs/enterprise-search/developing-apps-with-search-features.md`（`user_context` 入力パラメータ）
- `docs/tools/deno-slack-sdk/reference/slack-types.md`（`user_context` 型の定義）
- `docs/tools/python-slack-sdk/reference/web.md`（`users_info` メソッド定義）
- `docs/reference/scopes/users.read.md`（`users:read` スコープ）
- `docs/reference/scopes/users.read.email.md`（`users:read.email` スコープ）

## 調査アプローチ

1. 0071 のログから `handle_search` の引数リストを確認し、`client` が含まれていないことを確認
2. Bolt Python の `Args` クラス定義を確認し、`client` が any listener に DI 可能かを確認
3. `web-api.md` と `custom-steps.md` で WebClient の利用方法を確認
4. Enterprise Search の `user_context` 入力型の仕様を確認
5. `users.info` API のシグネチャと必要スコープを確認

## 調査結果

### 1. `client` は `@app.function` ハンドラーに DI 可能か

**結論: YES**

`docs/tools/bolt-python/reference/index.md` の `Args` クラス定義（行3152）に以下の記述がある:

```
class Args:
    """All the arguments in this class are available in any middleware / listeners.
    You can inject the named variables in the argument list in arbitrary order.
    ...
    """
    client: WebClient
    """`slack_sdk.web.WebClient` instance with a valid token"""
```

**「any middleware / listeners」と明記されている。** `@app.function` はリスナーを登録するメソッドなので、`client: WebClient` は引数として DI 可能。

`app.function` の定義（行966）にも:
```
To learn available arguments for middleware/listeners, see `slack_bolt.kwargs_injection.args`'s API document.
```
と記載されており、`Args` クラスの全引数が利用できることが示されている。

実際のコード例（`@app.action("sample_click")` in `custom-steps.md`）:
```python
@app.action("sample_click")
def handle_sample_click(ack, body, context, client, complete, fail):
    ack()
    client.chat_update(...)
```
このようにアクションリスナーで `client` が使われている。`app.function` でも同様に利用できる。

### 2. DI の使い方

`handle_search` の引数に `client: WebClient` を追加するだけでよい:

```python
from slack_sdk import WebClient
from slack_bolt import Ack, Complete, Fail

@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(
    ack: Ack,
    inputs: dict,
    complete: Complete,
    fail: Fail,
    client: WebClient,  # ← 追加するだけ
) -> None:
    try:
        query = inputs.get("query", "")
        # client はここで使える
        complete(outputs={"search_results": [...]})
    except Exception as e:
        fail(f"Search failed: {e}")
    finally:
        ack()
```

Bolt が引数名でマッチングして自動で注入する。順序は任意。

### 3. 注入される `client` は何のトークンを使うか

`docs/tools/bolt-python/concepts/web-api.md` より:
```
You can call any Web API method using the `WebClient` provided to your Bolt app
as either `app.client` or `client` in middleware/listener arguments
(given that your app has the appropriate scopes).
```

注入される `client` は `App()` 初期化時のトークン（`SLACK_BOT_TOKEN` 環境変数 または `token=` パラメータ）を使う**ボットトークンのクライアント**。

代替として `app.client` をグローバルに使う方法もある:
```python
app = App(token=os.environ["SLACK_BOT_TOKEN"], ...)

@app.function("search_function", ...)
def handle_search(ack, inputs, complete, fail):
    # app.client を直接参照
    user_info = app.client.users_info(user=user_id)
```

### 4. ユーザーのメールアドレスを取得するには

#### 4-1. `user_context` からユーザー ID を取得

Enterprise Search の `handle_search` でユーザー ID を得るには、まずマニフェストに `user_context` 型の入力パラメータを定義する必要がある。

`docs/enterprise-search/developing-apps-with-search-features.md` より:
```
Any additional input parameter with type `slack#/types/user_context`,
regardless of its name, will be set to the `user_context` value of the user executing the search.
```

`docs/tools/deno-slack-sdk/reference/slack-types.md` の `user_context` 型定義:
- `id`: The `user_id` of the person（例: `U123ABC456`）
- `secret`: Slack 内部のハッシュ値（検証用・無視して良い）

**マニフェストへの追加**（`manifest.json` の関数定義内）:
```json
"functions": {
    "search_function": {
        "title": "Search",
        "description": "Search documents",
        "input_parameters": {
            "query": {
                "type": "string",
                "title": "Query",
                "is_required": true
            },
            "user_context": {
                "type": "slack#/types/user_context",
                "title": "User Context",
                "is_required": false
            }
        },
        "output_parameters": {
            "search_results": {
                "type": "slack#/types/search_results",
                "title": "Search Results",
                "is_required": true
            }
        }
    }
}
```

パラメータ名（`user_context`）は何でも良い。型が `slack#/types/user_context` であれば Slack が自動でセットする。

#### 4-2. `users.info` でメールアドレスを取得

Python SDK の `users_info` メソッド（`docs/tools/python-slack-sdk/reference/web.md` 行5963）:
```python
def users_info(self, *, user: str, include_locale: Optional[bool] = None, **kwargs) -> SlackResponse:
    """Gets information about a user."""
    kwargs.update({"user": user, "include_locale": include_locale})
    return self.api_call("users.info", http_verb="GET", params=kwargs)
```

呼び出し方:
```python
user_info_response = client.users_info(user=user_id)
email = user_info_response["user"]["profile"]["email"]
```

#### 4-3. 必要なスコープ

`users.info` でメールアドレスを取得するには**2つのスコープが必要**:

| スコープ | 用途 |
|---|---|
| `users:read` | `users.info` API を呼び出すために必要 |
| `users:read.email` | レスポンスの `email` フィールドにアクセスするために必要 |

`docs/apis/slack-connect/index.md` より:
```
Both the `users:read.email` and `users:read` OAuth scopes are required
to access the `email` field in user objects returned by
`users.info` and `users.list` API methods.
```

`docs/reference/scopes/users.read.email.md` より:
```
This scope must be requested at the same time as `users:read`.
```

**`users:read` だけでは `email` フィールドは返ってこない。** 両方必要。

マニフェストへの追加:
```json
"oauth_config": {
    "scopes": {
        "bot": [
            "...",
            "users:read",
            "users:read.email"
        ]
    }
}
```

### 5. 完全なサンプルコード

```python
import logging
from typing import Any, Dict

from slack_bolt import Ack, Complete, Fail
from slack_sdk import WebClient


@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(
    ack: Ack,
    inputs: dict,
    complete: Complete,
    fail: Fail,
    client: WebClient,
) -> None:
    try:
        query = inputs.get("query", "")

        # user_context からユーザー ID を取得（マニフェストに user_context 型の入力を定義している場合）
        user_context = inputs.get("user_context", {})
        user_id = user_context.get("id") if user_context else None

        # ユーザーのメールアドレスを取得
        email = None
        if user_id:
            user_info_response = client.users_info(user=user_id)
            email = user_info_response["user"]["profile"].get("email")

        # 外部システムの検索（メールを使ってユーザー識別など）
        results = my_system.search(query, user_email=email)
        search_results = [
            {
                "external_ref": {"id": r["id"], "type": "document"},
                "title": r["title"],
                "description": r["summary"],
                "link": r["url"],
                "date_updated": r["updated_at"],
            }
            for r in results[:50]
        ]
        complete(outputs={"search_results": search_results})
    except Exception as e:
        fail(f"Search failed: {e}")
    finally:
        ack()
```

## 問題・疑問点

- Enterprise Search アプリはオーグレベルでインストールされるため、`users.info` 呼び出し時に `team_id` パラメータを指定する必要がある場合がある（クロスワークスペースのユーザー参照時）。`docs/enterprise/developing-for-enterprise-orgs.md` に「foreign user ID」の場合は `users.info` を使う旨の記載あり。
- `user_context` が `None` や存在しない場合（例: キャッシュされた結果や予期しないリクエスト）を適切にハンドリングする必要がある。

## 会話内容

ユーザーからの要求: 0071の更問いとして、`handle_search` の中でSlackのClientを使いたい。ユーザーのメールアドレスを参照したい。どうやってクライアントを生成したらいい？

調査の結論として、クライアントの「生成」は不要であり、Bolt の DI（依存性注入）によって引数に `client: WebClient` を追加するだけで良いことが判明した。
