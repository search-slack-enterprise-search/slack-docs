# Link Unfurl なしの manifest.json と Python 実装

## 知りたいこと

0068と0069を統合して、link unfurlを使用しない場合のmanifest.jsonやPythonの実装を詳しく教えてください。

## 目的

link unfurlが必要ないことがわかった。それを抜いた設定を知りたい。

## 調査サマリー

0068（0065/0067 統合）と 0069（link unfurl 詳細調査）を統合し、link unfurl なしの完全な manifest.json と Bolt for Python 実装をまとめた。

### link unfurl なしで不要になるもの

| 種別 | 除外する設定 |
|---|---|
| bot_events | `link_shared` |
| features | `unfurl_domains` |
| scopes | `links:read`, `links:write` |

### 完全な manifest.json（link unfurl なし・URL あり版）

```json
{
  "_metadata": {"major_version": 2, "minor_version": 1},
  "display_information": {
    "name": "My Enterprise Search App",
    "description": "Enterprise Search app for internal data sources",
    "background_color": "#2c2d30"
  },
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "request_url": "https://REPLACE_WITH_YOUR_LAMBDA_URL/slack/events",
      "bot_events": ["function_executed", "entity_details_requested"]
    },
    "interactivity": {
      "is_enabled": true,
      "request_url": "https://REPLACE_WITH_YOUR_LAMBDA_URL/slack/events"
    },
    "app_type": "remote",
    "function_runtime": "remote",
    "socket_mode_enabled": false,
    "token_rotation_enabled": false
  },
  "features": {
    "bot_user": {"display_name": "My Search Bot", "always_online": false},
    "search": {"search_function_callback_id": "search_function"},
    "rich_previews": {
      "is_active": true,
      "entity_types": ["slack#/entities/task"]
    }
  },
  "oauth_config": {
    "scopes": {"bot": ["team:read"]}
  },
  "functions": {
    "search_function": {
      "title": "Search Function",
      "description": "Returns search results from internal data sources",
      "input_parameters": {
        "properties": {
          "query": {"type": "string", "title": "Query"},
          "filters": {"type": "object", "title": "Filters"},
          "user_context": {"type": "slack#/types/user_context", "title": "User Context"}
        },
        "required": ["query"]
      },
      "output_parameters": {
        "properties": {
          "search_results": {"type": "slack#/types/search_results", "title": "Search Results"}
        },
        "required": ["search_results"]
      }
    }
  }
}
```

### Python 実装の3ハンドラー

#### 1. 検索ハンドラー（function_executed）
```python
@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack: Ack, inputs: dict, complete: Complete, fail: Fail):
    try:
        query = inputs.get("query", "")
        # 外部システムから検索結果を取得
        results = my_system.search(query)
        search_results = [
            {
                "external_ref": {"id": r["id"], "type": "document"},
                "title": r["title"],
                "description": r["summary"],
                "link": r["url"],
                "date_updated": r["updated_at"],  # YYYY-MM-DD
                "content": r.get("full_text")
            }
            for r in results[:50]
        ]
        complete(outputs={"search_results": search_results})
    except Exception as e:
        fail(f"Search failed: {e}")
    finally:
        ack()
```

#### 2. フレックスペインハンドラー（entity_details_requested）
```python
@app.event("entity_details_requested")
def handle_entity_details(body, client, logger):
    event = body["event"]
    trigger_id = event["trigger_id"]
    entity_id = event.get("external_ref", {}).get("id")
    entity_url = event.get("entity_url")
    # Enterprise Search から開いた場合 channel/message_ts は None
    item = my_system.get_item(entity_id)
    metadata = {
        "entity_type": "slack#/entities/task",
        "url": entity_url,
        "external_ref": {"id": entity_id},
        "entity_payload": {
            "attributes": {"title": {"text": item["title"]}},
            "fields": {
                "status": {"value": item["status"], "tag_color": "green"},
                "description": {"value": item["body"], "format": "markdown"}
            },
            "actions": {
                "primary_actions": [
                    {"text": "Close Issue", "action_id": "close_issue", "style": "danger", "value": entity_id}
                ]
            }
        }
    }
    client.entity_presentDetails(trigger_id=trigger_id, metadata=metadata)
```

#### 3. アクションハンドラー（block_actions）
```python
@app.action("close_issue")
def handle_close_issue(ack, body, client, logger):
    ack()  # 3秒以内に必須
    entity_id = body.get("container", {}).get("external_ref", {}).get("id")
    trigger_id = body.get("trigger_id")
    my_system.close(entity_id)
    client.entity_presentDetails(trigger_id=trigger_id, metadata={"entity_type": "slack#/entities/task", ...})
```

### 重要ポイント
- `auto_acknowledge=False` + `ack_timeout=10` は Enterprise Search の検索関数に必須
- `complete()` → `ack()` の順序を守ること（`finally` 内で `ack()` を呼ぶのが安全）
- `entity.presentDetails` 用 metadata は `chat.unfurl` の metadata と異なる（`entities` 配列なし、`url` を使用）
- Enterprise Search から開いたフレックスペインでは `channel`/`message_ts` は提供されない
- `features.rich_previews` の追加が Work Objects 有効化に必要

## 完了サマリー

link unfurl なしの Enterprise Search + Work Objects + Actions の完全な manifest.json（URL なし・URL あり両バリアント）と Bolt for Python 実装（検索・フレックスペイン・アクションの3ハンドラー）、フィルター関数の実装例をまとめた。詳細は `logs/0070_manifest-and-impl-without-link-unfurl.md` を参照。
