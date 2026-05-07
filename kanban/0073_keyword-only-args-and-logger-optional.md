# 名前付き引数強制と logger 省略の検証

## 知りたいこと

0071と0072の更問い。関数の引数は名前付き引数を強制して問題ないのかしりたい。
また、`logger` を引数に入れない場合問題はあるか？

## 目的

原則として関数の引数は名前付き引数を強制している。
そうして問題ないかを知りたい。

## 調査サマリー

Bolt Python の DI 機構と keyword-only 引数（`def handler(*, ack, body, ...)`）の互換性、および `logger` 省略時の挙動を確認した。

### keyword-only 引数は問題なし

`docs/tools/bolt-python/reference/kwargs_injection.md` の `build_required_kwargs()` 実装（105行）より：

```python
kwargs: Dict[str, Any] = {k: v for k, v in all_available_args.items() if k in required_arg_names}
```

Bolt はリスナー関数を **常に `**kwargs` 形式（キーワード引数展開）で呼び出す**（`listener.md` 81〜88行）。Python では `**kwargs` 展開は keyword-only 引数に対して完全に動作するため、`def handler(*, ack, body, client):` という定義は Bolt DI と完全に互換。

### `logger` 省略も問題なし

`required_arg_names` は関数が実際に宣言した引数名のリスト。`logger` を宣言していなければ注入されないだけで、エラーにはならない。公式ドキュメント（`getting-started.md` 168行）にも `logger` なしのハンドラー例が記載されている：

```python
@app.message("goodbye")
def message_goodbye(say):
    say("Farewell!")
```

### 実装サンプル（keyword-only + logger 省略）

```python
@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(
    *,
    ack: Ack,
    inputs: dict,
    complete: Complete,
    fail: Fail,
    client: WebClient,
) -> None:
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

`logger` は必要なときだけ宣言すればよい。

## 完了サマリー

keyword-only 引数（`def handler(*, ack, body, ...)`）は Bolt Python DI と完全に互換。理由: Bolt は常に `**kwargs` でリスナーを呼び出すため、Python 言語レベルで keyword-only 引数がそのまま機能する。`logger` 省略も問題なし。必要な引数だけ宣言する設計が Bolt の意図通り。詳細は `logs/0073_keyword-only-args-and-logger-optional.md` を参照。
