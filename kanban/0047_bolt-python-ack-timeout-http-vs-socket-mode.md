# Bolt Python で 10 秒 ack タイムアウトを使うための条件（HTTP vs Socket Mode）
## 知りたいこと

0046への更問い。Bolt PythonでもSocket Modeでないと3秒以内での完了が必要か

## 目的

Python実装で10秒をつかうための条件が知りたい。Socket Modeに限定されるのならFaaSではなく、何らかのマシンで動かす必要がある。

## 調査サマリー

**Bolt Python の `ack_timeout=10` は Socket Mode 不要。HTTP モード（Lambda を含む FaaS）でも機能する。**

### 回答

「Bolt Python でも Socket Mode でないと 3 秒以内での完了が必要か？」→ **NO**

Bolt Python では `ack_timeout=10` を設定することで、**HTTP モードでも 10 秒以内の処理**が可能。FaaS（Lambda 等）でも使用できる。

### Bolt Python と Bolt JS の違い

| | HTTP モード | Socket Mode |
|---|---|---|
| **Bolt Python** | `ack_timeout=10` で 10 秒利用可能 ✅ | 同じく 10 秒利用可能 |
| **Bolt JS** | 3 秒以内が必要 ⚠️ | 10 秒以上も可能 ✅ |

→ Bolt JS には `ack_timeout` パラメータがないため、HTTP モードでは 3 秒制約が残る。10 秒が必要なら Socket Mode が必要（Bolt JS ドキュメントに明記）。

### Lambda（FaaS）での Bolt Python 実装

```python
app = App(
    process_before_response=True,  # FaaS 環境で必須
    ...
)

@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack, complete, fail, inputs):
    try:
        complete(outputs={"search_results": ...})
    except Exception as e:
        fail(error=str(e))
    finally:
        ack()  # complete()/fail() の後に呼ぶ
```

| パラメータ | 値 | 理由 |
|---|---|---|
| `process_before_response=True` | App 初期化時 | FaaS では HTTP 応答前に処理を完結させる必要がある |
| `auto_acknowledge=False` | デコレータ | `complete()`/`fail()` の後に `ack()` を呼ぶため |
| `ack_timeout=10` | デコレータ | Bolt 内部タイムアウトを 3 秒→10 秒に延長 |

- Lambda Lazy Listener（`lambda:InvokeFunction`）は **不要**（同期処理なので自己 invoke しない）
- Lambda タイムアウト設定は **15〜30 秒**推奨

### 根拠

1. Enterprise Search ドキュメントで Bolt Python セクションに Socket Mode 要件の言及なし
2. Bolt JS セクションには明示的に「Socket Mode、または 3 秒以内」と書かれている（対照的）
3. 過去調査 `kanban/0039` で Lambda + HTTP モードの動作確認済み

## 完了サマリー

Bolt Python の `ack_timeout=10` は Socket Mode 不要で HTTP モードでも有効であることを確認。FaaS（Lambda）でも `process_before_response=True` + `auto_acknowledge=False` + `ack_timeout=10` の組み合わせで動作する。Bolt JS との非対称性（JS は Socket Mode が必要、Python は不要）が重要ポイント。
