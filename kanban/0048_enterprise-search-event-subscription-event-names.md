# Enterprise Search における Event Subscription イベント名と区別方法

## 知りたいこと

Enterprise SearchにおけるEvent Subscriptionでのイベント名や区別方法。

## 目的

Event Subscriptionを動かすため、何をもってEnterprise SearchのSearchなのかを区別しているのかを知りたい。

## 調査サマリー

### 購読すべきイベント

Enterprise Search の実装に必要な `bot_events` は2つ:

| イベント名 | 用途 |
|---|---|
| `function_executed` | ユーザーが検索実行 or 検索フィルタ変更時に発火（検索の本体） |
| `entity_details_requested` | Work Object のアンフールクリック・フレックスペインリフレッシュ時（Work Objects サポート用、検索本体とは別） |

### 「Enterprise Search の Search」を区別する仕組み

`function_executed` は Enterprise Search 専用のイベント名ではなく、**ワークフローのカスタムステップと共通のイベント**。

区別の核心は **`function.callback_id`**:

1. app manifest の `features.search.search_function_callback_id` に検索関数の `callback_id` を登録する
2. ユーザーが検索すると、Slack はその `callback_id` を含む `function_executed` イベントを送る
3. Bolt では `@app.function("callback_id")` デコレータでその `callback_id` 専用のハンドラを登録するため、自動でルーティングされる

```python
# この関数は callback_id="id123456" の function_executed イベントのみ受け取る
@app.function("id123456", auto_acknowledge=False, ack_timeout=10)
def handle_search(inputs, complete, fail, ack):
    query = inputs["query"]      # 検索クエリ
    filters = inputs.get("filters", {})  # フィルタ
    # 検索処理...
    complete(outputs={"search_results": [...]})
    ack()
```

### 検索関数の inputs

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `query` | string | 必須 | 検索クエリ（Slack が解析・正規化済み） |
| `filters` | object | 任意 | 選択されたフィルタのキー・バリューペア |
| （任意名） | `slack#/types/user_context` | 任意 | 検索実行ユーザーのコンテキスト情報 |

## 完了サマリー

- Enterprise Search の検索呼び出しは `function_executed` イベント（ワークフロー共通）で届く
- 「Enterprise Search の Search かどうか」は `function.callback_id` で区別する（Bolt は `@app.function("callback_id")` で自動ルーティング）
- manifest の `features.search.search_function_callback_id` に登録した `callback_id` と一致する `function_executed` のみが検索ハンドラに届く
- 同期処理 + 10 秒タイムアウト設定（`auto_acknowledge=False, ack_timeout=10`）が Enterprise Search では必須
