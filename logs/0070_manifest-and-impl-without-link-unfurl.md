# Link Unfurl なしの manifest.json と Python 実装

## 調査情報

- タスクファイル: `kanban/0070_manifest-and-impl-without-link-unfurl.md`
- 調査日: 2026-05-07
- 前提タスク:
  - 0068: `0065・0067の調査結果統合`（logs/0068_reconcile-0065-0067-findings.md）
  - 0069: `Link Unfurl 詳細調査`（logs/0069_link-unfurl-details.md）
  - 0055: `Enterprise Search manifest サンプル`（logs/0055_enterprise-search-manifest-sample.md）
  - 0060: `Bolt Python 検索関数の引数型`（logs/0060_bolt-python-search-function-argument-types.md）
  - 0062: `Bolt Python App インスタンス化設定`（logs/0062_bolt-python-app-init-config.md）
  - 0065: `検索→リッチプレビュー→アクション の実装詳細`（logs/0065_search-rich-preview-actions-detail.md）

---

## 調査ファイル一覧

- `kanban/0068_reconcile-0065-0067-findings.md`（サマリー参照）
- `logs/0068_reconcile-0065-0067-findings.md`（詳細ログ参照）
- `logs/0069_link-unfurl-details.md`（詳細ログ参照）
- `logs/0055_enterprise-search-manifest-sample.md`（manifest サンプル参照）
- `logs/0060_bolt-python-search-function-argument-types.md`（型情報参照）
- `logs/0062_bolt-python-app-init-config.md`（App 初期化参照）
- `logs/0065_search-rich-preview-actions-detail.md`（実装詳細参照）
- `docs/enterprise-search/developing-apps-with-search-features.md`（公式仕様）
- `docs/messaging/work-objects-implementation.md`（entity_details_requested・flexpane）
- `docs/tools/bolt-python/concepts/custom-steps.md`（Bolt Python 実装）
- `docs/tools/bolt-python/concepts/acknowledge.md`（ack 動作）

---

## 調査アプローチ

1. 0068/0069 のログを読んで「link unfurl なし」の場合に何が不要かを整理済みの情報として確認
2. 0055/0060/0062/0065 のログを読んで完全な manifest と Python 実装を把握
3. 公式ドキュメントで最新情報を補完
4. 2 バリアント（URL なし・URL あり）の manifest と全 Python ハンドラーをまとめる

---

## 前提：link unfurl なしで何が変わるか（0068/0069 の統合結論）

0068（0065/0067 の統合）と 0069（link unfurl 詳細調査）の結論を以下に集約する。

### link unfurl を使う場合に必要だが、なしの場合には**不要**なもの

| 種別 | 不要になる設定 | 理由 |
|---|---|---|
| bot_events | `link_shared` | チャットへの URL 貼り付けを検知するイベント。Enterprise Search 経由では発生しない |
| features | `unfurl_domains` | `link_shared` イベントを受け取るためのドメイン登録 |
| scopes | `links:read` | `link_shared` イベント受信のためのスコープ |
| scopes | `links:write` | `chat.unfurl` API 呼び出しのためのスコープ |

### link unfurl なしでも**必要**なもの

| 種別 | 必要な設定 | 理由 |
|---|---|---|
| bot_events | `function_executed` | Enterprise Search の検索クエリ受信 |
| bot_events | `entity_details_requested` | 検索結果クリック時のフレックスペイン表示 |
| interactivity | `is_enabled: true` | `block_actions`（アクションボタンクリック）受信 |
| features | `search.search_function_callback_id` | 検索関数の紐付け |
| features | `rich_previews` | Work Objects エンティティタイプの有効化 |
| scopes | `team:read` | org-ready 設定に最低1つの bot スコープが必要 |
| settings | `org_deploy_enabled: true` | Enterprise Grid でのオーグレベルインストール |
| settings | `function_runtime: remote` | Lambda 等での実行 |

---

## 完全な manifest.json サンプル（link unfurl なし）

### variant 1: URL なし（Slack App 作成直後・Lambda デプロイ前）

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
      "bot_events": [
        "function_executed",
        "entity_details_requested"
      ]
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
      "description": "Returns search results for the given query from internal data sources",
      "input_parameters": {
        "properties": {
          "query": {
            "type": "string",
            "title": "Query",
            "description": "The search query string"
          },
          "filters": {
            "type": "object",
            "title": "Filters",
            "description": "Key-value pairs of filters selected by the user"
          },
          "user_context": {
            "type": "slack#/types/user_context",
            "title": "User Context",
            "description": "Context of the user performing the search"
          }
        },
        "required": [
          "query"
        ]
      },
      "output_parameters": {
        "properties": {
          "search_results": {
            "type": "slack#/types/search_results",
            "title": "Search Results",
            "description": "The search results returned by the app"
          }
        },
        "required": [
          "search_results"
        ]
      }
    }
  }
}
```

### variant 2: URL あり（Lambda デプロイ後・本番運用用）

`REPLACE_WITH_YOUR_LAMBDA_URL` を実際の Lambda Function URL（例: `https://abcdef.lambda-url.ap-northeast-1.on.aws`）に置き換える。

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
      "description": "Returns search results for the given query from internal data sources",
      "input_parameters": {
        "properties": {
          "query": {
            "type": "string",
            "title": "Query",
            "description": "The search query string"
          },
          "filters": {
            "type": "object",
            "title": "Filters",
            "description": "Key-value pairs of filters selected by the user"
          },
          "user_context": {
            "type": "slack#/types/user_context",
            "title": "User Context",
            "description": "Context of the user performing the search"
          }
        },
        "required": [
          "query"
        ]
      },
      "output_parameters": {
        "properties": {
          "search_results": {
            "type": "slack#/types/search_results",
            "title": "Search Results",
            "description": "The search results returned by the app"
          }
        },
        "required": [
          "search_results"
        ]
      }
    }
  }
}
```

### URL なし → URL ありの差分

| フィールド | URL なし | URL あり |
|---|---|---|
| `settings.event_subscriptions.request_url` | なし | Lambda URL |
| `settings.interactivity.is_enabled` | なし | `true` |
| `settings.interactivity.request_url` | なし | Lambda URL |

### link unfurl あり版との差分

| フィールド | link unfurl あり | link unfurl なし（本サンプル） |
|---|---|---|
| `settings.event_subscriptions.bot_events` | `["function_executed", "link_shared", "entity_details_requested"]` | `["function_executed", "entity_details_requested"]`（`link_shared` 除外） |
| `features.unfurl_domains` | `["your-domain.example.com"]` | **なし** |
| `oauth_config.scopes.bot` | `["team:read", "links:read", "links:write"]` | `["team:read"]`（`links:read`/`links:write` 除外） |

---

## 各 manifest フィールドの説明

### `features.rich_previews`

| フィールド | 値 | 説明 |
|---|---|---|
| `is_active` | `true` | Work Object Previews を有効化 |
| `entity_types` | `["slack#/entities/task"]` 等 | 使用するエンティティタイプ（1種類以上指定） |

**サポートされる `entity_types`**:
- `slack#/entities/task` — タスク・チケット・TODO
- `slack#/entities/file` — ドキュメント・スプレッドシート・画像
- `slack#/entities/incident` — インシデント・障害
- `slack#/entities/content_item` — Wiki ページ・記事
- `slack#/entities/item` — 汎用エンティティ

**注意**: manifest の `features.rich_previews.entity_types` と UI の「Work Object Previews → entity type 選択」は同じ設定を指す。manifest で設定すると UI に反映され、UI で変更すると manifest も更新される。

### `features.search.search_function_callback_id`

`functions` マップのキー（`callback_id`）と一致させる必要がある。本サンプルでは `"search_function"` を使用。

フィルター関数（任意）を追加する場合は `search_filters_function_callback_id` を追加し、対応する `functions.search_filters_function` エントリも追加する:

```json
"features": {
  "search": {
    "search_function_callback_id": "search_function",
    "search_filters_function_callback_id": "search_filters_function"
  }
}
```

### `settings.app_type: "remote"`

`docs/reference/app-manifest.md` のリファレンスには記載がないが、`docs/enterprise-search/developing-apps-with-search-features.md` の公式例に明記されている。Enterprise Search アプリでは安全策として含める。

### `oauth_config.scopes.bot`

- `team:read` のみ（最小スコープ）。org-ready 設定（Opt-in 画面）で最低1つの bot スコープが必要なため。
- Enterprise Search 機能自体（`function_executed` 処理 + `functions.completeSuccess`）は専用スコープ不要（ワークフロートークンを使用するため）。
- Connection reporting を実装する場合は **user token** で `users:write` が追加で必要（bot スコープではなく user スコープ）。

---

## 完全な Python 実装（Bolt for Python + AWS Lambda）

### app.py（メインファイル）

```python
import os
import logging
from slack_bolt import App, Complete, Fail, Ack
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

logger = logging.getLogger(__name__)

# Lambda 環境では process_before_response=True が必須
app = App(
    token=os.environ.get("SLACK_BOT_TOKEN"),
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    process_before_response=True
)


# =============================================================================
# 1. 検索ハンドラー（function_executed イベント経由）
# =============================================================================

@app.function(
    "search_function",
    auto_acknowledge=False,  # 手動で ack() を制御（Enterprise Search 必須）
    ack_timeout=10           # デフォルト3秒→10秒に延長（Enterprise Search 必須）
)
def handle_search(ack: Ack, inputs: dict, complete: Complete, fail: Fail):
    """
    Enterprise Search の検索関数ハンドラー。
    Slack から function_executed イベントで呼び出される。
    10秒以内に complete() または fail() を呼び出し、最後に ack() で確認応答する。
    """
    try:
        query = inputs.get("query", "")
        filters = inputs.get("filters", {})
        user_context = inputs.get("user_context", {})
        user_id = user_context.get("user_id") if user_context else None

        logger.info(f"Search request: query={query}, user_id={user_id}")

        # 外部システムから検索結果を取得（独自実装）
        raw_results = my_external_system_search(
            query=query,
            filters=filters,
            user_id=user_id
        )

        # search_results オブジェクトを構築（最大50件）
        search_results = []
        for item in raw_results[:50]:
            search_results.append({
                "external_ref": {
                    "id": item["id"],         # Work Objects の external_ref.id と同じ値を使う
                    "type": "document"         # 任意: 外部システムでのエンティティ型名
                },
                "title": item["title"],       # 必須: 検索結果の見出し
                "description": item["summary"], # 必須: 説明文（AI アンサーにも使用）
                "link": item["url"],           # 必須: 外部システムへの URI
                "date_updated": item["updated_at"],  # 必須: YYYY-MM-DD 形式
                "content": item.get("full_text")     # 任意: AI アンサー向け詳細テキスト
            })

        # 成功を Slack に通知（functions.completeSuccess API を内部で呼び出す）
        complete(outputs={"search_results": search_results})

    except AuthenticationRequired as e:
        # 認証エラー: ユーザーに認証 URL を示すエラーメッセージ
        fail(f"Authentication required. Please visit https://your-app.example.com/auth to authenticate.")

    except Exception as e:
        logger.exception(f"Search failed: {e}")
        # fail() にエラーメッセージを渡すと Slack の検索ページにユーザー向けメッセージとして表示される
        fail(f"Search is temporarily unavailable. Please try again later.")

    finally:
        # complete()/fail() の呼び出し後に ack() で Slack に HTTP 200 を返す
        ack()


# =============================================================================
# 2. フレックスペイン（Work Objects）ハンドラー（entity_details_requested イベント）
# =============================================================================

@app.event("entity_details_requested")
def handle_entity_details(body, client, logger):
    """
    ユーザーが Enterprise Search の検索結果をクリックしたときに呼び出される。
    entity.presentDetails API で Work Object フレックスペインのコンテンツを返す。
    """
    event = body["event"]
    trigger_id = event["trigger_id"]
    external_ref = event.get("external_ref", {})
    entity_id = external_ref.get("id")  # Enterprise Search 結果の external_ref.id
    entity_url = event.get("entity_url")  # entity_id が None の場合のフォールバック
    user_id = event.get("user")
    user_locale = event.get("user_locale", "en-US")

    # Enterprise Search から来た場合、channel/message_ts/thread_ts は提供されない
    # （メッセージコンテキストがないため）

    # ユーザー認証チェック（外部システムへのアクセス制御）
    if not is_user_authenticated(user_id):
        client.entity_presentDetails(
            trigger_id=trigger_id,
            user_auth_required=True,
            user_auth_url=f"https://your-app.example.com/auth?user={user_id}"
        )
        return

    try:
        # 外部システムからエンティティ情報を取得
        item = my_external_system_get_item(entity_id or entity_url)

        # Work Object メタデータを構築
        # entity.presentDetails 向け（chat.unfurl と異なり entities 配列は不要）
        metadata = {
            "entity_type": "slack#/entities/task",  # または file, incident, content_item, item
            "url": entity_url,
            "external_ref": {
                "id": item["id"],
                "type": "document"
            },
            "entity_payload": {
                "attributes": {
                    "title": {"text": item["title"]},
                    "display_type": "Issue",          # Slack UI に表示される型名（例: "Issue", "Page"）
                    "product_name": "My System",      # 外部システム名（デフォルト: アプリ名）
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
                    "status": {
                        "value": item["status"],
                        "tag_color": "green" if item["status"] == "open" else "gray"
                    },
                    "assignee": {
                        "user": {
                            "text": item["assignee_name"],
                            "email": item["assignee_email"]
                        },
                        "type": "slack#/types/user"
                    },
                    "due_date": {
                        "value": item["due_date"],  # YYYY-MM-DD 形式
                        "type": "slack#/types/date"
                    },
                    "created_by": {
                        "user": {"user_id": item["creator_slack_id"]},
                        "type": "slack#/types/user"
                    },
                    "date_updated": {
                        "value": item["updated_at_ts"]  # UNIX タイムスタンプ
                    }
                },
                "actions": {
                    "primary_actions": [
                        {
                            "text": "Close Issue",
                            "action_id": "close_issue",
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
                            "text": "Pin Issue",
                            "action_id": "pin_issue",
                            "value": item["id"]
                        }
                    ]
                },
                "display_order": ["description", "status", "assignee", "due_date", "created_by"]
            }
        }

        # フレックスペインを表示
        client.entity_presentDetails(
            trigger_id=trigger_id,
            metadata=metadata
        )

    except Exception as e:
        logger.exception(f"Failed to present entity details: {e}")
        # エラー時はカスタムエラー画面を表示
        client.entity_presentDetails(
            trigger_id=trigger_id,
            error={
                "status": "custom_partial_view",
                "custom_title": "Error",
                "custom_message": f"Failed to load details. Please try again."
            }
        )


# =============================================================================
# 3. アクションハンドラー（block_actions イベント）
# =============================================================================

@app.action("close_issue")
def handle_close_issue(ack, body, client, logger):
    """
    フレックスペインまたは unfurl の「Close Issue」ボタンクリックを処理する。
    ack() は3秒以内に呼び出す必要がある。
    """
    ack()  # 3秒以内に必須

    container = body.get("container", {})
    entity_url = container.get("entity_url")
    external_ref = container.get("external_ref", {})
    entity_id = external_ref.get("id")
    trigger_id = body.get("trigger_id")
    user_id = body["user"]["id"]

    # container.type で発生元を判別できる:
    # "message_attachment" → unfurl からのアクション
    # "entity_detail" → フレックスペインからのアクション
    container_type = container.get("type")

    try:
        # 外部システムでアクションを実行
        my_external_system_close_issue(entity_id, user_id=user_id)

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
                            "text": "Reopen Issue",
                            "action_id": "reopen_issue",
                            "style": "primary",
                            "value": entity_id
                        }
                    ]
                }
            }
        }

        # フレックスペインを最新状態に更新
        client.entity_presentDetails(
            trigger_id=trigger_id,
            metadata=updated_metadata
        )

    except Exception as e:
        logger.exception(f"Failed to close issue: {e}")
        # エラーはユーザーへの DM で通知
        client.chat_postMessage(
            channel=user_id,
            text=f"Failed to close issue. Please try again."
        )


@app.action("assign_to_me")
def handle_assign_to_me(ack, body, client, logger):
    """assign_to_me ボタンクリックの処理（close_issue と同様のパターン）"""
    ack()
    # ... 実装省略（close_issue と同様のパターン）


@app.action("reopen_issue")
def handle_reopen_issue(ack, body, client, logger):
    """reopen_issue ボタンクリックの処理（close_issue と同様のパターン）"""
    ack()
    # ... 実装省略（close_issue と同様のパターン）


# =============================================================================
# Lambda エントリポイント
# =============================================================================

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)


# =============================================================================
# スタブ関数（実装が必要）
# =============================================================================

class AuthenticationRequired(Exception):
    pass

def my_external_system_search(query, filters, user_id):
    """外部システムから検索結果を取得する（実装が必要）"""
    raise NotImplementedError

def my_external_system_get_item(entity_id):
    """外部システムからエンティティの詳細を取得する（実装が必要）"""
    raise NotImplementedError

def my_external_system_close_issue(entity_id, user_id):
    """外部システムでイシューをクローズする（実装が必要）"""
    raise NotImplementedError

def is_user_authenticated(user_id):
    """ユーザーが外部システムへのアクセス権を持っているか確認する（実装が必要）"""
    return True  # 認証が不要な場合は常に True を返す
```

---

## requirements.txt

```
slack-bolt>=1.18.0
slack-sdk>=3.19.0
```

---

## 環境変数

| 変数名 | 取得元 | 説明 |
|---|---|---|
| `SLACK_BOT_TOKEN` | Slack アプリ設定 → OAuth & Permissions → Bot User OAuth Token（`xoxb-...`） | API 呼び出しに使用 |
| `SLACK_SIGNING_SECRET` | Slack アプリ設定 → Basic Information → App Credentials → Signing Secret | HTTP リクエストの署名検証 |

---

## 実装上の重要なポイント

### 1. `auto_acknowledge=False` + `ack_timeout=10` は Enterprise Search に必須

```python
@app.function(
    "search_function",
    auto_acknowledge=False,
    ack_timeout=10
)
def handle_search(ack, inputs, complete, fail):
    try:
        # 処理...
        complete(outputs={"search_results": results})
    except Exception as e:
        fail(f"エラーメッセージ")
    finally:
        ack()  # complete()/fail() の後に呼ぶ
```

- `auto_acknowledge=True`（デフォルト）だと Bolt が先に `ack()` を呼んでしまうため、`complete()` の前に ACK が発生する
- Enterprise Search は同期的な処理完了（10秒以内）が必要なため、`complete()` → `ack()` の順が重要
- `ack_timeout=10` でデフォルト3秒を10秒に延長（Enterprise Search の制限に合わせる）

### 2. search_results の `external_ref.id` と entity_details_requested の `external_ref.id` は同じ値

```python
# 検索ハンドラー
search_results.append({
    "external_ref": {"id": "doc-123"},  # この ID と
    ...
})

# フレックスペインハンドラー
entity_id = event.get("external_ref", {}).get("id")  # この ID は同じ値になる
item = my_system.get_item(entity_id)  # "doc-123" で外部システムを照会できる
```

### 3. Enterprise Search から開いたフレックスペインでは channel/message_ts が提供されない

```python
@app.event("entity_details_requested")
def handle_entity_details(body, client, logger):
    event = body["event"]
    # これらは Enterprise Search からの場合は None/存在しない
    channel = event.get("channel")    # None になる
    message_ts = event.get("message_ts")  # None になる
    # entity_url と external_ref で外部システムを特定する
    entity_id = event.get("external_ref", {}).get("id")
    entity_url = event.get("entity_url")
```

### 4. entity.presentDetails の metadata スキーマ（chat.unfurl との違い）

`entity.presentDetails` 用のメタデータは `chat.unfurl` の `metadata` とほぼ同じだが、以下が異なる:

```python
# chat.unfurl 用（entities 配列で複数エンティティを返せる）
{
    "entities": [
        {
            "app_unfurl_url": "...",  # ← 必要
            "entity_type": "...",
            "entity_payload": {...}
        }
    ]
}

# entity.presentDetails 用（単一エンティティ、entities 配列なし）
{
    "entity_type": "...",        # ← 直接指定
    "url": "...",               # ← app_unfurl_url ではなく url
    "external_ref": {...},
    "entity_payload": {...}
}
```

### 5. `app.client` vs `client` パラメータ

Bolt ハンドラーの引数に `client` を受け取ると、そのリクエストに紐付いたトークンで認可された SDK クライアントが渡される。

```python
@app.event("entity_details_requested")
def handle_entity_details(body, client, logger):
    # client は既にトークンが設定された WebClient インスタンス
    client.entity_presentDetails(...)  # これが正しい使い方
```

---

## フィルター機能（オプション）

フィルター関数が必要な場合は manifest に `search_filters_function_callback_id` を追加し、対応するハンドラーを実装する。

### manifest への追加

```json
"features": {
  "search": {
    "search_function_callback_id": "search_function",
    "search_filters_function_callback_id": "search_filters_function"
  }
}
```

```json
"functions": {
  "search_filters_function": {
    "title": "Search Filters Function",
    "description": "Returns available search filters",
    "input_parameters": {
      "properties": {
        "user_context": {
          "type": "slack#/types/user_context",
          "title": "User Context"
        }
      },
      "required": []
    },
    "output_parameters": {
      "properties": {
        "filter": {
          "type": "slack#/types/search_filters",
          "title": "Filters"
        }
      },
      "required": ["filter"]
    }
  }
}
```

### Python ハンドラー（フィルター関数）

```python
@app.function("search_filters_function")
def handle_search_filters(inputs: dict, complete: Complete, fail: Fail):
    """
    ユーザーが検索アプリを選択したときにフィルター一覧を返す関数。
    結果は3分間キャッシュされる。
    """
    try:
        user_context = inputs.get("user_context", {})

        # フィルター定義（最大5個）
        filters = [
            {
                "name": "status",
                "display_name": "Status",
                "display_name_plural": "Statuses",
                "type": "multi_select",
                "options": [
                    {"name": "Open", "value": "open"},
                    {"name": "In Progress", "value": "in_progress"},
                    {"name": "Closed", "value": "closed"}
                ]
            },
            {
                "name": "assigned_to_me",
                "display_name": "Assigned to me",
                "type": "toggle"
            }
        ]

        complete(outputs={"filter": filters})

    except Exception as e:
        fail(f"Failed to load filters: {e}")
```

---

## 問題・疑問点

1. **`features.rich_previews` なしで Enterprise Search の検索結果クリックが動作するか**: ドキュメントには `entity_details_requested` の購読のみで Work Objects が使えると記述されている部分もあるが、`features.rich_previews` なしで動作するかは未確認。manifest への `features.rich_previews` 追加を推奨（0068 での結論）。

2. **`entity.presentDetails` の Bolt Python SDK サポート**: 0065 調査時点では "Coming soon" と記載されていた。現在 SDK がネイティブサポートしているかは未確認。`client.entity_presentDetails(...)` として呼べる可能性はあるが、動作しない場合は `client.api_call("entity.presentDetails", ...)` を使う。

3. **`trigger_id` の有効期限**: `entity_details_requested` の `trigger_id` の有効期限がどれくらいか不明（通常の `trigger_id` は3秒だが、フレックスペイン向けは異なる可能性）。

4. **`process_before_response=True` の Enterprise Search への影響**: `process_before_response=True` を設定すると全リスナーが完了するまで HTTP 200 を返さない。`auto_acknowledge=False` と組み合わせた場合の動作（complete → ack の順序）は内部的に確認が必要。
