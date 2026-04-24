# Enterprise Search のみの最小 manifest.json サンプル — 調査ログ

## 調査日時
2026-04-24

## タスク概要

0055（Bolt + Lambda の manifest.json サンプル）の更問い。
Filter（検索フィルター）と Work Objects（フレックスペイン・ボタン）を省いた、
**Search のみの最小 manifest.json** を作成する。

---

## 調査アプローチ

本タスクは新規ドキュメント調査を要しない。
0055 の調査ログ（`logs/0055_enterprise-search-manifest-sample.md`）で確認した知識を元に、
省略可能な設定を特定して差分を整理する。

---

## 調査ファイル一覧

- 既存ログ: `logs/0055_enterprise-search-manifest-sample.md`（主要参照元）
- `docs/enterprise-search/developing-apps-with-search-features.md`（任意フィールド確認）

---

## 調査結果

### 0055 の manifest から省略するフィールド

| フィールド | 省略理由 |
|---|---|
| `features.search.search_filters_function_callback_id` | フィルター機能はオプション。ドキュメント記載:「Optional」 |
| `functions.search_filters_function` | フィルター関数の定義。上記を省けば不要 |
| `settings.event_subscriptions.bot_events["entity_details_requested"]` | Work Objects フレックスペイン用。Work Objects を使わなければ不要 |
| `settings.interactivity` (URL あり版のみ) | Work Objects のボタンクリック受信用。Work Objects なしでは不要 |

### 残す必須フィールド

| フィールド | 理由 |
|---|---|
| `settings.org_deploy_enabled: true` | Enterprise Search の必須要件 |
| `settings.event_subscriptions.bot_events["function_executed"]` | 検索リクエスト受信に必須 |
| `settings.app_type: "remote"` | 公式例に記載あり |
| `settings.function_runtime: "remote"` | セルフホスト型 Lambda |
| `features.search.search_function_callback_id` | 検索関数の参照（必須） |
| `functions.search_function` | 検索関数の定義（必須） |
| `oauth_config.scopes.bot["team:read"]` | org-ready Opt-in のために最低1スコープ必要 |

### search_function の入力パラメータ（Search のみ版）

0055 で確認した仕様（`developing-apps-with-search-features.md`）より：
- `query`: string（必須）
- `filters`: object（任意）← フィルター関数を使わない場合でもこのパラメータ自体は残せる。ただし常に空 object になる
- `user_context`: slack#/types/user_context（任意）

**Search のみ版の判断**:
- `filters` パラメータは完全に省略可能（必須ではない）
- `user_context` は外部認証やユーザー固有の結果を返す場合に有用だが、汎用検索であれば省略可能

---

## 作成した manifest.json サンプル（Search のみ・最小版）

### manifest_no_url_search_only.json（Slack App 作成前・URLs なし・Search のみ）

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
        "function_executed"
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

---

### manifest_with_url_search_only.json（Lambda デプロイ後・URLs あり・Search のみ）

`REPLACE_WITH_YOUR_LAMBDA_URL` を実際の Lambda Function URL に置き換える。

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
        "function_executed"
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

---

## 0055 との差分まとめ

### URL なし版の差分

```diff
 "settings": {
   "event_subscriptions": {
     "bot_events": [
-      "function_executed",
-      "entity_details_requested"   ← Work Objects 用。削除
+      "function_executed"
     ]
   }
 },
 "features": {
   "search": {
-    "search_function_callback_id": "search_function",
-    "search_filters_function_callback_id": "search_filters_function"  ← フィルター用。削除
+    "search_function_callback_id": "search_function"
   }
 },
 "functions": {
   "search_function": { ... },  ← そのまま
-  "search_filters_function": { ... }  ← フィルター関数。削除
 }
```

### URL あり版の追加差分（URL なし版との差分）

```diff
 "settings": {
   "event_subscriptions": {
+    "request_url": "https://REPLACE_WITH_YOUR_LAMBDA_URL/slack/events",
     "bot_events": ["function_executed"]
   },
-  "interactivity": {                           ← Work Objects ボタン用。削除
-    "is_enabled": true,
-    "request_url": "https://REPLACE..."
-  }
 }
```

---

## 機能拡張時の追加方法

将来的に機能を追加する際は以下を順に足していく：

1. **フィルター追加**:
   - `features.search.search_filters_function_callback_id: "search_filters_function"` を追加
   - `functions.search_filters_function` を追加
   - `functions.search_function.input_parameters.properties.filters` を追加（任意）

2. **Work Objects（フレックスペイン）追加**:
   - `settings.event_subscriptions.bot_events` に `"entity_details_requested"` を追加
   - URL あり版は `settings.interactivity` を追加
   - アプリ設定画面の「Work Object Previews」をUIで有効化

---

## 問題・疑問点

- `user_context` パラメータを省略した場合、Slack はそのパラメータなしで `function_executed` イベントを送信する。ユーザー認証が不要であれば省略可能。
- `filters` パラメータを `search_function` の input_parameters から省略する場合: フィルター関数がなくてもこのパラメータを定義しておくことは無害だが、フィルター関数がない場合は常に空になるため省略した。
