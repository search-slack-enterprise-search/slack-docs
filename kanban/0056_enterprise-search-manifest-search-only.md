# Enterprise Search のみの最小 manifest.json サンプル

## 知りたいこと

0055の更問い。FilterとWork Objectsを無効化したサンプルが欲しい。

## 目的

まず最初にsearchだけ有効化した物を作りたい

## 調査サマリー

0055 の manifest から Filter と Work Objects に関する設定を除いた最小版を作成した。

### 0055 からの削除箇所

| 削除フィールド | 理由 |
|---|---|
| `event_subscriptions.bot_events["entity_details_requested"]` | Work Objects 用（不要） |
| `features.search.search_filters_function_callback_id` | フィルター機能（不要） |
| `functions.search_filters_function` | フィルター関数定義（不要） |
| `settings.interactivity`（URL あり版） | Work Objects ボタン受信用（不要） |

### manifest_no_url_search_only.json（URLs なし）

```json
{
  "_metadata": { "major_version": 2, "minor_version": 1 },
  "display_information": {
    "name": "My Enterprise Search App",
    "description": "Enterprise Search app for internal data sources",
    "background_color": "#2c2d30"
  },
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "bot_events": ["function_executed"]
    },
    "app_type": "remote",
    "function_runtime": "remote",
    "socket_mode_enabled": false,
    "token_rotation_enabled": false
  },
  "features": {
    "bot_user": { "display_name": "My Search Bot", "always_online": false },
    "search": {
      "search_function_callback_id": "search_function"
    }
  },
  "oauth_config": { "scopes": { "bot": ["team:read"] } },
  "functions": {
    "search_function": {
      "title": "Search Function",
      "description": "Returns search results for the given query from internal data sources",
      "input_parameters": {
        "properties": {
          "query": { "type": "string", "title": "Query", "description": "The search query string" },
          "user_context": { "type": "slack#/types/user_context", "title": "User Context", "description": "Context of the user performing the search" }
        },
        "required": ["query"]
      },
      "output_parameters": {
        "properties": {
          "search_results": { "type": "slack#/types/search_results", "title": "Search Results", "description": "The search results returned by the app" }
        },
        "required": ["search_results"]
      }
    }
  }
}
```

### manifest_with_url_search_only.json（URLs あり）

上記と同じ構成で `settings.event_subscriptions.request_url` を追加。**interactivity は含まない**。

```json
"settings": {
  "org_deploy_enabled": true,
  "event_subscriptions": {
    "request_url": "https://REPLACE_WITH_YOUR_LAMBDA_URL/slack/events",
    "bot_events": ["function_executed"]
  },
  "app_type": "remote",
  "function_runtime": "remote",
  "socket_mode_enabled": false,
  "token_rotation_enabled": false
}
```

詳細は `logs/0056_enterprise-search-manifest-search-only.md` 参照。

## 完了サマリー

2026-04-24 調査完了。Filter と Work Objects を除いた Search のみの最小 manifest.json（URL なし・URL あり）を作成した。機能拡張時の追加方法もログに記録済み。
