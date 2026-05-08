# Work Objects Task アクション実装（manifest.json と bolt-python）

## 調査情報

- タスクファイル: `kanban/0076_work-objects-task-action-implementation.md`
- 調査日: 2026-05-08
- 前提タスク:
  - 0070（link unfurl なし manifest.json + Python 実装）
  - 0075（external_ref type と Work Objects Task エンティティの両立）
  - 0064（Enterprise Search + Work Objects + Interactions の組み合わせ）
  - 0065（検索→リッチプレビュー→アクション 実装詳細）

---

## 調査ファイル一覧

- `docs/messaging/work-objects-implementation.md`（アクション実装の主要ドキュメント）
- `docs/tools/bolt-python/concepts/actions.md`（Bolt Python アクション実装）
- `docs/messaging/work-objects-overview.md`（Work Objects 概要・SDK サポート状況）
- `docs/reference/app-manifest.md`（manifest.json の interactivity フィールド仕様）
- `docs/app-manifests/configuring-apps-with-app-manifests.md`（マニフェスト設定全般）
- `logs/0070_manifest-and-impl-without-link-unfurl.md`（既存 manifest サンプル・完全 Python 実装）
- `logs/0065_search-rich-preview-actions-detail.md`（App Manifest + アクション実装詳細）
- `logs/0055_enterprise-search-manifest-sample.md`（manifest.json サンプル）
- `logs/0075_external-ref-type-for-work-objects-task.md`（Task エンティティの確認）
- `logs/0064_enterprise-search-work-objects-interactions.md`（インタラクション種類）

---

## 調査アプローチ

1. 前提タスク（0070・0075・0064・0065）のログを読み込み、現状把握
2. `docs/messaging/work-objects-implementation.md` の「Adding actions to Work Objects」セクション（line 606-728）を精読
3. `docs/tools/bolt-python/concepts/actions.md` で Bolt Python の `@app.action()` 実装を確認
4. `docs/reference/app-manifest.md` で `settings.interactivity` フィールド仕様を確認
5. 既存の manifest サンプル（0070）との差分を整理

---

## 調査結果

### 1. 全体像：アクション実装に必要な3要素

アクションを実装するには以下の3つが必要:

1. **manifest.json の `settings.interactivity` 設定** — `block_actions` ペイロードを受け取るためのエンドポイント設定
2. **`entity.presentDetails` のメタデータ内にアクション定義** — どのボタンを表示するかの定義
3. **Bolt Python の `@app.action()` ハンドラー** — ボタンがクリックされた際の処理

---

### 2. manifest.json の設定

#### 2a. `settings.interactivity` の追加

アクション（`block_actions` ペイロード）を受け取るためには manifest.json に `settings.interactivity` が必須。

**出典**: `docs/reference/app-manifest.md` L729-L761

```
settings.interactivity — インタラクティビティ設定のサブグループ

  is_enabled (boolean, 必須):
    インタラクティビティ機能を有効にするかどうか。

  request_url (string):
    インタラクティブなリクエストを送信する Request URL。
    (https://example.com/slack/message_action)

  message_menu_options_url (string):
    動的 Options Load URL（外部セレクトのオプション動的取得に使用）。
```

**URL なし（Lambda デプロイ前）**: `interactivity` フィールド自体を省略可能  
**URL あり（Lambda デプロイ後）**:

```json
"settings": {
  "interactivity": {
    "is_enabled": true,
    "request_url": "https://REPLACE_WITH_YOUR_LAMBDA_URL/slack/events"
  }
}
```

注意: `event_subscriptions.request_url` と `interactivity.request_url` は**同じ URL**を設定してよい。Bolt は1エンドポイントで両方を受け付ける（0055のログで確認済み）。

#### 2b. 完全な manifest.json（アクション対応・URL あり版）

0070 のサンプルは既に `interactivity` を含んでいる。以下は確認のための再掲:

```json
{
  "_metadata": {
    "major_version": 2,
    "minor_version": 1
  },
  "display_information": {
    "name": "My Enterprise Search App",
    "description": "Enterprise Search app for internal data sources",
    "background_color": "#2c2d30"
  },
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "request_url": "https://REPLACE_WITH_YOUR_LAMBDA_URL/slack/events",
      "bot_events": [
        "function_executed",
        "entity_details_requested"
      ]
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
    "bot_user": {
      "display_name": "My Search Bot",
      "always_online": false
    },
    "search": {
      "search_function_callback_id": "search_function"
    },
    "rich_previews": {
      "is_active": true,
      "entity_types": [
        "slack#/entities/task"
      ]
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "team:read"
      ]
    }
  },
  "functions": {
    "search_function": {
      "title": "Search Function",
      "description": "Returns search results for the given query",
      "input_parameters": {
        "properties": {
          "query": { "type": "string", "title": "Query", "description": "Search query string" },
          "filters": { "type": "object", "title": "Filters", "description": "Filter key-value pairs" },
          "user_context": { "type": "slack#/types/user_context", "title": "User Context", "description": "User context" }
        },
        "required": ["query"]
      },
      "output_parameters": {
        "properties": {
          "search_results": { "type": "slack#/types/search_results", "title": "Search Results", "description": "Results" }
        },
        "required": ["search_results"]
      }
    }
  }
}
```

**アクション実装のための差分（URL なし版からの変更点）**:

| フィールド | URL なし | URL あり（アクション対応） |
|---|---|---|
| `settings.event_subscriptions.request_url` | なし | Lambda URL |
| `settings.interactivity.is_enabled` | なし | `true` |
| `settings.interactivity.request_url` | なし | Lambda URL |

---

### 3. アクションの定義（entity_payload.actions）

**出典**: `docs/messaging/work-objects-implementation.md` L606-L699

アクションは `entity.presentDetails` に渡す `metadata` の `entity_payload.actions` フィールドで定義する。

#### 3a. アクション構造

```json
{
  "actions": {
    "primary_actions": [],   // 最大2つ（unfurl/flexpane フッターに表示）
    "overflow_actions": []   // 最大5つ（「More actions」オーバーフローメニューに表示）
  }
}
```

#### 3b. 各アクションのプロパティ

| プロパティ | 必須 | 型 | 説明 |
|---|---|---|---|
| `text` | Yes | string | ボタンに表示するテキスト |
| `action_id` | Yes | string | アクション識別子（最大255文字）。`@app.action()` でリスンする ID |
| `value` | No | string | インタラクションペイロードと一緒に送られる値（最大2000文字）|
| `style` | No | string | `"primary"` (緑) または `"danger"` (赤) |
| `url` | No | string | クリックでブラウザが開く URL（最大3000文字）|
| `accessibility_label` | No | string | スクリーンリーダー用テキスト（最大75文字）|

#### 3c. アクション定義の例（entity.presentDetails の metadata 内）

```python
metadata = {
    "entity_type": "slack#/entities/task",
    "url": entity_url,
    "external_ref": {"id": entity_id},
    "entity_payload": {
        "attributes": {
            "title": {"text": item["title"]}
        },
        "fields": {
            "status": {"value": item["status"], "tag_color": "blue"},
            "assignee": {
                "user": {"text": item["assignee_name"], "email": item["assignee_email"]},
                "type": "slack#/types/user"
            },
            "due_date": {"value": item["due_date"], "type": "slack#/types/date"}
        },
        "actions": {
            "primary_actions": [
                {
                    "text": "Close Task",
                    "action_id": "close_task",   # Bolt の @app.action("close_task") でリスン
                    "style": "danger",
                    "value": item["id"]
                },
                {
                    "text": "Assign to Me",
                    "action_id": "assign_to_me",
                    "style": "primary",
                    "value": item["id"]
                }
            ],
            "overflow_actions": [
                {
                    "text": "Pin Task",
                    "action_id": "pin_task",
                    "value": item["id"]
                },
                {
                    "text": "Share Task",
                    "action_id": "share_task",
                    "value": item["id"]
                }
            ]
        },
        "display_order": ["status", "assignee", "due_date"]
    }
}
client.entity_presentDetails(trigger_id=trigger_id, metadata=metadata)
```

---

### 4. Bolt for Python でのアクションハンドラー実装

**出典**: `docs/tools/bolt-python/concepts/actions.md`

#### 4a. 基本構文

```python
@app.action("action_id")
def handle_action(ack, body, client, logger):
    ack()  # 3秒以内に必須
    # 処理...
```

- `action_id` は `entity_payload.actions` で定義した `action_id` と一致させる
- `re.Pattern` で複数の action_id をまとめてリスンすることも可能

#### 4b. `block_actions` ペイロードの重要プロパティ

ユーザーがボタンをクリックすると `block_actions` ペイロードがアプリに送信される。

**出典**: `docs/messaging/work-objects-implementation.md` L703-L715

```
container オブジェクトに含まれる Work Objects 固有プロパティ:
  - entity_url      : 外部システムでのエンティティ URL
  - external_ref    : {"id": "...", "type": "..."} 外部参照
  - app_unfurl_url  : Slack メッセージ内の unfurl URL
  - message_ts      : ソースメッセージのタイムスタンプ
  - thread_ts       : スレッドのルートメッセージのタイムスタンプ
  - channel_id      : チャンネル ID

container.type:
  "message_attachment" → unfurl カードからのアクション
  "entity_detail"      → flexpane からのアクション
```

#### 4c. 完全なアクションハンドラー実装例

```python
@app.action("close_task")
def handle_close_task(ack, body, client, logger):
    """
    「Close Task」ボタンクリックを処理する。
    """
    ack()  # 3秒以内に必須（タイムアウトしてもアクション処理は継続可能）

    container = body.get("container", {})
    entity_url = container.get("entity_url")
    external_ref = container.get("external_ref", {})
    entity_id = external_ref.get("id")
    trigger_id = body.get("trigger_id")
    user_id = body["user"]["id"]

    # 発生元の判別
    container_type = container.get("type")
    # "message_attachment" → unfurl カードから
    # "entity_detail"      → flexpane から

    # actions 配列から action_id と value を取得
    actions = body.get("actions", [])
    if actions:
        action = actions[0]
        item_id = action.get("value")  # entity_payload.actions で設定した value

    try:
        # 外部システムでタスクをクローズ
        my_external_system_close_task(entity_id, user_id=user_id)

        # 最新状態を取得してフレックスペインを更新
        updated_item = my_external_system_get_item(entity_id)
        updated_metadata = {
            "entity_type": "slack#/entities/task",
            "url": entity_url,
            "external_ref": {"id": entity_id},
            "entity_payload": {
                "attributes": {"title": {"text": updated_item["title"]}},
                "fields": {
                    "status": {
                        "value": "closed",
                        "tag_color": "gray"
                    }
                },
                "actions": {
                    "primary_actions": [
                        {
                            "text": "Reopen Task",
                            "action_id": "reopen_task",
                            "style": "primary",
                            "value": entity_id
                        }
                    ]
                }
            }
        }

        # flexpane を最新状態に更新
        # trigger_id は block_actions ペイロードの trigger_id を使用
        client.entity_presentDetails(
            trigger_id=trigger_id,
            metadata=updated_metadata
        )

    except Exception as e:
        logger.exception(f"Failed to close task: {e}")
        # エラー時はユーザーへの DM で通知（flexpane 更新は認証エラー時のみ自動対応）
        client.chat_postMessage(
            channel=user_id,
            text=f"Failed to close task. Please try again."
        )


@app.action("assign_to_me")
def handle_assign_to_me(ack, body, client, logger):
    ack()
    # close_task と同様のパターンで実装


@app.action("reopen_task")
def handle_reopen_task(ack, body, client, logger):
    ack()
    # close_task と同様のパターンで実装


@app.action("pin_task")
def handle_pin_task(ack, body, client, logger):
    ack()
    # pin 処理の実装
```

#### 4d. 制約マッチング（複数の action_id をまとめて処理する場合）

```python
import re

# action_id が "task_" で始まるアクションを全て処理
@app.action(re.compile("^task_.*"))
def handle_task_actions(ack, body, action, logger):
    ack()
    action_id = action["action_id"]
    value = action["value"]
    logger.info(f"Task action: {action_id}, value: {value}")

# block_id + action_id の組み合わせで特定
@app.action({"block_id": "task_block", "action_id": "close_task"})
def handle_specific_action(ack, body, client, logger):
    ack()
```

---

### 5. アクション後の応答方法（まとめ）

**出典**: `docs/messaging/work-objects-implementation.md` L717-L728

ボタンクリック後のアプリの応答方法（複数選択可）:

| 応答方法 | 実装 | 用途 |
|---|---|---|
| flexpane を更新 | `client.entity_presentDetails(trigger_id=..., metadata=...)` | アクション成功後に最新状態を表示（推奨） |
| モーダルを開く | `client.views_open(trigger_id=..., view=...)` | 追加情報をユーザーから収集する場合 |
| スレッドにメッセージ投稿 | `client.chat_postMessage(channel=..., thread_ts=..., text=...)` | unfurl メッセージがあるスレッドへの投稿 |
| ユーザーに DM | `client.chat_postMessage(channel=user_id, text=...)` | アクション失敗の通知 |
| 認証フローへ誘導 | `client.entity_presentDetails(trigger_id=..., user_auth_required=True, user_auth_url=...)` | ユーザー未認証時に自動で flexpane を開く |

**注意**: アクション処理後は自動的にリフレッシュがスケジュールされる（ドキュメント line 64）。  
「Block action clicks. When a user clicks an action button on an unfurl, a refresh is scheduled to pick up any changes the action may have caused in your external system.」  
→ 手動で `entity.presentDetails` を呼ぶとより即時に反映される。

---

### 6. SDK サポート状況（Bolt for Python）

**出典**: `docs/messaging/work-objects-overview.md` L31-35

```
Work Object support is also available in the Bolt for JavaScript and Bolt for Java 
frameworks, and is coming soon to the Bolt for Python framework.
```

- **Bolt for JavaScript**: サポート済み
- **Bolt for Java**: サポート済み
- **Bolt for Python**: "coming soon"（現時点では「まもなく対応」）

→ ただし `@app.action()` による `block_actions` ペイロード処理は既存の Bolt for Python 機能として**今でも利用可能**。「coming soon」は Work Objects 専用の高レベル API（Bolt for JS の `app.view('work-object-edit', ...)` 相当）を指していると考えられる。

実際、0070 のサンプルコードでは `@app.action("close_issue")` を使用しており、これは標準の Bolt for Python で動作する。

---

### 7. 自動更新メカニズム

**出典**: `docs/messaging/work-objects-implementation.md` L59-72

アクションクリック後、Slack は**自動的に**リフレッシュをスケジュールする:

```
Block action clicks. When a user clicks an action button on an unfurl, a refresh is 
scheduled to pick up any changes the action may have caused in your external system. 
This refresh occurs after a short delay to allow time for your system to process the action.
```

`metadata_last_modified` フィールドを最適化に使用できる:

```python
"entity_payload": {
    "attributes": {
        "title": {"text": item["title"]},
        "metadata_last_modified": int(item["updated_at_ts"])  # UNIX タイムスタンプ
    },
    ...
}
```

Slack はこの値を以前のものと比較し、新しい値が大きい場合のみリフレッシュをトリガーする。

---

## 実装チェックリスト

### manifest.json

- [ ] `settings.interactivity.is_enabled: true` を追加（Lambda URL 設定後）
- [ ] `settings.interactivity.request_url` に Lambda URL を設定（`event_subscriptions.request_url` と同じ URL でよい）
- [ ] `settings.event_subscriptions.bot_events` に `entity_details_requested` が含まれている（flexpane 対応）
- [ ] `features.rich_previews.is_active: true` と `entity_types: ["slack#/entities/task"]` が設定されている

### entity.presentDetails（handle_entity_details 内）

- [ ] `entity_payload.actions.primary_actions` にアクションを定義（最大2つ）
- [ ] 各アクションに一意の `action_id` を設定
- [ ] 必要に応じて `overflow_actions` を定義（最大5つ）

### Bolt for Python（app.py）

- [ ] 各 `action_id` に対応する `@app.action()` ハンドラーを実装
- [ ] ハンドラー内で `ack()` を3秒以内に呼び出す
- [ ] `body["container"]["entity_url"]` と `body["container"]["external_ref"]["id"]` で操作対象を特定
- [ ] アクション処理後に `client.entity_presentDetails()` で flexpane を更新
