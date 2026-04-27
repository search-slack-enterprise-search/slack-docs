# 調査ログ: manifest.json の invalid additional property エラー調査

## 調査日時
2026-04-27

## 調査ファイル一覧

- `kanban/0063_manifest-invalid-additional-property.md` — タスクファイル
- `docs/reference/app-manifest.md` — App Manifest スキーマリファレンス
- `docs/enterprise-search/developing-apps-with-search-features.md` — Enterprise Search 実装ガイド

## 調査アプローチ

1. `fd -e md . docs/` で manifest 関連ドキュメントを検索 → `docs/reference/app-manifest.md` を特定
2. `rg -l "app_type" docs/` で `app_type` の記載があるドキュメントを検索 → 2件ヒット
3. `reference/app-manifest.md` の settings セクションを全読みして有効フィールドを把握
4. `enterprise-search/developing-apps-with-search-features.md` を読んで Enterprise Search の manifest 例を確認

## 調査結果

### 1. `reference/app-manifest.md` の `settings` セクション (行 637〜837)

`settings` セクションに定義されている有効フィールド一覧（v1/v2 共通）：

| フィールド | 説明 | 必須 |
|---|---|---|
| `settings` | 設定グループ | Optional |
| `settings.allowed_ip_address_ranges` | 許可 IP アドレス配列、最大10件 | Optional |
| `settings.event_subscriptions` | Events API 設定サブグループ | Optional |
| `settings.event_subscriptions.request_url` | Events API リクエスト URL | Optional |
| `settings.event_subscriptions.bot_events` | ボットイベント種別配列、最大100件 | Optional |
| `settings.event_subscriptions.user_events` | ユーザーイベント種別配列、最大100件 | Optional |
| `settings.event_subscriptions.metadata_subscriptions` | メタデータサブスクリプション配列 | Optional |
| `settings.incoming_webhooks` | Incoming Webhooks 設定 | Optional |
| `settings.interactivity` | インタラクティビティ設定サブグループ | Optional |
| `settings.interactivity.is_enabled` | インタラクティビティ有効化フラグ | Required (if using interactivity) |
| `settings.interactivity.request_url` | インタラクティブリクエスト URL | Optional |
| `settings.interactivity.message_menu_options_url` | Options Load URL | Optional |
| `settings.org_deploy_enabled` | 組織全体デプロイ有効化フラグ | Optional |
| `settings.socket_mode_enabled` | Socket Mode 有効化フラグ | Optional |
| `settings.token_rotation_enabled` | トークンローテーション有効化フラグ | Optional |
| `settings.is_hosted` | Slack ホスティングフラグ | Optional |
| `settings.siws_links` | SIWS Links 設定 | Optional |
| `settings.siws_links.initiate_uri` | SIWS Links URI | Optional |
| `settings.function_runtime` | 関数ランタイム種別（`remote` または `slack`）| Required (if using functions) |

**`app_type` は `settings` セクションのどこにも記載されていない。**

### 2. `enterprise-search/developing-apps-with-search-features.md` の manifest 例 (行 46)

Enterprise Search ドキュメントには以下のサンプルコードが記載されている：

```
"settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
        "bot_events": [
            ...
            "function_executed",
            "entity_details_requested"
        ]
    },
    "app_type": "remote",
    "function_runtime": "remote"
}
```

つまり **Enterprise Search ドキュメント自身が `settings.app_type: "remote"` を使うサンプルを掲載している**が、公式スキーマリファレンス (`reference/app-manifest.md`) には `app_type` フィールドの定義が存在しない。

### 3. `rg -l "app_type" docs/` の検索結果

```
docs/enterprise-search/developing-apps-with-search-features.md
docs/reference/methods/team.integrationLogs.md
```

- `team.integrationLogs.md` は API メソッドのリファレンスで、ログの `app_type` フィールドの話であり manifest とは無関係。
- `reference/app-manifest.md` には `app_type` の記載がないことを確認。

### 4. `features.search` フィールドの確認

`reference/app-manifest.md` の `features` セクションには `features.search` についての記載がない。

一方、`enterprise-search/developing-apps-with-search-features.md` 行 7〜33 には：

```
"features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```

- `search_function_callback_id`: 検索結果を収集する関数の callback_id（必須）
- `search_filters_function_callback_id`: 検索フィルターを返す関数の callback_id（オプション）

### 5. エラーの根本原因

`settings.app_type: "remote"` が Slack の manifest スキーマに存在しないフィールドであるため、`invalid additional property` エラーが発生している。

`app_type` は Enterprise Search ドキュメントのサンプルに含まれているが、**実際のスキーマには存在しない誤記載（またはドキュメントの更新漏れ）**と考えられる。

### 6. 追加の問題点：callback_id の不整合

元の manifest.json を確認すると：

```json
"features": {
  "search": {
    "search_function_callback_id": "search"  // "search" を参照
  }
},
"functions": {
  "search_function": { ... }  // キーは "search_function"
}
```

`search_function_callback_id: "search"` は `functions.search` を参照しているが、manifest では `functions.search_function` として定義されており、**参照先が存在しない不整合**がある。

## 修正後の manifest.json

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

変更点：
1. `settings.app_type: "remote"` を**削除**（スキーマ未定義フィールド）
2. `features.search.search_function_callback_id` を `"search"` → `"search_function"` に**修正**（callback_id 不整合の解消）

## 判断・意思決定

- `app_type: "remote"` は Enterprise Search ドキュメントのサンプルに記載されているため、一見有効に見えるが、公式スキーマリファレンスに存在しないため削除が正しい判断。
- `function_runtime: "remote"` は `app_type` と意味的に重複しており、おそらく `app_type` は古い名称か誤った例として Enterprise Search ドキュメントに残っている可能性がある。
- callback_id の不整合はエラーメッセージとは別の問題だが、アプリが正常に動作しないため合わせて修正。

## 会話内容

- ユーザーが manifest.json で `settings.app_type` が invalid additional property エラーを出しているので調査・修正依頼
- 調査の結果、スキーマリファレンスに存在しないフィールドであることが判明
- 追加で callback_id の不整合も発見し合わせて修正提案
