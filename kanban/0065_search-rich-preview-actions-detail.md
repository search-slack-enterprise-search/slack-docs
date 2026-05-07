# 検索→リッチプレビュー→アクション の実装詳細

## 知りたいこと

0064の更問い。`検索 -> リッチプレビュー -> アクション` の詳細。どう実装して何ができるのか

## 目的

更に詳しく知りたい

## 調査サマリー

### 全体フロー

```
ユーザー検索
  → function_executed イベント（inputs.query 等を含む）
  → functions.completeSuccess で search_results を返す（10秒以内）
  → ユーザーが検索結果をクリック
  → entity_details_requested イベント（trigger_id, external_ref 等を含む）
  → entity.presentDetails API で entity_payload を返す（flexpane 表示）
  → ユーザーがアクションボタンをクリック
  → block_actions ペイロード（container.entity_url, external_ref 等を含む）
  → 外部システム操作 → entity.presentDetails で flexpane 更新
```

### 実装の要点

**①検索関数（Bolt Python）**
```python
@app.function("my_search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(inputs, complete, fail):
    results = external_system.search(inputs["query"])
    complete(outputs={"search_results": [
        {"external_ref": {"id": item["id"]}, "title": ..., "description": ...,
         "link": ..., "date_updated": "YYYY-MM-DD"}
        for item in results[:50]
    ]})
```
- `auto_acknowledge=False, ack_timeout=10` が必須
- `external_ref.id` は Work Objects と同じ値を使う

**②flexpane（entity_details_requested ハンドラー）**
```python
@app.event("entity_details_requested")
def handle_flexpane(body, client):
    event = body["event"]
    entity_id = event["external_ref"]["id"]  # Enterprise Search 経由では保証されない場合あり
    client.entity_presentDetails(
        trigger_id=event["trigger_id"],
        metadata={"entity_type": "slack#/entities/task", "entity_payload": {..., "actions": {...}}}
    )
```
- Enterprise Search から開いた場合 `channel`/`message_ts`/`thread_ts` は提供されない

**③アクション処理（block_actions ハンドラー）**
```python
@app.action("close_issue")
def handle_action(ack, body, client):
    ack()  # 3秒以内
    entity_id = body["container"]["external_ref"]["id"]
    # 外部システム操作 → entity.presentDetails で flexpane 更新
    client.entity_presentDetails(trigger_id=body["trigger_id"], metadata={...更新後の状態...})
```
- `container.type == "message_attachment"`: unfurl からのアクション
- `container.type == "entity_detail"`: flexpane からのアクション

### 必要な設定

| 種別 | 設定 |
|---|---|
| Bot スコープ | `links:read`, `links:write` |
| Bot Events | `function_executed`, `entity_details_requested` |
| Interactivity | Request URL（block_actions 受信用） |
| App Manifest | `org_deploy_enabled: true`, `function_runtime: remote` |
| App Manifest | `features.search.search_function_callback_id` |
| App Settings | Work Object Previews を有効化 |

### 詳細ログ

`logs/0065_search-rich-preview-actions-detail.md`

## 完了サマリー

「検索→リッチプレビュー→アクション」フローの実装詳細を確認した。検索関数（`function_executed`）・flexpane（`entity_details_requested` + `entity.presentDetails`）・アクション（`block_actions`）の3つのハンドラーを実装することで完全なフローが実現できる。`external_ref.id` の一致・`auto_acknowledge=False, ack_timeout=10`・Interactivity URL の設定が特に重要な実装ポイント。
