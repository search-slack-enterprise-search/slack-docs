# Bolt Python リスナー引数はキーワード引数として渡されるか

## 知りたいこと

0060の更問い。引数の順番が0047でサンプルを出力してもらった時とは異なる。すべて名前付き引数として渡されていると考えて良いか？

## 目的

名前付き引数であれば順番は関係ないが、そうでないのなら意図しない結果があり得るため。

## 調査サマリー

**結論: はい、すべて名前付き引数（kwargs injection）として渡される。引数の順番は一切関係ない。**

### 根拠

1. **`experiments.md` の明示的な記述** (21行目):
   > "The listener argument is wired into the Bolt **`kwargs` injection system**"

2. **ドキュメント全体で参照するURLに `kwargs_injection` を含む**:
   `https://docs.slack.dev/tools/bolt-python/reference/kwargs_injection/args.html`
   全概念ページが一貫してこのURLを案内している。

3. **コード例で引数が異なる順番で宣言されている**:
   - `def action_button_click(body, ack, say):`
   - `def update_message(ack, body, client):`
   - `def handle_summary_function_callback(ack, inputs, fail, logger, client, complete):`
   
   すべて同じ引数が異なる順序で使われており、それでも正しく動作している。

### 実用上の意味

以下はまったく同じ動作:
```python
def handle_search(ack: Ack, inputs: dict, complete: Complete, fail: Fail): ...
def handle_search(fail: Fail, complete: Complete, inputs: dict, ack: Ack): ...
```

Bolt は `inspect` モジュールでパラメータ名を調べ、名前に対応する値をキーワード引数として注入する。タスク0047と0060でサンプルの引数順が違っていても問題なし。

## 完了サマリー

Bolt Python のリスナー引数は `kwargs` injection システムで名前ベースに注入される。`experiments.md` に明示的な記述あり。引数の順番は完全に自由で、必要な引数だけを宣言すれば良い。
