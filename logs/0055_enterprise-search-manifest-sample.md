# Enterprise Search Slack App manifest.json サンプル作成 — 調査ログ

## 調査日時
2026-04-24

## タスク概要

Bolt + AWS Lambda を使う Enterprise Search アプリ向けに、2種類の manifest.json を作成する。
- **manifest_no_url.json**: Slack App 作成前（URLs なし）
- **manifest_with_url.json**: Lambda デプロイ後（URLs あり）

---

## 調査アプローチ

1. 既存ログ（0039, 0050, 0053, 0054）から必要な設定情報を収集
2. `docs/enterprise-search/developing-apps-with-search-features.md` で必須設定を確認
3. `docs/reference/app-manifest.md` でフィールド仕様を確認
4. `docs/reference/scopes/` でスコープ一覧を確認
5. `docs/reference/methods/apps.user.connection.update.md` で connection reporting スコープを確認

---

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/index.md`
- `docs/enterprise-search/connection-reporting.md`
- `docs/enterprise-search/enterprise-search-access-control.md`
- `docs/reference/app-manifest.md`
- `docs/reference/scopes/search.read.enterprise.md`
- `docs/reference/methods/apps.user.connection.update.md`
- 既存ログ: `logs/0039_enterprise-search-on-aws-lambda.md`
- 既存ログ: `logs/0050_managing-organization-ready-apps.md`
- 既存ログ: `logs/0053_bolt-lambda-best-practices.md`
- 既存ログ: `logs/0054_enterprise-search-interactivity.md`

---

## 調査結果

### 1. manifest.json に必要な設定（Enterprise Search + Bolt + Lambda）

#### 必須設定

`docs/enterprise-search/developing-apps-with-search-features.md` より：

```json
"settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
        "bot_events": [
            "function_executed",
            "entity_details_requested"
        ]
    },
    "app_type": "remote",
    "function_runtime": "remote"
}
```

- `org_deploy_enabled: true` — Enterprise Search はオーグ対応必須
- `function_executed` — 検索時にトリガーされるイベント
- `entity_details_requested` — ユーザーが検索結果クリック時（Work Objects 連携用）
- `app_type: "remote"` — 公式ドキュメントに明示（manifest リファレンスには記載なし）
- `function_runtime: "remote"` — セルフホスト型 Lambda を示す

#### features.search 設定

```json
"features": {
    "search": {
        "search_function_callback_id": "search_function",
        "search_filters_function_callback_id": "search_filters_function"
    }
}
```

- `search_function_callback_id` — 必須。`functions` マップのキー（callback_id）を参照
- `search_filters_function_callback_id` — 任意。検索フィルター関数

#### functions 定義

**search_function の入出力仕様**（developing-apps-with-search-features.md より）：

入力パラメータ：
- `query`: string（必須） — ユーザーの検索クエリ
- `filters`: object（任意） — ユーザーが選択したフィルターのキーバリューペア
- `user_context`: slack#/types/user_context（任意） — 名前は何でもよい

出力パラメータ：
- `search_results`: slack#/types/search_results（必須）

**search_filters_function の入出力仕様**：

入力パラメータ：
- `user_context`: slack#/types/user_context（任意）

出力パラメータ：
- `filter`: slack#/types/search_filters（必須）

#### スコープ

`docs/reference/scopes/` を全件確認した結果：
- `functions:read` のようなスコープは存在しない
- `search:read.enterprise` は Enterprise Search を*利用*する AI エージェント側のスコープであり、Enterprise Search アプリ*提供*側には不要
- `functions.completeSuccess` / `functions.completeError` は `function_executed` イベントの workflow_token を使用するため、bot token のスコープは不要
- org-ready 設定のため、最低1つの bot スコープが必要（`docs/enterprise/developing-for-enterprise-orgs.md`: "Bot スコープがないと次ステップが表示されない"）
- **推奨最小スコープ**: `team:read`（org-ready 設定を有効化するために必要）
- connection reporting を実装する場合: `apps.user.connection.update` は **user token** に `users:write` スコープが必要

#### Lambda URL と Bolt のエンドポイント

- Bolt アプリは event subscriptions と interactivity の両方を同一エンドポイントで受け付ける
- Lambda Function URL（または API Gateway）の URL を両方の request_url に設定する
- 一般的なパス: `https://XXXXXXXX.lambda-url.ap-northeast-1.on.aws/slack/events`

#### 2段階方式が必要な理由

1. Slack App を作成する前は Signing Secret が不明
2. Signing Secret がないと Bolt は起動できない（署名検証のため）
3. Bolt が起動しないと Lambda URL が取得できない
4. Lambda URL がないと manifest に request_url を設定できない

したがって：
- **Step 1**: URL なしの manifest で Slack App を作成 → Signing Secret・App ID を取得
- **Step 2**: Signing Secret を使って Lambda をデプロイ → Lambda URL を取得
- **Step 3**: URL ありの manifest で Slack App を更新

---

## 作成した manifest.json サンプル

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
例: `https://abcdefghij.lambda-url.ap-northeast-1.on.aws/slack/events`

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

## 各フィールドの説明

### URL なし → URL ありの差分

| フィールド | URL なし | URL あり |
|---|---|---|
| `settings.event_subscriptions.request_url` | なし | Lambda URL |
| `settings.interactivity.is_enabled` | なし | `true` |
| `settings.interactivity.request_url` | なし | Lambda URL |

### 重要な注意事項

1. **`event_subscriptions.request_url` と `interactivity.request_url` は同じURL**
   - Bolt は単一エンドポイントで Events と Interactivity の両方を処理する
   - どちらも `https://YOUR_LAMBDA_URL/slack/events` に向ける

2. **`app_type: "remote"`**
   - `docs/reference/app-manifest.md` のリファレンスには記載なし
   - ただし `docs/enterprise-search/developing-apps-with-search-features.md` の公式例に明記されている
   - Enterprise Search の実装時は安全策として含める

3. **`search_filters_function_callback_id` は任意**
   - フィルターが不要なアプリは省略可能
   - 含める場合は `functions` マップにも対応するエントリが必要

4. **bot スコープ `team:read`**
   - Enterprise Search 自体の機能（function_executed ハンドリング + functions.completeSuccess）には専用スコープ不要
   - ただし org-ready 設定（Opt-in）を行うために最低1つの bot スコープが必要
   - connection reporting（apps.user.connection.update）を実装する場合は **user token** で `users:write` が必要

5. **`functions.search_function` の `filters` 入力パラメータの型**
   - ドキュメント上の型定義は `object`
   - manifest v2 形式では `"type": "object"` と記述する

6. **`entity_details_requested` と `interactivity`**
   - `entity_details_requested` は Work Objects のフレックスペインを開くために必要
   - フレックスペインにボタンを表示してクリックを処理するには `interactivity` が必要
   - Work Objects を使わない場合は両方省略可能

---

## デプロイフロー

```
[Step 1] manifest_no_url.json で Slack App を作成
    → Signing Secret と App ID を取得

[Step 2] Signing Secret を AWS Secrets Manager に保存

[Step 3] Lambda をデプロイ（Signing Secret を環境変数または Secrets Manager 経由で参照）
    → Lambda Function URL を取得

[Step 4] manifest_with_url.json の REPLACE_WITH_YOUR_LAMBDA_URL を Lambda URL に置き換え

[Step 5] Slack App 設定画面で manifest_with_url.json をインポートして更新

[Step 6] Org Admin がアプリをオーグレベルでインストール
    → 対象ワークスペースに追加
    → Work Object Previews を設定（UIで操作）
```

---

## 問題・疑問点

1. **`app_type: "remote"` の必要性**: manifest リファレンスには記載がないが、公式の developing-apps 例に含まれている。実際に省略した場合の動作は未確認。

2. **`filters` 入力パラメータの型**: ドキュメントでは "object" とされているが、manifest の `functions` 定義でこの型がそのまま使えるか未確認（`slack#/types/object` のような特殊型が必要かも）。

3. **Connection reporting のスコープ**: `apps.user.connection.update` はユーザートークン（`users:write`）が必要。これを実装するには OAuth フローが必要になる可能性がある。

4. **`search_filters_function` の `required` フィールド**: `required: []`（空配列）が valid かどうか manifest バリデーターで確認が必要。
