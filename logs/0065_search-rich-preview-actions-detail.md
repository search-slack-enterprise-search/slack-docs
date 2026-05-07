# 検索→リッチプレビュー→アクション の実装詳細

## 調査情報

- タスクファイル: `kanban/0065_search-rich-preview-actions-detail.md`
- 調査日: 2026-05-07
- 調査者: Claude Code (kanban スキル)
- 前提タスク: 0064（Enterprise Search + Work Objects + Interactions の組み合わせでできること）

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/messaging/work-objects-implementation.md`
- `docs/messaging/work-objects-overview.md`
- `docs/messaging/unfurling-links-in-messages.md`
- `docs/reference/events/function_executed.md`
- `docs/reference/methods/functions.completesuccess.md`
- `docs/reference/methods/functions.completeerror.md`
- `docs/reference/methods/chat.unfurl.md`
- `docs/reference/interaction-payloads/block_actions-payload.md`
- `docs/tools/bolt-python/concepts/custom-steps.md`
- `docs/tools/bolt-python/reference/app.md`
- `docs/reference/app-manifest.md`

## 調査アプローチ

0064 の調査で得た概要をベースに、「検索→リッチプレビュー→アクション」の具体的な実装手順・API・コード例を重点的に調査した。特に以下のポイントを深掘りした:
1. Enterprise Search の検索関数の実装方法
2. Work Objects flexpane の実装方法
3. アクションボタンの定義と `block_actions` 処理の実装方法
4. Bolt for Python での具体的なコードパターン
5. 必要なスコープ・App Manifest の設定

---

## 調査結果

### 1. 全体フロー概要

「検索→リッチプレビュー→アクション」の完全なフローは以下の通り:

```
[ユーザーが Slack で検索]
    ↓
[Slack が function_executed イベントをアプリに送信]
    ↓ (10秒以内)
[アプリが functions.completeSuccess で検索結果を返す]
    ↓
[Slack が検索結果を表示 (title, description, link 等)]
    ↓ (ユーザーが検索結果をクリック)
[Slack が entity_details_requested イベントをアプリに送信]
    ↓
[アプリが entity.presentDetails API で flexpane コンテンツを返す]
    ↓
[Slack が Work Object flexpane を表示 (リッチプレビュー)]
    ↓ (ユーザーが flexpane 内のアクションボタンをクリック)
[Slack が block_actions ペイロードをアプリに送信]
    ↓
[アプリがアクション処理（外部システム更新等）を実行]
    ↓
[アプリが entity.presentDetails で flexpane を更新]
```

---

### 2. App Manifest の設定

#### 2a. 完全な App Manifest 構成

以下の設定が必要（docs/enterprise-search/developing-apps-with-search-features.md, line 44-47）:

```json
{
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "request_url": "https://your-app.example.com/slack/events",
      "bot_events": [
        "function_executed",
        "entity_details_requested"
      ]
    },
    "interactivity": {
      "is_enabled": true,
      "request_url": "https://your-app.example.com/slack/interactivity"
    },
    "app_type": "remote",
    "function_runtime": "remote"
  },
  "features": {
    "search": {
      "search_function_callback_id": "my_search_function",
      "search_filters_function_callback_id": "my_search_filters_function"
    },
    "unfurl_domains": [
      "your-domain.example.com"
    ]
  },
  "functions": {
    "my_search_function": {
      "title": "My Search Function",
      "description": "Handles search queries from Slack",
      "input_parameters": {
        "properties": {
          "query": {
            "type": "string",
            "title": "Search Query",
            "is_required": true
          },
          "filters": {
            "type": "object",
            "title": "Search Filters",
            "is_required": false
          },
          "user_ctx": {
            "type": "slack#/types/user_context",
            "title": "User Context",
            "is_required": false
          }
        },
        "required": ["query"]
      },
      "output_parameters": {
        "properties": {
          "search_results": {
            "type": "slack#/types/search_results",
            "title": "Search Results",
            "is_required": true
          }
        },
        "required": ["search_results"]
      }
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "links:read",
        "links:write"
      ]
    }
  }
}
```

**注意点**:
- `org_deploy_enabled: true` は必須（Enterprise Grid オーグレベルインストールが必要）
- `function_runtime: remote` は必須（Lambda 等の外部サーバーでの実行を示す）
- `links:read` と `links:write` スコープが Work Objects の unfurl に必要（`unfurling-links-in-messages.md` line 44-45）
- `unfurl_domains` に外部システムのドメインを登録（URL unfurl にも対応する場合）
- Enterprise Search のみの場合は `unfurl_domains` は不要（ただし link_shared イベントは不要）
- `interactivity.request_url` は `block_actions`（ボタンクリック）を受け取るために必要

---

### 3. Step 1: Enterprise Search 実装（検索結果の返却）

#### 3a. function_executed イベント

検索が実行されると Slack から以下のイベントが送信される（docs/reference/events/function_executed.md）:

```json
{
  "type": "event_callback",
  "event": {
    "type": "function_executed",
    "function": {
      "id": "Fn123456789O",
      "callback_id": "my_search_function",
      "title": "My Search Function",
      "input_parameters": [...],
      "output_parameters": [...]
    },
    "inputs": {
      "query": "ユーザーが検索したクエリ文字列",
      "filters": {},
      "user_ctx": { "user_id": "U123...", "team_id": "T123..." }
    },
    "function_execution_id": "Fx1234567O9L",
    "bot_access_token": "xwfp-..."
  }
}
```

**重要**: `bot_access_token` はワークフロートークンで、`functions.completeSuccess` / `functions.completeError` の呼び出しに使用する。このトークンは完了通知後に無効化されるが、ボットトークンは引き続き使用可能。

#### 3b. Bolt for Python での実装

`developing-apps-with-search-features.md`（line 315-333）より:

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    process_before_response=True  # Lambda 等の FaaS 向け
)

@app.function(
    "my_search_function",
    auto_acknowledge=False,  # 手動で ack() を制御
    ack_timeout=10           # タイムアウトを3秒→10秒に延長
)
def handle_search(inputs: dict, complete, fail, ack):
    try:
        query = inputs.get("query", "")
        user_ctx = inputs.get("user_ctx", {})
        filters = inputs.get("filters", {})
        
        # 外部システムから検索結果を取得
        results = my_external_system.search(
            query=query,
            user_id=user_ctx.get("user_id"),
            filters=filters
        )
        
        # search_results を構築
        search_results = []
        for item in results[:50]:  # 最大50件
            search_results.append({
                "external_ref": {
                    "id": item["id"],          # Work Objects の external_ref.id と一致させる！
                    "type": "document"          # オプション: 任意の型名
                },
                "title": item["title"],        # 必須: 検索結果のタイトル
                "description": item["summary"], # 必須: 検索結果の説明文（AI アンサーにも使用）
                "link": item["url"],            # 必須: 外部システムへのリンク
                "date_updated": item["updated_at"].strftime("%Y-%m-%d"),  # 必須: YYYY-MM-DD 形式
                "content": item["full_text"]    # オプション: AI アンサー向けの詳細コンテンツ
            })
        
        # 成功を Slack に通知（同時に ack() も行われる）
        complete(outputs={"search_results": search_results})
        
    except Exception as e:
        fail(f"Search failed: Authentication required. Visit https://your-app.example.com/auth")
```

`app.function()` のシグネチャ（`bolt-python/reference/app.md` line 841-888）:

```python
def function(
    self,
    callback_id: Union[str, Pattern],
    matchers: Optional[Sequence[Callable[..., bool]]] = None,
    middleware: Optional[Sequence[Union[Callable, Middleware]]] = None,
    auto_acknowledge: bool = True,   # Enterprise Search では False に設定
    ack_timeout: int = 3,            # Enterprise Search では 10 に設定
) -> Callable
```

**重要な動作**（app.md line 876-878）:
- `auto_acknowledge=True` のとき `ack_timeout != 3` を設定すると警告が出る
- Enterprise Search では必ず `auto_acknowledge=False, ack_timeout=10` を設定する
- これにより、デフォルトの3秒ではなく10秒の制限内で処理できる

#### 3c. search_results オブジェクトの構造（developing-apps-with-search-features.md, line 93-176）

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `external_ref` | object | 必須 | ユニーク識別子。Work Objects の `external_ref.id` と同じ値を使う |
| `external_ref.id` | string | 必須 | 外部システムでの一意ID |
| `external_ref.type` | string | 任意 | ID が一意でない場合に必要な内部タイプ名 |
| `title` | string | 必須 | 検索結果の見出し |
| `description` | string | 必須 | 検索結果の説明文（AI アンサーにも利用） |
| `link` | string | 必須 | 外部システムへのナビゲーション URI |
| `date_updated` | string | 必須 | 作成日または最終更新日（YYYY-MM-DD 形式） |
| `content` | string | 任意 | 詳細コンテンツ（AI アンサー向け、title + description に加えて提供） |

**注意点**: `query` 入力はユーザーの生の検索クエリとは異なる場合がある。Slack がセキュリティ・ UX 向上のために再書き込み（rewrite）を行うため（line 86-88）。

#### 3d. キャッシュ動作

- Slack は検索結果を**ユーザーとクエリの組み合わせごとに最大3分間**キャッシュする
- AI アンサーも同様に3分間キャッシュされる
- フィルター結果も同様に3分間キャッシュされ、同一検索コンテキストでは再呼び出しされない

---

### 4. Step 2: Work Objects flexpane の実装（リッチプレビュー）

#### 4a. entity_details_requested イベント

ユーザーが検索結果をクリックすると Slack から以下のイベントが送信される（docs/messaging/work-objects-implementation.md, line 1247-1253）:

```json
{
  "type": "entity_details_requested",
  "user": "U0123456",
  "external_ref": {
    "id": "123",          // Enterprise Search の external_ref.id と同じ値
    "type": "my-type"
  },
  "entity_url": "https://your-domain.example.com/document/123",
  "link": {
    "url": "https://your-domain.example.com/document/123",
    "domain": "your-domain.example.com"
  },
  "app_unfurl_url": "https://your-domain.example.com/document/123?params=...",
  "event_ts": "123456789.1234566",
  "trigger_id": "1234567890123.1234567890123.abcdef...",
  "user_locale": "en-US",
  // 検索結果からの場合、これらのフィールドは含まれない（メッセージコンテキストがない）
  // "channel": "C123...",     // 検索結果から開いた場合は不提供
  // "message_ts": "...",      // 検索結果から開いた場合は不提供
  // "thread_ts": "..."        // 検索結果から開いた場合は不提供
}
```

**重要な注意点** (work-objects-implementation.md, line 1247-1253):
> These fields will not be provided when the entity details are opened from outside of a message context (i.e., Enterprise Search)

→ Enterprise Search から flexpane を開いた場合、`channel`, `message_ts`, `thread_ts` は提供されない。

#### 4b. Bolt for Python での flexpane 実装

```python
@app.event("entity_details_requested")
def handle_entity_details(body, client, logger):
    event = body["event"]
    trigger_id = event["trigger_id"]
    external_ref = event.get("external_ref", {})
    entity_id = external_ref.get("id")
    entity_url = event.get("entity_url")
    user_id = event.get("user")
    user_locale = event.get("user_locale", "en-US")
    
    # ユーザー認証チェック
    if not is_user_authenticated(user_id):
        client.entity_presentDetails(
            trigger_id=trigger_id,
            user_auth_required=True,
            user_auth_url=f"https://your-app.example.com/auth?user={user_id}"
        )
        return
    
    # 外部システムからエンティティ情報を取得
    item = my_external_system.get_item(entity_id)
    
    # Work Object メタデータを構築
    metadata = {
        "entity_type": "slack#/entities/task",  # または file, incident, content_item, item
        "url": entity_url,
        "external_ref": {
            "id": entity_id,
            "type": "document"
        },
        "entity_payload": {
            "attributes": {
                "title": {"text": item["title"]},
                "display_type": "Document",          # 例: "Issue", "Wiki Page" 等
                "product_name": "My System",         # 外部システム名
                "product_icon": {
                    "alt_text": "My System icon",
                    "url": "https://your-domain.example.com/icon.png"
                }
            },
            "fields": {
                "description": {
                    "value": item["body"],
                    "format": "markdown"
                },
                "created_by": {
                    "user": {"text": item["creator_name"]},
                    "type": "slack#/types/user"
                },
                "status": {
                    "value": item["status"],
                    "tag_color": "green" if item["status"] == "open" else "gray"
                },
                "due_date": {
                    "value": item["due_date"],  # YYYY-MM-DD
                    "type": "slack#/types/date"
                },
                "assignee": {
                    "user": {
                        "text": item["assignee_name"],
                        "email": item["assignee_email"]
                    },
                    "type": "slack#/types/user"
                }
            },
            "actions": {
                "primary_actions": [
                    {
                        "text": "Close Issue",
                        "action_id": "close_issue",
                        "style": "danger",
                        "value": entity_id
                    },
                    {
                        "text": "Assign to Me",
                        "action_id": "assign_to_me",
                        "style": "primary",
                        "value": entity_id
                    }
                ],
                "overflow_actions": [
                    {
                        "text": "Pin Issue",
                        "action_id": "pin_issue",
                        "value": entity_id
                    }
                ]
            },
            "display_order": ["description", "status", "assignee", "due_date", "created_by"]
        }
    }
    
    # flexpane を表示
    client.entity_presentDetails(
        trigger_id=trigger_id,
        metadata=metadata
    )
```

**Bolt Python での API 呼び出し名**: `client.entity_presentDetails`（メソッド名はキャメルケースからスネークケースに変換）

---

### 5. Step 3: アクションボタンの実装

#### 5a. アクション定義の完全構造

`entity_payload.actions` フィールドに定義する（work-objects-implementation.md, line 623-699）:

```json
{
  "actions": {
    "primary_actions": [     // unfurl フッター・flexpane フッターに表示。最大2個
      {
        "text": "Close Issue",           // 必須: ボタンのラベル
        "action_id": "close_issue",      // 必須: アクション識別子（255文字以内）
        "value": "issue_123",            // 任意: アクションペイロードに含める値（2000文字以内）
        "style": "danger",               // 任意: "primary"（緑）または "danger"（赤）
        "url": null,                     // 任意: クリック時に開く URL（3000文字以内）
        "accessibility_label": "Close the selected issue"  // 任意: スクリーンリーダー用（75文字以内）
      }
    ],
    "overflow_actions": [   // 「More actions」オーバーフローメニューに表示。最大5個
      {
        "text": "Pin Issue",
        "action_id": "pin_issue",
        "value": "issue_123"
      }
    ]
  }
}
```

#### 5b. block_actions ペイロードの受信

ユーザーがボタンをクリックすると `block_actions` ペイロードがアプリの Interactivity Request URL に送信される。

**unfurl からのアクション**（work-objects-implementation.md, line 709-713）:
- `container.type: "message_attachment"`
- Work Object 固有のフィールド: `container.entity_url`, `container.external_ref`, `container.app_unfurl_url`, `container.message_ts`, `container.thread_ts`, `container.channel_id`

**flexpane からのアクション**:
- `container.type: "entity_detail"`
- 同様の Work Object 固有フィールドを含む

完全なペイロード例（line 711-713）:
```json
{
  "type": "block_actions",
  "user": {"id": "U123ABC456", "username": "jennifer_hynes"},
  "api_app_id": "A123ABC456",
  "trigger_id": "1234567890123.1234567890123.abcdef...",
  "container": {
    "type": "message_attachment",  // unfurl の場合
    "message_ts": "1753813500.959789",
    "thread_ts": "1753813200.519449",
    "channel_id": "C123ABC456",
    "is_app_unfurl": true,
    "app_unfurl_url": "https://your-domain.example.com/issues/139",
    "entity_url": "https://your-domain.example.com/issues/139",
    "external_ref": {"id": "139"}
  },
  "actions": [
    {
      "type": "button",
      "action_id": "close_issue",
      "value": "139",
      "action_ts": "1748809126.803329"
    }
  ]
}
```

#### 5c. Bolt for Python でのアクション処理

```python
@app.action("close_issue")
def handle_close_issue(ack, body, client, logger):
    ack()  # 3秒以内に ACK が必要
    
    # Work Object 固有のコンテキスト取得
    container = body.get("container", {})
    entity_url = container.get("entity_url")
    external_ref = container.get("external_ref", {})
    entity_id = external_ref.get("id")
    trigger_id = body.get("trigger_id")
    user_id = body["user"]["id"]
    
    try:
        # 外部システムでアクションを実行
        my_external_system.close_issue(entity_id)
        
        # flexpane を最新状態に更新（ユーザーに即座にフィードバック）
        updated_item = my_external_system.get_item(entity_id)
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
                            "text": "Reopen Issue",
                            "action_id": "reopen_issue",
                            "style": "primary",
                            "value": entity_id
                        }
                    ]
                }
            }
        }
        
        client.entity_presentDetails(
            trigger_id=trigger_id,
            metadata=updated_metadata
        )
        
    except Exception as e:
        logger.error(f"Failed to close issue: {e}")
        # エラー時: ユーザーに DM で通知
        client.chat_postMessage(
            channel=user_id,  # DM
            text=f"Issue のクローズに失敗しました: {str(e)}"
        )
```

**重要**: `ack()` は3秒以内に呼び出す必要がある（`block_actions` の標準タイムアウト）。外部システムへのリクエストが遅い場合は、ack 後に非同期処理を実行し、結果は後から `entity.presentDetails` で更新する。

#### 5d. アクション後の応答パターン一覧

（work-objects-implementation.md, line 717-728より）

| シナリオ | 応答方法 | API |
|---|---|---|
| ユーザー認証が必要 | flexpane に認証 UI を表示 | `entity.presentDetails(user_auth_required=True, user_auth_url=...)` |
| 追加情報が必要（モーダル） | モーダルを開く | `views.open(trigger_id=..., view={...})` |
| unfurl を最新化 | unfurl コンテンツを更新 | `chat.unfurl(channel=..., ts=..., metadata={...})` |
| flexpane を最新化 | flexpane コンテンツを更新 | `entity.presentDetails(trigger_id=..., metadata={...})` |
| エラー通知 | ユーザーに DM 送信 | `chat.postMessage(channel=user_id, text=...)` |
| スレッドに投稿 | スレッドにメッセージ | `chat.postMessage(channel=..., thread_ts=..., text=...)` |

---

### 6. 必要なスコープ・イベント・設定の一覧

| 種別 | 項目 | 説明 |
|---|---|---|
| Bot スコープ | `links:read` | URL unfurl のためのリンク読み取り（Work Objects unfurl に必要） |
| Bot スコープ | `links:write` | URL unfurl のためのリンク書き込み（`chat.unfurl` に必要） |
| Bot Events | `function_executed` | 検索クエリを受け取る |
| Bot Events | `entity_details_requested` | flexpane 表示リクエストを受け取る |
| Interactivity | Request URL | `block_actions`, `view_submission` を受け取る |
| App Manifest | `org_deploy_enabled: true` | Enterprise Grid でのオーグレベルインストール |
| App Manifest | `function_runtime: remote` | 外部サーバーでの関数実行 |
| App Manifest | `features.search.search_function_callback_id` | 検索関数の callback_id を指定 |
| App settings | Work Object Previews | GUI で Work Object のエンティティタイプを有効化 |

---

### 7. Work Object エンティティタイプ別フィールド

（work-objects-implementation.md, line 767-819より）

#### Task（タスク・チケット）
```json
{
  "entity_type": "slack#/entities/task",
  "entity_payload": {
    "fields": {
      "description": {"value": "...", "format": "markdown"},
      "status": {"value": "open", "tag_color": "blue"},
      "assignee": {"user": {"text": "John"}, "type": "slack#/types/user"},
      "due_date": {"value": "2026-06-01", "type": "slack#/types/date"},
      "priority": {"value": "high"},
      "created_by": {"user": {"user_id": "U123"}, "type": "slack#/types/user"},
      "date_created": {"value": 1741164235},
      "date_updated": {"value": 1741164235}
    }
  }
}
```

#### File（ドキュメント・スプレッドシート・画像）
```json
{
  "entity_type": "slack#/entities/file",
  "entity_payload": {
    "fields": {
      "preview": {"type": "slack#/types/image", "image_url": "...", "alt_text": "..."},
      "created_by": {"user": {"user_id": "U123"}, "type": "slack#/types/user"},
      "file_size": {"value": "256MB"},
      "mime_type": {"value": "application/pdf"},
      "date_created": {"value": 1741164235},
      "date_updated": {"value": 1741164235}
    }
  }
}
```

#### Content Item（Wiki ページ・記事）
```json
{
  "entity_type": "slack#/entities/content_item",
  "entity_payload": {
    "fields": {
      "description": {"value": "..."},
      "preview": {"type": "slack#/types/image", "image_url": "..."},
      "created_by": {"user": {"user_id": "U123"}, "type": "slack#/types/user"},
      "last_modified_by": {"user": {"user_id": "U456"}, "type": "slack#/types/user"},
      "date_created": {"value": 1741164235},
      "date_updated": {"value": 1741164235}
    }
  }
}
```

#### Item（汎用エンティティ）
- `fields` なし。すべてのプロパティを `custom_fields` で定義する
- 最も柔軟だが、Work Objects 標準フィールドのダウンストリーム機能（AI アンサー等）は機能しない可能性あり

---

### 8. Sample App へのリファレンス

ドキュメント（developing-apps-with-search-features.md, line 332-351）には以下の2つのサンプルアプリが紹介されている:

- **Bolt for Python**: `https://github.com/slack-samples/bolt-python-search-template`
  - `README.md` の "Using Slack CLI" セクションを参照
- **Bolt for TypeScript**: `https://github.com/slack-samples/bolt-ts-search-template`
  - `README.md` の "Using Slack CLI" セクションを参照

---

### 9. 重要な制約・注意点

1. **`entity_details_requested` の `trigger_id` は一度限り**: `entity.presentDetails` を呼び出す際の `trigger_id` は1回のみ使用可能。複数回呼び出す場合は最初のレスポンスから `trigger_id` は不要になる（再度イベントが送信される）

2. **`function_executed` の10秒制限**: Enterprise Search の検索関数は10秒以内に `functions.completeSuccess` または `functions.completeError` を呼び出す必要がある。Bolt Python では `auto_acknowledge=False, ack_timeout=10` が必須。

3. **Enterprise Search から `entity_details_requested` が来る場合は `external_ref` が保証されない**: 
   > "This is not guaranteed to be set in all cases. For example, when a work object is opened from an Enterprise Search result provided by a Slack-developed search provider, we cannot provide an external_ref."
   
   アプリが作成した検索結果については `external_ref` は提供されるはずだが、Slack 開発のサーチプロバイダーからの結果については提供されない。`entity_url` をフォールバックとして使う必要がある。

4. **`links:read` / `links:write` スコープと `unfurl_domains` は Work Objects の link unfurl シナリオに必要**: Enterprise Search から直接 flexpane を開く場合（検索結果クリック）は link unfurl フローを経由しないため、これらは Work Objects の unfurl（チャンネルでの URL 共有）のために必要。

5. **Bolt for Python の Work Objects SDK サポートは "Coming soon"**: `entity_presentDetails` のヘルパーは手動で呼び出す必要がある場合がある（`work-objects-overview.md` line 33）。現時点では `app.client.entity_presentDetails(...)` のように API を直接呼び出す形になる。

6. **`container.type` の違い**: unfurl からのアクションは `container.type: "message_attachment"`、flexpane からのアクションは `container.type: "entity_detail"`。同じ `action_id` でも発生元を区別したい場合はこのフィールドで判別する。

---

### 10. 調査中の疑問・未解決事項

1. `entity_details_requested` イベントの `trigger_id` の有効期限は何秒か？（通常の `trigger_id` は3秒だが、flexpane 向けは異なる可能性）
2. Enterprise Search の検索関数からは `link_shared` イベントは発生しないため、Work Objects unfurl（`chat.unfurl` + `metadata`）は別途 link_shared イベントを受信した際に実装する必要があるが、この2つのフローは独立して実装するのか、それとも何らかの形で統合できるのか？
3. `entity.presentDetails` の Tier 3 レートリミット（50+/分）は、多数のユーザーが同時に flexpane を開いた場合に問題になる可能性があるが、対策方法はあるか？
