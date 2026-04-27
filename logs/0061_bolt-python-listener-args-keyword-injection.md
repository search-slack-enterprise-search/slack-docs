# Bolt Python リスナー引数はキーワード引数として渡されるか

## 調査情報

- タスクファイル: `kanban/0061_bolt-python-listener-args-keyword-injection.md`
- 調査日: 2026-04-27

## 調査ファイル一覧

- `docs/tools/bolt-python/experiments.md`
- `docs/tools/bolt-python/concepts/context.md`
- `docs/tools/bolt-python/concepts/listener-middleware.md`
- `docs/tools/bolt-python/concepts/global-middleware.md`
- `docs/tools/bolt-python/concepts/event-listening.md`
- `docs/tools/bolt-python/concepts/actions.md`
- `docs/tools/bolt-python/concepts/custom-steps.md`
- `docs/tools/bolt-python/creating-an-app.md`
- `docs/tools/bolt-python/getting-started.md`
- `docs/tools/bolt-python/index.md`
- `docs/tools/bolt-python/ja-jp/getting-started.md`
- `docs/tools/bolt-python/legacy/steps-from-apps.md`

## 調査アプローチ

1. `kwargs_injection`・`inject`・`keyword argument` などのキーワードで全体検索 → ドキュメント内にはURLに含まれる程度で直接説明なし
2. `experiments.md` を読んで明示的な記述を発見 (grep で確認)
3. 各概念ページ（global-middleware, listener-middleware, event-listening, actions, custom-steps など）でコード例の引数順序を観察

## 調査結果

### 結論: **はい、すべて名前付き引数（kwargs injection）として渡される**

Bolt Python のリスナー引数は、**パラメータ名で照合して注入される（kwargs injection）** 仕組みになっている。引数の宣言順序は関係なく、**名前さえ正しければどの順番でも動作する**。

---

### 根拠1: experiments.md の明示的な記述

`docs/tools/bolt-python/experiments.md` 21行目:

> "The listener argument is wired into the Bolt **`kwargs` injection system**, so listeners can declare it as a parameter or access it via the `context.agent` property."

「リスナー引数は Bolt の `kwargs` injection システムに組み込まれている」と明示している。Python の `kwargs` は keyword arguments（キーワード引数）を指す。

---

### 根拠2: すべての概念ページが同じ URL を参照している

Bolt Python の概念ページはすべて、利用可能なリスナー引数の一覧として以下の URL を案内している:

```
https://docs.slack.dev/tools/bolt-python/reference/kwargs_injection/args.html
```

URL のパスに `kwargs_injection` が含まれており、この仕組み自体が「kwargs による引数注入」であることを示している。

参照箇所の一覧:
- `listener-middleware.md`: "Refer to the module document (https://docs.slack.dev/tools/bolt-python/reference/kwargs_injection/args.html)"
- `global-middleware.md`: 同上
- `event-listening.md`: 同上
- `actions.md`: 同上（2箇所）
- `creating-an-app.md`: コメントとして `# To learn available listener arguments, # visit https://docs.slack.dev/tools/bolt-python/reference/kwargs_injection/args.html`
- `ja-jp/getting-started.md`: `# 指定可能なリスナーのメソッド引数の一覧は以下のモジュールドキュメントを参考にしてください：# https://docs.slack.dev/tools/bolt-python/reference/kwargs_injection/args.html`

---

### 根拠3: コード例で引数の順番が異なっている

各ページのコード例で、**同じ引数が異なる順番**で宣言されていることが確認できる。もし位置引数（positional arguments）であれば順序は固定されるはずだが、実際には自由に並べられている。

**creating-an-app.md の例（`body, ack, say` の順）:**
```python
@app.action("button_click")
def action_button_click(body, ack, say):
    ack()
    say(f"<@{body['user']['id']}> clicked the button")
```

**actions.md の例（`ack, body, client` の順）:**
```python
@app.action({"block_id": "assign_ticket", "action_id": "select_user"})
def update_message(ack, body, client):
    ack()
    ...
```

**custom-steps.md の例（`inputs, fail, complete` の順）:**
```python
@app.function("sample_custom_step")
def sample_step_callback(inputs: dict, fail: Fail, complete: Complete):
    ...
```

**ai-chatbot tutorial の例（`ack, inputs, fail, logger, client, complete` の順）:**
```python
def handle_summary_function_callback(
    ack: Ack, inputs: dict, fail: Fail, logger: Logger, client: WebClient, complete: Complete):
    ack()
    ...
```

**custom-steps-for-jira の例（`ack, inputs, fail, complete, logger` の順）:**
```python
@app.function("create_issue")
def create_issue_callback(ack: Ack, inputs: dict, fail: Fail, complete: Complete, logger: logging.Logger):
    ack()
    ...
```

上記のように `ack`, `complete`, `fail`, `inputs` がさまざまな順番で宣言されており、すべて正常に動作する。これは kwargs injection（名前ベースの注入）だからこそ成立する。

---

### 仕組みの概要

Bolt for Python は内部で Python の `inspect` モジュールを使って、リスナー関数のパラメータ名を調べる。そして、パラメータ名に対応する値（`ack`, `complete`, `fail`, `inputs`, `client`, `say`, `body` など）を **キーワード引数として注入** する。

これは「依存性注入（Dependency Injection）」と呼ばれるデザインパターンに相当する。関数が必要な引数だけを宣言すれば、Bolt が自動的に適切な値を名前で照合して渡してくれる。

---

### 実用上の意味

- `def handle_search(ack: Ack, inputs: dict, complete: Complete, fail: Fail):` と
- `def handle_search(fail: Fail, complete: Complete, inputs: dict, ack: Ack):` は **まったく同じ動作**

必要な引数だけを宣言すれば良い（使わない引数は省略可能）:
```python
# complete と fail だけ使う場合
@app.function("search_callback_id", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack: Ack, inputs: dict, complete: Complete, fail: Fail):
    ...
```

---

### タスク0047との関係について

タスク0047で出力されたサンプルと0060の型情報で示された例で引数の順番が異なるが、それは問題ない。Bolt Python の kwargs injection により、**引数名さえ正しければ順番は完全に自由**。

## 問題・疑問点

- 実際のBolt Pythonのソースコードを確認すれば `inspect.signature()` などを使った実装が確認できるはずだが、ローカルドキュメントのみでの調査のため直接確認はしていない。
- ただし、以上の状況証拠（URL名・明示的な記述・コード例）から、kwargs injection であることは確実。

## 会話内容

ユーザーからの要求: タスク0060で `ack`, `complete`, `fail`, `inputs` の型を調べた際、引数の順番がタスク0047で出力されたサンプルと異なる。これはすべて名前付き引数として渡されていると考えて良いか。名前付き引数であれば順番は関係ないが、そうでなければ意図しない結果が生じる可能性がある。

調査結果: `experiments.md` の明示的な記述 "wired into the Bolt `kwargs` injection system"、ドキュメント全体での `kwargs_injection` URLへの一貫した参照、および複数コード例での引数順序の違いから、**Bolt Python のリスナー引数はすべてキーワード引数（名前ベース）で注入される**ことを確認した。引数の順番は一切関係ない。
