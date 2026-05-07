# Python 実装における型アノテーション付きサンプル（0070 更問い）
## 知りたいこと

0070の更問い。Python実装において関数の引数について型アノテーションを付けたサンプルが欲しい

## 目的

実際に実装する際に型アノテーションを付けるので何を付けるべきか知りたい

## 調査サマリー

0070 の3ハンドラー全引数の型アノテーションを確認した。Bolt Python reference の `Args` クラス定義（`docs/tools/bolt-python/reference/index.md`）から各型を特定。

### インポート

```python
import logging
from typing import Any, Dict  # Python 3.9+ は不要

from slack_bolt import Ack, Complete, Fail
from slack_sdk import WebClient
```

### 引数型一覧

| 引数 | 型 | インポート元 |
|---|---|---|
| `ack` | `Ack` | `slack_bolt` |
| `complete` | `Complete` | `slack_bolt` |
| `fail` | `Fail` | `slack_bolt` |
| `inputs` | `dict` | Python組み込み |
| `body` | `Dict[str, Any]` | `typing` |
| `client` | `WebClient` | `slack_sdk` |
| `logger` | `logging.Logger` | `logging` |

### 型アノテーション付き実装サンプル

```python
@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack: Ack, inputs: dict, complete: Complete, fail: Fail) -> None:
    try:
        query = inputs.get("query", "")
        complete(outputs={"search_results": [...]})
    except Exception as e:
        fail(f"Search failed: {e}")
    finally:
        ack()

@app.event("entity_details_requested")
def handle_entity_details(
    body: Dict[str, Any],
    client: WebClient,
    logger: logging.Logger,
) -> None:
    event = body["event"]
    ...

@app.action("close_issue")
def handle_close_issue(
    ack: Ack,
    body: Dict[str, Any],
    client: WebClient,
    logger: logging.Logger,
) -> None:
    ack()
    ...
```

Python 3.9+ では `Dict[str, Any]` → `dict[str, Any]` に置き換え可能（ただし `Any` は Python 3.12+ まで `typing.Any` が必要）。

## 完了サマリー

0070 の3ハンドラー全引数に型アノテーションを付与したサンプルを確認。`ack: Ack`, `complete: Complete`, `fail: Fail` は `slack_bolt` から、`client: WebClient` は `slack_sdk` から、`body: Dict[str, Any]` は `typing.Dict`、`logger: logging.Logger` は標準 `logging` モジュールを使用。詳細は `logs/0071_python-type-annotations-for-search-args.md` を参照。
