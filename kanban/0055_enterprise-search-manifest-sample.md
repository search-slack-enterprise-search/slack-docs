# Enterprise Search Slack App manifest.json サンプル作成

## 知りたいこと

EnterpriseSearchのための Slack Appのmanifest.jsonのサンプルを作成して欲しい

## 目的

BoltフレームワークとAWS Lambdaを使う場合、URLを含まないSlack App作成前のmanifest.jsonとURLを含むmanifest.jsonが必要になる。
(Slack App作成前にはsignature verifyのためのsecretがわからないため)。
それを作ってもらいたい。

## 調査サマリー

2種類の manifest.json サンプルを作成した。詳細は `logs/0055_enterprise-search-manifest-sample.md` 参照。

### manifest_no_url.json（Slack App 作成前・URLs なし）

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
      "search_function_callback_id": "search_function",
      "search_filters_function_callback_id": "search_filters_function"
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
    },
    "search_filters_function": {
      "title": "Search Filters Function",
      "description": "Returns available search filters for this app",
      "input_parameters": {
        "properties": {
          "user_context": {
            "type": "slack#/types/user_context",
            "title": "User Context",
            "description": "Context of the user performing the search"
          }
        },
        "required": []
      },
      "output_parameters": {
        "properties": {
          "filter": {
            "type": "slack#/types/search_filters",
            "title": "Filters",
            "description": "Available search filters (up to 5)"
          }
        },
        "required": [
          "filter"
        ]
      }
    }
  }
}
```

---

### manifest_with_url.json（Lambda デプロイ後・URLs あり）

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
      "search_function_callback_id": "search_function",
      "search_filters_function_callback_id": "search_filters_function"
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
    },
    "search_filters_function": {
      "title": "Search Filters Function",
      "description": "Returns available search filters for this app",
      "input_parameters": {
        "properties": {
          "user_context": {
            "type": "slack#/types/user_context",
            "title": "User Context",
            "description": "Context of the user performing the search"
          }
        },
        "required": []
      },
      "output_parameters": {
        "properties": {
          "filter": {
            "type": "slack#/types/search_filters",
            "title": "Filters",
            "description": "Available search filters (up to 5)"
          }
        },
        "required": [
          "filter"
        ]
      }
    }
  }
}
```

---

### 2つの manifest の差分

| フィールド | URL なし | URL あり |
|---|---|---|
| `settings.event_subscriptions.request_url` | なし | Lambda URL |
| `settings.interactivity.is_enabled` | なし | `true` |
| `settings.interactivity.request_url` | なし | Lambda URL |

### デプロイフロー

```
[Step 1] manifest_no_url.json で Slack App を作成 → Signing Secret 取得
[Step 2] Signing Secret を AWS Secrets Manager に保存
[Step 3] Lambda をデプロイ → Lambda Function URL 取得
[Step 4] manifest_with_url.json の REPLACE_WITH_YOUR_LAMBDA_URL を実際の URL に置き換え
[Step 5] Slack App 設定でmanifest_with_url.json をインポートして更新
[Step 6] Org Admin がアプリをオーグインストール → ワークスペース追加
```

### 注意事項

- `event_subscriptions.request_url` と `interactivity.request_url` は同じ URL（Bolt は単一エンドポイントで両方処理）
- `app_type: "remote"` は manifest リファレンスには記載なし（developing-apps 公式例には記載あり）
- bot スコープ `team:read` は Enterprise Search 機能自体に必要ではないが org-ready 設定のために最低1つ必要
- connection reporting（apps.user.connection.update）はユーザートークンが必要（manifest には影響なし）

## 完了サマリー

2026-04-24 調査完了。Bolt + Lambda 用の2種類の manifest.json サンプルを作成した。URL なし版は Slack App 作成時に使用し、URL あり版は Lambda デプロイ後に Slack App を更新する際に使用する。
