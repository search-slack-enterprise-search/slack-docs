# manifest.json の invalid additional property エラー調査

## 知りたいこと

manifest.jsonでinvalid additional propertyとエラーが出た

## 目的

manifest.jsonからSlack Appを作ろうとしたらエラーが出て作成できないので、修正して欲しい。
エラーが出たのは `settings.app_type`。

## manifest.json
```json
{
  "_metadata": { "major_version": 2, "minor_version": 1 },
  "display_information": {
    "name": "TrialEnterpriseSearch",
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
      "search_function_callback_id": "search"
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

## 調査サマリー

### 原因

`settings.app_type` は Slack の App Manifest 公式スキーマ (`reference/app-manifest.md`) に存在しないフィールドであるため、`invalid additional property` エラーが発生している。

- Enterprise Search ドキュメント (`enterprise-search/developing-apps-with-search-features.md`) のサンプルコードには `settings.app_type: "remote"` が記載されているが、スキーマリファレンスには定義がなく、Slack の API は無効フィールドとして拒否する。
- `settings.function_runtime: "remote"` は有効なフィールド（functions を使う場合は必須）。

### 追加の問題点

`features.search.search_function_callback_id: "search"` が参照しているが、`functions` 内のキーは `"search_function"` であり、callback_id が一致していない不整合がある。

### 修正内容

1. `settings.app_type: "remote"` を**削除**（スキーマ未定義フィールド）
2. `features.search.search_function_callback_id` を `"search"` → `"search_function"` に**修正**

### 修正後の manifest.json

```json
{
  "_metadata": { "major_version": 2, "minor_version": 1 },
  "display_information": {
    "name": "TrialEnterpriseSearch",
    "description": "Enterprise Search app for internal data sources",
    "background_color": "#2c2d30"
  },
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "bot_events": ["function_executed"]
    },
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

## 完了サマリー

`settings.app_type` は Slack App Manifest スキーマに存在しないフィールドであり、削除することでエラーが解消される。`settings.function_runtime: "remote"` は有効なフィールドであり、そのまま残す。また `features.search.search_function_callback_id` の callback_id 不整合も合わせて修正した。