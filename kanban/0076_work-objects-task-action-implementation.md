# Work Objects Task アクション実装（manifest.json と bolt-python）

## 知りたいこと

Work ObjectsのTaskエンティティを有効にすることができたので、アクションを実装する上でmanifest.jsonとbolt-pythonで何を実装すればいいのかを知りたい

## 目的

アクションを実行できるようにしたい

## 調査サマリー

### manifest.json で必要な追加設定

アクション（`block_actions`）を受け取るためには `settings.interactivity` の設定が必須。

```json
"settings": {
  "interactivity": {
    "is_enabled": true,
    "request_url": "https://LAMBDA_URL/slack/events"
  }
}
```

- Lambda デプロイ前（URL なし）の段階では省略可能
- `event_subscriptions.request_url` と同じ URL でよい（Bolt は1エンドポイントで両方を受け付ける）
- 他の必要設定（`org_deploy_enabled`, `function_executed`, `entity_details_requested`, `rich_previews` 等）は 0070 のサンプルの通り

### アクションの定義（entity.presentDetails の metadata 内）

`entity_payload.actions` フィールドにボタンを定義する:

```python
"actions": {
    "primary_actions": [      # 最大2つ（フッターに表示）
        {
            "text": "Close Task",
            "action_id": "close_task",    # @app.action() でリスンする ID
            "style": "danger",
            "value": item["id"]
        }
    ],
    "overflow_actions": [     # 最大5つ（More actions メニュー）
        {
            "text": "Pin Task",
            "action_id": "pin_task",
            "value": item["id"]
        }
    ]
}
```

### Bolt for Python でのアクションハンドラー

```python
@app.action("close_task")
def handle_close_task(ack, body, client, logger):
    ack()  # 3秒以内に必須

    container = body.get("container", {})
    entity_url = container.get("entity_url")
    entity_id = container.get("external_ref", {}).get("id")
    trigger_id = body.get("trigger_id")
    user_id = body["user"]["id"]

    # 外部システムでアクションを実行
    my_external_system_close_task(entity_id, user_id=user_id)

    # flexpane を最新状態に更新（任意だが推奨）
    client.entity_presentDetails(
        trigger_id=trigger_id,
        metadata={
            "entity_type": "slack#/entities/task",
            "url": entity_url,
            "external_ref": {"id": entity_id},
            "entity_payload": {
                "attributes": {"title": {"text": updated_title}},
                "fields": {"status": {"value": "closed", "tag_color": "gray"}},
                "actions": {
                    "primary_actions": [{
                        "text": "Reopen Task",
                        "action_id": "reopen_task",
                        "style": "primary",
                        "value": entity_id
                    }]
                }
            }
        }
    )
```

### 重要なポイント

- `container.type` が `"message_attachment"` なら unfurl からのアクション、`"entity_detail"` なら flexpane からのアクション
- アクション処理後は自動的にリフレッシュがスケジュールされるが、`entity.presentDetails` を呼ぶと即時反映できる
- `metadata_last_modified` フィールドで更新検知を最適化できる
- Bolt for Python の `@app.action()` は標準機能として今でも利用可能（Work Objects 専用 API の高レベルサポートは "coming soon"）

詳細ログ: `logs/0076_work-objects-task-action-implementation.md`

## 完了サマリー

Work Objects Task アクション実装に必要な設定を確認した。manifest.json では `settings.interactivity`（`is_enabled: true` + `request_url`）の追加が唯一の新規設定。アクションの定義は `entity.presentDetails` の `entity_payload.actions` フィールドで行い、Bolt for Python では `@app.action("action_id")` で各ボタンに対応するハンドラーを実装する。
