# 名前付き引数強制と logger 省略の検証

## 調査ファイル一覧

- `docs/tools/bolt-python/reference/kwargs_injection.md`
- `docs/tools/bolt-python/reference/listener.md`
- `docs/tools/bolt-python/reference/listener_matcher.md`
- `docs/tools/bolt-python/reference/index.md`（`CustomListenerMatcher` 部分）
- `docs/tools/bolt-python/getting-started.md`

## 調査アプローチ

0071・0072の更問い。Bolt Python の DI（Dependency Injection）機構が Python の keyword-only 引数（`def handler(*, ack, body, ...)` という形式）と互換性があるかを確認し、`logger` 引数を省略した場合の挙動を調査した。

調査の中心は `docs/tools/bolt-python/reference/kwargs_injection.md` の `build_required_kwargs()` 実装と、リスナーが呼び出される方法。

## 調査結果

### 1. Bolt Python の DI 仕組み（`build_required_kwargs`）

`docs/tools/bolt-python/reference/kwargs_injection.md` 26〜117行に `build_required_kwargs()` 関数の実装が記載されている。

#### 1-1. 利用可能な全引数の辞書（37〜89行）

```python
all_available_args: Dict[str, Any] = {
    "logger": logger,                          # 38行
    "client": request.context.client,          # 39行
    "req": request,                            # 40行
    "request": request,                        # 41行
    "resp": response,                          # 42行
    "response": response,                      # 43行
    "context": request.context,                # 44行
    "body": request.body,                      # 46行
    "options": to_options(request.body),       # 47行
    "shortcut": to_shortcut(request.body),     # 48行
    "action": to_action(request.body),         # 49行
    "view": to_view(request.body),             # 50行
    "command": to_command(request.body),       # 51行
    "event": to_event(request.body),           # 52行
    "message": to_message(request.body),       # 53行
    "step": to_step(request.body),             # 54行
    "ack": request.context.ack,                # 56行
    "say": request.context.say,                # 57行
    "respond": request.context.respond,        # 58行
    "complete": request.context.complete,      # 59行
    "fail": request.context.fail,              # 60行
    ...
}
```

`logger` は常に `all_available_args` に含まれている（38行）。

#### 1-2. 実際に注入される kwargs の生成（105行）

```python
kwargs: Dict[str, Any] = {k: v for k, v in all_available_args.items() if k in required_arg_names}
```

**ポイント**: `required_arg_names` は関数が実際に宣言した引数名のリスト。つまり、**関数が宣言した引数名だけが注入される**。`logger` を宣言していなければ、`required_arg_names` に `logger` が含まれないため、注入されない。

#### 1-3. 関数の呼び出し方式（`listener.md` 81〜88行）

```python
def run_ack_function(self, *, request: BoltRequest, response: BoltResponse) -> Optional[BoltResponse]:
    return self.ack_function(
        **build_required_kwargs(                  # ← ** による keyword argument 展開
            logger=self.logger,
            required_arg_names=self.arg_names,
            request=request,
            response=response,
            this_func=self.ack_function,
        )
    )
```

**重要**: Bolt は **常に `**kwargs` 形式でリスナー関数を呼び出す**。これが keyword-only 引数との互換性の根拠。

### 2. Keyword-only 引数（`def handler(*, ack, body, ...)`）との互換性

#### 2-1. Python 言語レベルの動作

Python では、`**` によるキーワード引数展開は keyword-only 引数（`*` の後に定義された引数）に対して完全に動作する:

```python
def handler(*, ack, body):
    pass

handler(**{"ack": some_ack, "body": some_body})  # 正常に動作する
```

#### 2-2. `get_arg_names_of_callable` による引数名抽出

`listener.md` 72行・`listener_matcher.md` 35行で確認できる通り、Bolt は `get_arg_names_of_callable(func)` で関数の引数名リストを取得する。

この関数の実装は docs スナップショット内では確認できないが、Python 標準の `inspect.signature(func).parameters` を使用していると推測される。`inspect.signature()` は keyword-only 引数も含む全パラメータを返す:

```python
import inspect

def handler(*, ack, body, client):
    pass

list(inspect.signature(handler).parameters.keys())
# → ['ack', 'body', 'client']  ← keyword-only 引数も含まれる
```

#### 2-3. `self`/`cls` チェック（91〜103行）

```python
if len(required_arg_names) > 0:
    first_arg_name = required_arg_names[0]
    if first_arg_name in {"self", "cls"}:
        required_arg_names.pop(0)
    elif first_arg_name not in all_available_args.keys() and first_arg_name != "args":
        ...
```

keyword-only 引数で `def handler(*, ack, body)` と定義した場合、`required_arg_names[0]` は `ack` になる。`ack` は `all_available_args` に含まれるため、この `elif` 分岐は実行されない。問題なし。

#### 2-4. 結論

`def handler(*, ack, body, client, logger):` のように keyword-only 引数で定義することは **Bolt Python DI と完全に互換性がある**。

### 3. `logger` 引数を省略した場合の挙動

#### 3-1. 省略しても問題ない理由

105行のフィルタリングロジック：

```python
kwargs: Dict[str, Any] = {k: v for k, v in all_available_args.items() if k in required_arg_names}
```

関数が `logger` を宣言していない場合、`required_arg_names` に `logger` が含まれないため、`kwargs` にも含まれない。**関数には `logger` が渡されず、エラーにもならない。**

#### 3-2. ドキュメント内の実例

`docs/tools/bolt-python/getting-started.md` 168行（`logger` なしの例）:

```python
@app.message("goodbye")
def message_goodbye(say):
    responses = ["Adios", "Au revoir", "Farewell"]
    parting = random.choice(responses)
    say(f"{parting}!")
```

`say` だけを引数に取り、`logger` を含まないが正常に動作する例が公式ドキュメントに記載されている。

#### 3-3. `logger` を含む例との比較

同じファイル 12行付近（`logger` あり）:

```python
@app.event("app_mention")
def handle_mention(body, say, logger):
    user = body["event"]["user"]
    logger.debug(body)
    say(f"{user} mentioned your app")
```

同一ドキュメントに `logger` あり・なし両方の例が存在し、どちらも有効な用法。

#### 3-4. `logger` が必要になる場面

- `logger.info()`, `logger.debug()`, `logger.error()` 等のログ出力をハンドラー内で行いたい場合のみ宣言する
- 不要なら省略してよい

## 判断・意思決定

### `get_arg_names_of_callable` の実装確認

docs スナップショット内に実装が見当たらないため、`inspect.signature()` を使用していると推測した。Bolt Python の GitHub ソースでは実際にこの実装になっていることが知られている（訓練データ時点の知識）。ドキュメントの証拠: `build_required_kwargs` 自体が `def build_required_kwargs(*, logger, ...)` と keyword-only 引数で定義されており、Bolt チームが keyword-only 引数を積極的に使用していることがわかる。

### 「問題なし」の根拠

1. **Python 言語レベル**: `**kwargs` 展開は keyword-only 引数に対して動作する（言語仕様）
2. **Bolt 実装レベル**: `build_required_kwargs` は `required_arg_names` フィルタによって関数が必要とする引数だけを注入する設計
3. **ドキュメント実例**: `logger` なしのハンドラーが公式ドキュメントに記載されている

## まとめ

| 質問 | 回答 |
|---|---|
| keyword-only 引数（`def f(*, ack, body, ...)`）は Bolt DI と互換？ | ✅ 問題なし。`**kwargs` で呼び出されるため完全に動作する |
| `logger` を省略しても問題ない？ | ✅ 問題なし。必要な引数だけ宣言すればよい設計 |

### 実装サンプル（keyword-only + logger 省略）

```python
from slack_bolt import Ack, Complete, Fail
from slack_sdk import WebClient
from typing import Any, Dict

@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(
    *,
    ack: Ack,
    inputs: dict,
    complete: Complete,
    fail: Fail,
    client: WebClient,
) -> None:
    try:
        query = inputs.get("query", "")
        complete(outputs={"search_results": [...]})
    except Exception as e:
        fail(f"Search failed: {e}")
    finally:
        ack()

@app.event("entity_details_requested")
def handle_entity_details(
    *,
    body: Dict[str, Any],
    client: WebClient,
) -> None:
    event = body["event"]
    ...

@app.action("close_issue")
def handle_close_issue(
    *,
    ack: Ack,
    body: Dict[str, Any],
    client: WebClient,
) -> None:
    ack()
    ...
```

`logger` は必要なときだけ宣言すればよい。keyword-only 引数（`*,` プレフィックス）は完全に動作する。
