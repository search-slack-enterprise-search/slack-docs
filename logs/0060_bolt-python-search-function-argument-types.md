# Bolt Python Enterprise Search関数の引数型

## 調査情報

- タスクファイル: `kanban/0060_bolt-python-search-function-argument-types.md`
- 調査日: 2026-04-27

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/tools/bolt-python/concepts/custom-steps.md`
- `docs/tools/bolt-python/concepts/custom-steps-dynamic-options.md`
- `docs/tools/bolt-python/concepts/acknowledge.md`
- `docs/tools/bolt-python/concepts/adding-agent-features.md`
- `docs/tools/bolt-python/tutorial/ai-chatbot/index.md`
- `docs/tools/bolt-python/tutorial/custom-steps.md`
- `docs/tools/bolt-python/tutorial/custom-steps-workflow-builder-existing/index.md`
- `docs/tools/bolt-python/tutorial/custom-steps-workflow-builder-new/index.md`

## 調査アプローチ

1. `enterprise-search/developing-apps-with-search-features.md` でBolt for Pythonの基本的な使い方を確認
2. `bolt-python/concepts/custom-steps.md` でカスタムステップ関数の引数型を確認
3. `bolt-python/tutorial/ai-chatbot/index.md` でインポート元を含む完全な型アノテーション例を発見
4. `bolt-python/concepts/custom-steps-dynamic-options.md` で追加の型使用例を確認

## 調査結果

### 結論: 4つの引数の型

| 引数 | 型 | インポート元 |
|------|-----|-------------|
| `ack` | `Ack` | `slack_bolt` |
| `complete` | `Complete` | `slack_bolt` |
| `fail` | `Fail` | `slack_bolt` |
| `inputs` | `dict` | Python組み込み型 |

### インポート文

```python
from slack_bolt import Complete, Fail, Ack
```

### 詳細: 各引数の役割と使い方

#### `ack: Ack`
- Slackへのリクエスト受信確認を行う関数型
- `ack()` を呼び出すことで、Slackにイベントを受け取ったことを通知する
- Enterprise Search（`auto_acknowledge=False`設定時）では、`complete()`/`fail()` 呼び出し後に `ack()` を呼ぶ
- `docs/tools/bolt-python/concepts/acknowledge.md` 参照

#### `complete: Complete`
- カスタムステップの**成功**を通知する関数型
- 呼び出し方: `complete(outputs: dict)` または `complete({"key": "value"})` のように `dict` を引数に取る
- 内部的に `functions.completeSuccess` API を呼び出す
- 呼び出すと提供されたワークフロートークンは無効化される（ボットトークンは引き続き使用可能）

#### `fail: Fail`
- カスタムステップの**失敗**を通知する関数型
- 呼び出し方: `fail(error: str)` のように `str` を引数に取る
- エラーメッセージは検索ページでユーザーに表示される（例: 認証エラーの場合はリンク付きのメッセージ）
- 内部的に `functions.completeError` API を呼び出す

#### `inputs: dict`
- 関数実行時に渡される入力パラメータを格納したPython標準の `dict`
- Enterprise Search の検索関数では以下のキーを含む:
  - `query` (str): ユーザーの検索クエリ文字列
  - `filters` (dict, optional): ユーザーが選択したフィルタのキーバリューペア
  - `*` (user_context, optional): `slack#/types/user_context` 型のユーザーコンテキスト

### ドキュメントに記載された型アノテーション例

**`docs/tools/bolt-python/tutorial/ai-chatbot/index.md`** (行176):

```python
from slack_bolt import Complete, Fail, Ack
from slack_sdk import WebClient

def handle_summary_function_callback(
    ack: Ack, inputs: dict, fail: Fail, logger: Logger, client: WebClient, complete: Complete):
    ack()
    try:
        user_context = inputs["user_context"]
        channel_id = inputs["channel_id"]
        history = client.conversations_history(channel=channel_id, limit=10)["messages"]
        conversation = parse_conversation(history)
        summary = get_provider_response(user_context["id"], SUMMARIZE_CHANNEL_WORKFLOW, conversation)
        complete({"user_context": user_context, "response": summary})
    except Exception as e:
        logger.exception(e)
        fail(e)
```

**`docs/tools/bolt-python/concepts/custom-steps.md`** (行15):

```python
@app.function("sample_custom_step")
def sample_step_callback(inputs: dict, fail: Fail, complete: Complete):
    try:
        message = inputs["message"]
        complete(
            outputs={
                "message": f":wave: You submitted the following message: \n\n>{message}"
            }
        )
    except Exception as e:
        fail(f"Failed to handle a custom step request (error: {e})")
        raise e
```

**`docs/tools/bolt-python/concepts/custom-steps-dynamic-options.md`** (行121):

```python
@app.function("get-projects", auto_acknowledge=False)
def handle_get_projects(ack: Ack, complete: Complete):
    try:
        complete(outputs={"options": [...]})
    finally:
        ack()
```

**`docs/tools/bolt-python/tutorial/custom-steps-for-jira/index.md`** (行内):

```python
@app.function("create_issue")
def create_issue_callback(ack: Ack, inputs: dict, fail: Fail, complete: Complete, logger: logging.Logger):
    ack()
    ...
```

### Enterprise Search の場合の特記事項

`docs/enterprise-search/developing-apps-with-search-features.md` より:

> When using Bolt for Python, developers can gain more control over the search function's acknowledgment behavior by setting two key parameters:
> - `auto_acknowledge=False`: This gives developers manual control over invoking `ack()`.
> - `ack_timeout=10`: This extends the default timeout from 3 to 10 seconds.

Enterprise Searchの推奨実装フロー:
1. `function_executed` イベントを受信
2. `complete()` または `fail()` で関数の実行結果をSlackに通知
3. その後 `ack()` でイベントを確認応答

```python
@app.function("search_function_callback_id", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack: Ack, inputs: dict, complete: Complete, fail: Fail):
    try:
        query = inputs["query"]
        filters = inputs.get("filters", {})
        user_context = inputs.get("user_context")
        # 検索処理
        results = perform_search(query, filters)
        complete(outputs={"search_results": results})
    except Exception as e:
        fail(f"Search failed: {e}")
    finally:
        ack()
```

## 問題・疑問点

- `Ack`, `Complete`, `Fail` の詳細なクラス定義（シグネチャ）はローカルドキュメントには含まれていない。PyPI上の `slack-bolt` パッケージのソースコードを確認することで詳細な型情報が得られる。
- `fail(e)` のように `Exception` オブジェクトをそのまま渡している例もある（`ai-chatbot` チュートリアル）。ドキュメントでは `str` と記述されているが、実際は `Exception` も受け付ける可能性がある。

## 会話内容

ユーザーからの要求: Bolt Python でEnterprise Searchの検索関数を書く際の `ack`, `complete`, `fail`, `inputs` の型を知りたい。

調査を実施し、`from slack_bolt import Complete, Fail, Ack` と `inputs: dict` という結論を得た。
