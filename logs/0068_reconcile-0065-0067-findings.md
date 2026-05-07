# 0065・0067の調査結果統合と正しい情報の整理

## 調査情報

- タスクファイル: `kanban/0068_reconcile-0065-0067-findings.md`
- 調査日: 2026-05-07
- 調査者: Claude Code (kanban スキル)
- 前提タスク:
  - 0065: `検索→リッチプレビュー→アクション の実装詳細`（logs/0065_search-rich-preview-actions-detail.md）
  - 0067: `Work Objects manifest.json 設定`（logs/0067_work-objects-manifest-config.md）

---

## 調査ファイル一覧

- `kanban/0065_search-rich-preview-actions-detail.md`（サマリー読み込み）
- `logs/0065_search-rich-preview-actions-detail.md`（詳細ログ読み込み）
- `kanban/0067_work-objects-manifest-config.md`（サマリー読み込み）
- `logs/0067_work-objects-manifest-config.md`（詳細ログ読み込み）
- `docs/reference/app-manifest.md`（line 365–393: `features.rich_previews` 定義の確認）
- `docs/messaging/work-objects-overview.md`（line 87–91: Enterprise Search と Work Objects の関係）
- `docs/enterprise-search/developing-apps-with-search-features.md`（line 38–47: manifest 設定例）
- `docs/messaging/work-objects-implementation.md`（Work Object Previews UI 手順の確認）
- `kanban/0055_enterprise-search-manifest-sample.md`（既存サンプル確認）
- `kanban/0056_enterprise-search-manifest-search-only.md`（既存サンプル確認）

---

## 調査アプローチ

1. 0065・0067 の kanban ファイル（サマリー）と logs（詳細）を読んで相違点を抽出
2. 相違点の根拠となるドキュメントを直接読んで検証
3. 「どちらが正しいか」を判断してまとめた

---

## 相違点の一覧

以下の3点が主な相違点・矛盾点として特定された。

---

### 相違点A: `features.rich_previews` の manifest 記載有無（最重要）

#### 0065 の記述

サマリーテーブル（kanban/0065, 必要な設定欄）:
> | App settings | Work Object Previews | GUI で Work Object のエンティティタイプを有効化 |

→ manifest のキーとして `features.rich_previews` を明示せず「GUI の App Settings で有効化」という表現に留めている。  
→ 0065 の manifest JSON サンプル（logs/0065, line 70–143）にも `features.rich_previews` が**含まれていない**。

#### 0067 の記述

サマリー・ログ双方で明示:
> `features.rich_previews` が Work Objects の manifest 設定キーである

```json
"features": {
  "rich_previews": {
    "is_active": true,
    "entity_types": [
      "slack#/entities/task",
      ...
    ]
  }
}
```

→ UI の「Work Object Previews トグル」= manifest の `features.rich_previews.is_active: true`  
→ UI の「entity type 選択」= manifest の `features.rich_previews.entity_types: [...]`

#### ドキュメントによる検証

`docs/reference/app-manifest.md`（line 365–393）:
> `features.rich_previews` — A subgroup of settings that describe rich previews configuration. Optional.  
> `features.rich_previews.is_active` — A boolean that specifies whether or not rich previews are enabled. Optional.  
> `features.rich_previews.entity_types` — An array of strings containing entity types for rich previews. Optional.

`docs/messaging/work-objects-overview.md`（line 89）:
> You can define the type of Work Objects for your search results, such as an item, within the **Work Object Previews view within app settings**.

`docs/messaging/work-objects-implementation.md`（line 7–13）:
> First, you must enable the Work Objects feature on your app. To do so, perform the following steps:  
> 1. Visit https://api.slack.com/apps and select your app.  
> 2. Navigate to **Work Object Previews** under the left sidebar menu.  
> 3. Enable the toggle.  
> 4. Select the entity type(s) that you would like to add to your app.  
> 5. Click **Save**.

#### 正しい情報

**0067 が正しい。** `features.rich_previews` は manifest のキーとして存在し、UI の「Work Object Previews」設定に対応する。  
**0065 の manifest サンプルは不完全**であり、Work Objects（flexpane/アクション）を使うには `features.rich_previews` を manifest に追加する必要がある。

**補足（未解決の疑問点）**: 0067 の詳細ログでは「`features.rich_previews` なしでも Enterprise Search から Work Objects が機能するかもしれない」という可能性が残っていた。ドキュメント上は Enterprise Search でも `Work Object Previews` での設定を求めているため、**原則として `features.rich_previews` の追加が必要**と判断するのが安全。

---

### 相違点B: `links:read` / `links:write` スコープの必要性

#### 0065 の記述

**サマリーテーブル**:
> | Bot スコープ | `links:read`, `links:write` |

→ 一見「常に必要」のように見える。

**ログ詳細**（line 670）:
> `links:read` / `links:write` スコープと `unfurl_domains` は Work Objects の link unfurl シナリオに必要

→ ログでは「link unfurl シナリオに必要」と正確に記述している。サマリー表の表現がミスリードを招きやすかった。

#### 0067 の記述

サマリーテーブル:
> `oauth_config.scopes.bot["links:read", "links:write"]` — link unfurl に必要なスコープ

→ 「link unfurl に必要」と明確に限定している。

#### ドキュメントによる検証

`docs/messaging/unfurling-links-in-messages.md`（line 44–45）で `links:read` / `links:write` は URL unfurl のためのスコープと定義されている。  
Enterprise Search からの flexpane 表示（`entity_details_requested` → `entity.presentDetails`）では `chat.unfurl` API を使わないため、これらのスコープは不要。

#### 正しい情報

**`links:read` / `links:write` スコープは `chat.unfurl` API（link unfurl シナリオ）を使う場合にのみ必要**。  
Enterprise Search から検索結果をクリックして flexpane を開くだけのシナリオ（`entity_details_requested` + `entity.presentDetails`）では不要。  
0067 の表現の方が正確。0065 のサマリーテーブルは紛らわしいが、ログ詳細では正しく記述されている。

---

### 相違点C: `bot_events` の組み合わせ（矛盾ではなく用途の違い）

#### 0065 の記述

Enterprise Search + Work Objects の文脈:
> `function_executed` + `entity_details_requested`

→ `link_shared` は不要としている（link unfurl を使わない前提）

#### 0067 の記述

Work Objects（link unfurl 全機能）の文脈:
> `link_shared` + `entity_details_requested`

→ `function_executed` は含まれていない（Enterprise Search を使わない前提）

#### 正しい情報

**これは矛盾ではなく、フォーカスの違いである。** 正しい使い分けは以下の通り:

| シナリオ | 必要な bot_events |
|---|---|
| Enterprise Search のみ（link unfurl なし） | `function_executed`, `entity_details_requested` |
| link unfurl + Work Objects（Enterprise Search なし） | `link_shared`, `entity_details_requested` |
| Enterprise Search + link unfurl + Work Objects（全機能） | `function_executed`, `link_shared`, `entity_details_requested` |

---

## 統合後の正しい manifest 設定（Enterprise Search + Work Objects + link unfurl 全機能版）

```json
{
  "_metadata": {
    "major_version": 2,
    "minor_version": 1
  },
  "display_information": {
    "name": "My Enterprise Search App",
    "description": "Enterprise Search + Work Objects app",
    "background_color": "#2c2d30"
  },
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "request_url": "https://REPLACE_WITH_YOUR_LAMBDA_URL/slack/events",
      "bot_events": [
        "function_executed",
        "link_shared",
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
    "unfurl_domains": [
      "your-domain.example.com"
    ],
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
        "team:read",
        "links:read",
        "links:write"
      ]
    }
  },
  "functions": {
    "search_function": {
      "title": "Search Function",
      "description": "Returns search results for the given query",
      "input_parameters": {
        "properties": {
          "query": { "type": "string", "title": "Query" },
          "filters": { "type": "object", "title": "Filters" },
          "user_context": { "type": "slack#/types/user_context", "title": "User Context" }
        },
        "required": ["query"]
      },
      "output_parameters": {
        "properties": {
          "search_results": { "type": "slack#/types/search_results", "title": "Search Results" }
        },
        "required": ["search_results"]
      }
    }
  }
}
```

### Enterprise Search のみ（link unfurl なし）の場合の差分

link unfurl 不要なら以下を除外:
- `features.unfurl_domains`
- `settings.event_subscriptions.bot_events["link_shared"]`
- `oauth_config.scopes.bot["links:read"]`
- `oauth_config.scopes.bot["links:write"]`

---

## 問題・疑問点

1. **`features.rich_previews` なしで Enterprise Search から Work Objects が機能するかどうか**: ドキュメントからは確定できない。「Work Object Previews で entity type を定義する」という記述は必要性を示唆しているが、省略した場合の動作は未検証。
2. **0055/0056 の manifest サンプルに `features.rich_previews` が含まれていない点**: これらは Enterprise Search 全体のサンプルとして使われており、Work Objects を組み合わせた場合には `features.rich_previews` を追加する必要がある（既存サンプルの更新要否を検討）。
