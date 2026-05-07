# Python 実装における型アノテーション付きサンプル（0070 更問い）

## 調査情報

- タスクファイル: `kanban/0071_python-type-annotations-for-search-args.md`
- 調査日: 2026-05-07

## 調査ファイル一覧

- `kanban/0070_manifest-and-impl-without-link-unfurl.md`
- `kanban/0060_bolt-python-search-function-argument-types.md`
- `logs/0060_bolt-python-search-function-argument-types.md`
- `docs/tools/bolt-python/reference/index.md`（`Args` クラス定義部分）

## 調査アプローチ

1. 0070の kanban サマリーから型アノテーションが未付与のハンドラーを特定
2. 0060 のログから既知の型情報（`Ack`, `Complete`, `Fail`, `inputs: dict`）を確認
3. `docs/tools/bolt-python/reference/index.md` の `Args` クラス定義から残りの型（`body`, `client`, `logger`）を確認
4. インポート形式を `slack_sdk` のチュートリアル例から確認

## 調査結果

### 0070 の3ハンドラーの引数一覧

0070で提示した実装には3つのハンドラーがある。型アノテーションが不完全だった2・3番目を中心に調査した。

| ハンドラー | 引数 | 型アノテーション状況（0070時点） |
|---|---|---|
| `handle_search` | `ack, inputs, complete, fail` | 0060で確認済み（全て付与）|
| `handle_entity_details` | `body, client, logger` | 型なし |
| `handle_close_issue` | `ack, body, client, logger` | 型なし |

### `Args` クラスから確認した各引数の型

`docs/tools/bolt-python/reference/index.md` 行3152 の `Args` クラス定義より:

```python
class Args:
    client: WebClient
    """`slack_sdk.web.WebClient` instance with a valid token"""
    logger: Logger
    """Logger instance"""
    context: BoltContext
    """Context data associated with the incoming request"""
    body: Dict[str, Any]
    """Parsed request body data"""
    event: Optional[Dict[str, Any]]
    """An alias for payload in an `@app.event` listener"""
    action: Optional[Dict[str, Any]]
    """An alias for payload in an `@app.action` listener"""
    ack: Ack
    """`ack()` utility function"""
    complete: Complete
    """`complete()` utility function"""
    fail: Fail
    """`fail()` utility function"""
```

`__init__` シグネチャ（行3247）:
```python
def __init__(
    self,
    *,
    logger: logging.Logger,
    client: WebClient,
    ...
    context: BoltContext,
    body: Dict[str, Any],
    ...
    event: Optional[Dict[str, Any]] = None,
    action: Optional[Dict[str, Any]] = None,
    ack: Ack,
    complete: Complete,
    fail: Fail,
    ...
):
```

### 型一覧とインポート元

| 引数 | 型 | インポート元 |
|------|-----|-------------|
| `ack` | `Ack` | `from slack_bolt import Ack` |
| `complete` | `Complete` | `from slack_bolt import Complete` |
| `fail` | `Fail` | `from slack_bolt import Fail` |
| `inputs` | `dict` | Python組み込み型 |
| `body` | `Dict[str, Any]` | `from typing import Any, Dict` |
| `client` | `WebClient` | `from slack_sdk import WebClient` |
| `logger` | `logging.Logger` | `import logging` |
| `event`（ペイロード alias） | `Optional[Dict[str, Any]]` | `from typing import Any, Dict, Optional` |
| `action`（ペイロード alias） | `Optional[Dict[str, Any]]` | `from typing import Any, Dict, Optional` |

#### `WebClient` のインポート形式

`docs/tools/bolt-python/reference/index.md` 行3182:
```
var client : slack_sdk.web.client.WebClient
```

完全修飾名は `slack_sdk.web.client.WebClient` だが、インポートは短い形式が一般的:
- `from slack_sdk import WebClient`（推奨・チュートリアルで多用）
- `from slack_sdk.web import WebClient`（やや詳細な形式）

0060 のログに記載のチュートリアル例（`ai-chatbot`）でも:
```python
from slack_sdk import WebClient
```

#### `logging.Logger` vs `Logger`

ドキュメント内での使い分け:
- `from logging import Logger` → `logger: Logger`
- `import logging` → `logger: logging.Logger`

両方とも同じ型。`import logging` を使う `logging.Logger` 形式が `Args` クラスの `__init__` では採用されている。

#### Python 3.9+ の場合

Python 3.9 以降は `typing.Dict` の代わりに組み込み `dict` が使える:
- `body: Dict[str, Any]` → `body: dict[str, Any]`（Python 3.9+）

## 型アノテーション付き完全サンプル（0070ベース）

### インポートセクション

```python
import logging
from typing import Any, Dict

from slack_bolt import Ack, App, Complete, Fail
from slack_sdk import WebClient
```

### 1. 検索ハンドラー（`function_executed`）

```python
@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack: Ack, inputs: dict, complete: Complete, fail: Fail) -> None:
    try:
        query = inputs.get("query", "")
        results = my_system.search(query)
        search_results = [
            {
                "external_ref": {"id": r["id"], "type": "document"},
                "title": r["title"],
                "description": r["summary"],
                "link": r["url"],
                "date_updated": r["updated_at"],
                "content": r.get("full_text"),
            }
            for r in results[:50]
        ]
        complete(outputs={"search_results": search_results})
    except Exception as e:
        fail(f"Search failed: {e}")
    finally:
        ack()
```

### 2. フレックスペインハンドラー（`entity_details_requested`）

```python
@app.event("entity_details_requested")
def handle_entity_details(
    body: Dict[str, Any],
    client: WebClient,
    logger: logging.Logger,
) -> None:
    event = body["event"]
    trigger_id = event["trigger_id"]
    entity_id = event.get("external_ref", {}).get("id")
    entity_url = event.get("entity_url")
    item = my_system.get_item(entity_id)
    metadata = {
        "entity_type": "slack#/entities/task",
        "url": entity_url,
        "external_ref": {"id": entity_id},
        "entity_payload": {
            "attributes": {"title": {"text": item["title"]}},
            "fields": {
                "status": {"value": item["status"], "tag_color": "green"},
                "description": {"value": item["body"], "format": "markdown"},
            },
            "actions": {
                "primary_actions": [
                    {
                        "text": "Close Issue",
                        "action_id": "close_issue",
                        "style": "danger",
                        "value": entity_id,
                    }
                ]
            },
        },
    }
    client.entity_presentDetails(trigger_id=trigger_id, metadata=metadata)
```

### 3. アクションハンドラー（`block_actions`）

```python
@app.action("close_issue")
def handle_close_issue(
    ack: Ack,
    body: Dict[str, Any],
    client: WebClient,
    logger: logging.Logger,
) -> None:
    ack()
    entity_id = body.get("container", {}).get("external_ref", {}).get("id")
    trigger_id = body.get("trigger_id")
    my_system.close(entity_id)
    client.entity_presentDetails(
        trigger_id=trigger_id,
        metadata={"entity_type": "slack#/entities/task", ...},
    )
```

### Python 3.9+ 版（`typing` 不要）

Python 3.9 以降は `Dict` を小文字 `dict` に置き換えられる:

```python
import logging
from slack_bolt import Ack, Complete, Fail
from slack_sdk import WebClient

@app.event("entity_details_requested")
def handle_entity_details(
    body: dict[str, Any],
    client: WebClient,
    logger: logging.Logger,
) -> None:
    ...

@app.action("close_issue")
def handle_close_issue(
    ack: Ack,
    body: dict[str, Any],
    client: WebClient,
    logger: logging.Logger,
) -> None:
    ...
```

ただし `Any` は Python 3.11 まで `typing.Any` が必要（3.12 以降は `builtins` に追加）。

## 問題・疑問点

- `event` ペイロードを直接使う場合は `event: Optional[Dict[str, Any]]` を引数に追加することもできる（`body["event"]` の代わりに `event` を直接受け取る）
- `logger` を使う場合は引数に含めるが、使わない場合は省略しても Bolt は問題なく動作する（引数名によるDI）

## 会話内容

ユーザーからの要求: 0070の更問いとして、Python実装において関数の引数について型アノテーションを付けたサンプルが欲しい。
目的: 実際に実装する際に型アノテーションを付けるので何を付けるべきか知りたい。

0070では3ハンドラーのうち `handle_search` のみ型アノテーション付きで示されていた（0060参照）。
残りの `handle_entity_details` と `handle_close_issue` の引数 `body: Dict[str, Any]`, `client: WebClient`, `logger: logging.Logger`, `ack: Ack` を Bolt Python reference の `Args` クラス定義から確認した。
