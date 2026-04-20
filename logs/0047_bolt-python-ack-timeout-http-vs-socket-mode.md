# Bolt Python で 10 秒 ack タイムアウトを使うための条件（HTTP vs Socket Mode）— 調査ログ

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md` — Enterprise Search 実装ガイド（`ack_timeout=10` の記述）
- `docs/tools/bolt-python/concepts/acknowledge.md` — Bolt Python 標準 ack 仕様（3 秒ルール）
- `docs/tools/bolt-python/concepts/lazy-listeners.md` — FaaS 環境向け遅延リスナー
- `docs/tools/bolt-python/concepts/custom-steps-dynamic-options.md` — `auto_acknowledge=False` の Bolt Python 実装例
- `docs/tools/bolt-python/concepts/socket-mode.md` — Bolt Python の Socket Mode 実装
- `docs/apis/events-api/comparing-http-socket-mode.md` — HTTP vs Socket Mode の比較
- `kanban/0039_enterprise-search-on-aws-lambda.md` — 過去調査（Lambda で動かせるか）
- `logs/0039_enterprise-search-on-aws-lambda.md` — 上記の詳細ログ（参考）

---

## 調査アプローチ

1. `developing-apps-with-search-features.md` の Bolt Python セクション再確認（`ack_timeout=10` の説明文を精査）
2. Bolt Python の `lazy-listeners.md`（FaaS 対応）と `custom-steps-dynamic-options.md`（同期処理）を読んで HTTP モードでの動作を理解
3. `kanban/0039_enterprise-search-on-aws-lambda.md` の過去調査を参照し、実際の Lambda + HTTP モード動作を確認

---

## 調査結果

### 1. `ack_timeout=10` は HTTP モードでも有効か

**結論: YES — Socket Mode は不要。HTTP モードでも `ack_timeout=10` は機能する。**

#### 根拠①: `developing-apps-with-search-features.md` の記述（L313–L330）

Bolt Python セクションには Socket Mode の要件が一切言及されていない:

> "When using Bolt for Python, developers can gain more control over the search function's acknowledgment behavior by setting two key parameters:"
> - `auto_acknowledge=False` — "This gives developers manual control over invoking `ack()`."
> - `ack_timeout=10` — "This extends the default timeout from 3 to 10 seconds."

対照的に、**Bolt JS セクション（L335–L347）** では明示的に Socket Mode に言及している:

> "This is particularly useful when using [Socket Mode], or when you need to handle the `function_executed` event within the **default 3-second timeout**."

→ Bolt JS は Socket Mode を使わなければ「デフォルト 3 秒以内」という制約が残る。Bolt Python は `ack_timeout=10` によって HTTP モードでも 10 秒に延長できる。

#### 根拠②: 過去調査 `kanban/0039_enterprise-search-on-aws-lambda.md`

同タスクで **Lambda（HTTP モード）で Enterprise Search が動作する** ことを既に確認済み。確認された実装パターン:

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(
    process_before_response=True,  # FaaS 環境で必須
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    token=os.environ["SLACK_BOT_TOKEN"],
)

@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack, complete, fail, inputs):
    try:
        results = search_external_data(inputs["query"], inputs.get("filters", {}))
        complete(outputs={"search_results": results})
    except Exception as e:
        fail(error=str(e))
    finally:
        ack()  # complete()/fail() の後に呼ぶ

def lambda_handler(event, context):
    return SlackRequestHandler(app=app).handle(event, context)
```

→ **Lambda + API Gateway / Lambda Function URL（HTTP モード）** で `ack_timeout=10` を使用。Socket Mode は使っていない。

#### 根拠③: `custom-steps-dynamic-options.md` における同期処理パターン

`auto_acknowledge=False` の説明（L114–L122）:

> "In Bolt for Python, you can set `auto_acknowledge=False` on a specific function decorator. This allows you to manually control when the `ack()` event acknowledgement helper function is executed. It flips Bolt to synchronous `function_executed` event handling mode for the specific handler."

この文書は動的オプション（dynamic options）のための同期処理を説明しているが、Socket Mode は不要とされている。Enterprise Search も同じパターン（同期処理）を使う。

#### 根拠④: `lazy-listeners.md` との対比

Lazy Listener（FaaS 向け）は `process_before_response=True` を使い、**3 秒以内**に ack することが必須:

> "set the `process_before_response` flag to `True`. When this flag is true, the Bolt framework holds off sending an HTTP response until all the things in a listener function are done. You need to complete your processing within **3 seconds** or you will run into errors."

Enterprise Search では Lazy Listener パターンは **使わない**。代わりに `ack_timeout=10` で 10 秒のウィンドウを持ち、同期処理してから ack する。

→ `ack_timeout=10` は Bolt が内部的に保持するタイムアウト閾値を 3 秒から 10 秒に延長するパラメータ。Slack 側も Enterprise Search の `function_executed` イベントに対して 10 秒間 HTTP 接続を維持する（Documents: "Your app must complete the function execution within 10 seconds."）。

---

### 2. FaaS（Lambda）での必要設定まとめ

| パラメータ | 値 | 理由 |
|---|---|---|
| `process_before_response` | `True` | FaaS では HTTP レスポンスを返した後にスレッドを実行できないため、処理完了まで HTTP 応答を保持する |
| `auto_acknowledge` | `False` | ack() のタイミングを手動制御し、`complete()`/`fail()` の後に呼ぶため |
| `ack_timeout` | `10` | デフォルト 3 秒から 10 秒に延長（Enterprise Search の上限が 10 秒のため） |

- Lambda のタイムアウト設定は **15〜30 秒**推奨（Bolt の内部処理オーバーヘッド分を見込む）
- Lambda の Lazy Listener のための IAM 権限（`lambda:InvokeFunction`）は **不要**（同期処理なので Lambda 自己 invoke しない）

---

### 3. 結論: ユーザーの元の疑問への回答

**「Bolt Python でも Socket Mode でないと 3 秒以内での完了が必要か？」**

→ **NO。Socket Mode は不要。**

Bolt Python では `ack_timeout=10` を設定することで、HTTP モード（FaaS を含む）でも 10 秒以内の処理が可能。Slack 側が Enterprise Search の `function_executed` イベントに対して 10 秒の HTTP タイムアウトを持つため、`ack_timeout=10` で Bolt 側の閾値もそれに合わせる。

**Bolt JS との違い:**
- Bolt JS: `ack_timeout` パラメータが存在しない → HTTP モードでは 3 秒以内の処理が必要 → 10 秒が必要なら Socket Mode を使う
- Bolt Python: `ack_timeout=10` が利用可能 → HTTP モードでも 10 秒利用可能 → FaaS（Lambda）でも使える

---

## 問題・疑問点

- `ack_timeout=10` が「Slack 側の HTTP タイムアウトを 10 秒に延長している」のか、「Bolt 内部のタイムアウト警告を 10 秒に設定しているだけ」なのかは、ドキュメント上では明示されていない。ただし、過去調査（0039）で Lambda + HTTP モードで動作することを確認済みのため、実用上は問題ない。
- Bolt JS で将来 `ack_timeout` に相当する機能が追加されるかは不明。
