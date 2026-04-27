# Bolt Python Enterprise Search関数の引数型

## 知りたいこと

Boltフレームワーク (Python)でEnterprise SearchのSearch用の関数を書くときの、各引数の型はなに？

## 目的

引数として `ack`, `complete`, `fail`, `inputs` があるようだがそれぞれの型を知りたい。

## 調査サマリー

全4引数の型は `slack_bolt` からインポートする専用クラスと Python 標準型。

| 引数 | 型 | インポート元 |
|------|-----|-------------|
| `ack` | `Ack` | `slack_bolt` |
| `complete` | `Complete` | `slack_bolt` |
| `fail` | `Fail` | `slack_bolt` |
| `inputs` | `dict` | Python組み込み型 |

```python
from slack_bolt import Complete, Fail, Ack

@app.function("search_callback_id", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack: Ack, inputs: dict, complete: Complete, fail: Fail):
    try:
        query = inputs["query"]
        complete(outputs={"search_results": [...]})
    except Exception as e:
        fail(f"Search failed: {e}")
    finally:
        ack()
```

- `complete(outputs: dict)` — `functions.completeSuccess` を内部呼び出し
- `fail(error: str)` — `functions.completeError` を内部呼び出し
- Enterprise Search では `auto_acknowledge=False` + `ack_timeout=10` を設定し、`complete`/`fail` 呼び出し後に `ack()` を呼ぶ

## 完了サマリー

`ack: Ack`, `complete: Complete`, `fail: Fail` はすべて `slack_bolt` からインポート。`inputs: dict` はPython標準の辞書型。ドキュメント内の複数コード例（ai-chatbot チュートリアル、custom-steps ガイド）で型アノテーション付きの実例を確認した。
