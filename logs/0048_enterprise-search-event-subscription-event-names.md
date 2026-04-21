# ログ: Enterprise Search における Event Subscription イベント名と区別方法

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/reference/events.md`
- `docs/reference/events/function_executed.md`
- `docs/reference/events/entity_details_requested.md`
- `docs/tools/bolt-python/concepts/custom-steps.md`
- `docs/tools/bolt-python/concepts/custom-steps-dynamic-options.md`
- `docs/tools/bolt-python/concepts/adding-agent-features.md`

---

## 調査アプローチ

1. `docs/enterprise-search/developing-apps-with-search-features.md` を起点として、Event Subscription の設定を確認
2. `docs/reference/events.md` でイベント一覧を確認し、Enterprise Search 関連イベントを特定
3. `docs/reference/events/function_executed.md` と `entity_details_requested.md` でペイロード構造を確認
4. `docs/tools/bolt-python/concepts/custom-steps.md` で Bolt での `callback_id` を使ったルーティング方法を確認

---

## 調査結果

### 1. Enterprise Search で購読すべきイベント

`docs/enterprise-search/developing-apps-with-search-features.md` (行 40-47) によると、
Enterprise Search を実装するには app manifest の `event_subscriptions.bot_events` に以下の2つのイベントを追加する必要がある:

```json
"event_subscriptions": {
    "bot_events": [
        "function_executed",
        "entity_details_requested"
    ]
}
```

- **`function_executed`**: ユーザーが検索を実行したとき（および検索フィルタを変更したとき）に発火する
- **`entity_details_requested`**: ユーザーが Work Object のアンフールをクリックしたとき、またはフレックスペインをリフレッシュしたときに発火する

`entity_details_requested` は Work Objects のサポートに関するものなので、**純粋な Enterprise Search (検索呼び出し) は `function_executed` イベント1本のみ**で動く。

---

### 2. 「Enterprise Search の Search」を区別する仕組み

#### 区別の核心: `callback_id`

`function_executed` イベントは Enterprise Search 専用の新しいイベント名ではなく、**ワークフローのカスタムステップと共通のイベント**である。
Enterprise Search かどうかの区別は、**イベントペイロード内の `function.callback_id`** によって行われる。

仕組み:

1. **app manifest の `features.search` ブロック**で、検索関数の `callback_id` を宣言する
   ```json
   "features": {
       "search": {
           "search_function_callback_id": "id123456",
           "search_filters_function_callback_id": "id987654"
       }
   }
   ```

2. **`functions` ブロック**でその `callback_id` に対応する関数定義を記述する（入力: `query`, `filters`, 出力: `search_results`）

3. **Bolt でのハンドラ登録** (`@app.function("callback_id")`) で特定の `callback_id` に対してリスナーを紐付ける
   ```python
   @app.function("id123456")
   def handle_search(inputs, complete, fail):
       query = inputs["query"]
       filters = inputs.get("filters", {})
       # 検索処理...
       complete(outputs={"search_results": [...]})
   ```

4. Slack が `function_executed` イベントを送るとき、ペイロードの `event.function.callback_id` に関数の ID が含まれる
5. Bolt がその `callback_id` でルーティングし、登録されたハンドラのみが呼び出される

#### `function_executed` イベントのペイロード構造 (`docs/reference/events/function_executed.md`)

```json
{
    "event": {
        "type": "function_executed",
        "function": {
            "id": "Fn123456789O",
            "callback_id": "sample_function",   // ← ここで区別
            "title": "Sample function",
            ...
            "input_parameters": [...],
            "output_parameters": [...]
        },
        "inputs": {
            "user_id": "USER12345678"   // Enterprise Search の場合は query, filters など
        },
        "function_execution_id": "Fx1234567O9L",
        "workflow_execution_id": "WxABC123DEF0",
        "bot_access_token": "..."   // ワークフロートークン（検索完了後に無効化される）
    }
}
```

Enterprise Search の検索関数が呼ばれる場合の `inputs` には:
- `query` (string, 必須): ユーザーの検索クエリ（Slack により解析・再フォーマット済み）
- `filters` (object, 任意): ユーザーが選択したフィルタのキー・バリューペア
- ユーザーコンテキスト用パラメータ: `slack#/types/user_context` 型の任意名パラメータ（ユーザー情報）

---

### 3. 検索フィルタ関数の呼び出しタイミング

`search_filters_function_callback_id` に指定した関数は、ユーザーがアプリを検索ウィンドウで選択して結果を表示するときに呼ばれる。
同一の検索コンテキスト内では、一度取得されたフィルタはキャッシュされ、再呼び出しは行われない。

---

### 4. `entity_details_requested` イベントのペイロード (`docs/reference/events/entity_details_requested.md`)

```json
{
    "event": {
        "type": "entity_details_requested",
        "user": "U0123456",
        "external_ref": {
            "id": "123",
            "type": "my-type"
        },
        "entity_url": "https://example.com/document/123",
        "link": {
            "url": "https://example.com/document/123",
            "domain": "example.com"
        },
        "app_unfurl_url": "https://example.com/document/123?myquery=param",
        "event_ts": "...",
        "trigger_id": "...",
        "user_locale": "en-US",
        "channel": "C123ABC456",
        "message_ts": "...",
        "thread_ts": "..."
    }
}
```

このイベントは Work Objects のフレックスペイン表示時専用。Enterprise Search の検索呼び出しとは別物。

---

### 5. 検索処理の同期ハンドリング要件

`docs/enterprise-search/developing-apps-with-search-features.md` (行 293-307) より:

- Enterprise Search は **同期的なハンドリング**が必要
- アプリは `functions.completeSuccess` または `functions.completeError` を呼んでから `ack()` を返す
- **完了まで最大 10 秒**（デフォルト 3 秒から延長するために Bolt で `ack_timeout=10` を設定する）

Bolt for Python での設定:
```python
@app.function("search_callback_id", auto_acknowledge=False, ack_timeout=10)
def handle_search(inputs, complete, fail, ack):
    # 検索処理
    complete(outputs={"search_results": [...]})
    ack()
```

---

### 6. イベント一覧 (`docs/reference/events.md`) での Enterprise Search 関連イベント

全イベント一覧の中で Enterprise Search に直接関係するのは:
- `function_executed`: カスタム関数がワークフローステップとして実行されたとき（Enterprise Search の検索呼び出しも含む）
- `entity_details_requested`: Work Object のアンフールクリック・フレックスペインリフレッシュ時

---

## 判断・意思決定

- `function_executed` というイベント名自体は Enterprise Search に限定されたものではなく、**ワークフロー全体の汎用イベント**である
- 「何をもって Enterprise Search の Search なのか」を区別するのは **`function.callback_id`** の一致であり、これは Bolt フレームワークが自動でルーティングする
- `@app.function("callback_id")` デコレータで登録された関数は、対応する `callback_id` を持つ `function_executed` イベントのみを受け取る

---

## 問題・疑問点

- `function_executed` イベントのペイロードの `bot_access_token` はワークフロートークンであり、`complete()`/`fail()` 呼び出し後に無効化される。ボットトークン (`xoxb-`) は引き続き使用可能。
- 生の `app.event("function_executed")` でリスナーを登録した場合、全 `function_executed` イベント（Enterprise Search も一般ワークフローも）を受け取ることになる。`app.function("callback_id")` を使うことで特定の callback_id に絞れる。
