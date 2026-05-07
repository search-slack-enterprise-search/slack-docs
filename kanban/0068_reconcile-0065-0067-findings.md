# 0065・0067の調査結果統合と正しい情報の整理

## 知りたいこと

0065と0067で少し言っていることが異なる。双方の調査結果を統合して、正しい情報を整理してください。

## 目的

正しい情報が欲しい。

## 調査サマリー

0065 と 0067 の主な相違点は3点。詳細ログ: `logs/0068_reconcile-0065-0067-findings.md`

### 相違点A: `features.rich_previews`（最重要・0065 が不正確）

**0065**: サマリー表では「App Settings の GUI で有効化」と記載し、manifest キーを明示せず。manifest サンプルにも `features.rich_previews` が含まれていない。

**0067**: `features.rich_previews.is_active: true` + `features.rich_previews.entity_types` が manifest のキーであることを明示。

**正しい情報（0067 が正しい）**: `features.rich_previews` は manifest に必要。UI の「Work Object Previews トグル」= `features.rich_previews.is_active`、entity type 選択 = `features.rich_previews.entity_types`。ドキュメント（`docs/reference/app-manifest.md` line 365–393、`docs/messaging/work-objects-overview.md` line 89）で確認済み。**0055/0056 の manifest サンプルは Work Objects を使う場合に `features.rich_previews` の追加が必要**。

---

### 相違点B: `links:read` / `links:write` スコープの必要性（0065 サマリー表が紛らわしい）

**0065 サマリー表**: Bot スコープとして `links:read`, `links:write` を記載（必須のように見える）。

**0067**: 「link unfurl に必要なスコープ」と明確に限定。

**正しい情報（0067 が正確）**: `chat.unfurl` API（link unfurl）を使う場合のみ必要。Enterprise Search から flexpane を開くだけ（`entity_details_requested` → `entity.presentDetails`）なら不要。0065 のログ詳細では正確に記述されていたが、サマリー表の表現がミスリードを招いた。

---

### 相違点C: bot_events（矛盾ではなく用途の違い）

| シナリオ | 必要な bot_events |
|---|---|
| Enterprise Search のみ（0065 の対象） | `function_executed`, `entity_details_requested` |
| link unfurl + Work Objects（0067 の対象） | `link_shared`, `entity_details_requested` |
| 全機能（Enterprise Search + link unfurl + Work Objects） | `function_executed`, `link_shared`, `entity_details_requested` |

---

### 統合後の manifest（Enterprise Search + Work Objects + link unfurl 全機能版）

```json
"settings": {
  "org_deploy_enabled": true,
  "event_subscriptions": {
    "request_url": "https://REPLACE_WITH_YOUR_LAMBDA_URL/slack/events",
    "bot_events": ["function_executed", "link_shared", "entity_details_requested"]
  },
  "interactivity": { "is_enabled": true, "request_url": "https://REPLACE_WITH_YOUR_LAMBDA_URL/slack/events" },
  "app_type": "remote", "function_runtime": "remote"
},
"features": {
  "search": { "search_function_callback_id": "search_function" },
  "unfurl_domains": ["your-domain.example.com"],
  "rich_previews": {
    "is_active": true,
    "entity_types": ["slack#/entities/task"]
  }
},
"oauth_config": { "scopes": { "bot": ["team:read", "links:read", "links:write"] } }
```

link unfurl なし（Enterprise Search のみ）の場合は `unfurl_domains`・`link_shared`・`links:read`・`links:write` を除外。

## 完了サマリー

2026-05-07 調査完了。0065（Enterprise Search フロー詳細）と 0067（Work Objects manifest 設定）の相違点を特定・統合した。最大の相違点は `features.rich_previews`：0065 の manifest サンプルは不完全で、Work Objects を使うには manifest に `features.rich_previews` の追加が必要（0067 が正しい）。`links:read`/`links:write` は link unfurl 使用時のみ必要。bot_events は用途の違いであり矛盾ではない。
