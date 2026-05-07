# Work Objects manifest.json 設定

## 知りたいこと

Work Objectsを有効にするためにはmanifest.jsonにどのように書けばよいのか

## 目的

Work Objects有効化のために必要な設定値をしりたい

## 調査サマリー

manifest.json で Work Objects を有効にするには `features.rich_previews` が主要なキーであることを確認した。

### 核心: `features.rich_previews`

```json
"features": {
  "rich_previews": {
    "is_active": true,
    "entity_types": [
      "slack#/entities/task",
      "slack#/entities/file",
      "slack#/entities/incident",
      "slack#/entities/content_item",
      "slack#/entities/item"
    ]
  }
}
```

- `is_active: true` で Work Object Previews を有効化（UI の "Work Object Previews" トグルに対応）
- `entity_types` に使用したいエンティティタイプを列挙

### Work Objects に必要な manifest 設定全体

| 設定 | 目的 |
|---|---|
| `features.rich_previews.is_active: true` | Work Object Previews 有効化 |
| `features.rich_previews.entity_types` | 使用するエンティティタイプ |
| `features.unfurl_domains` | link unfurl 対象ドメイン |
| `settings.event_subscriptions.bot_events["link_shared"]` | URL 貼り付け時のイベント受信 |
| `settings.event_subscriptions.bot_events["entity_details_requested"]` | フレックスペイン開放時のイベント受信 |
| `settings.interactivity` | アクションボタン・編集機能の受信 |
| `oauth_config.scopes.bot["links:read", "links:write"]` | link unfurl に必要なスコープ |

詳細サンプルは `logs/0067_work-objects-manifest-config.md` 参照。

## 完了サマリー

2026-05-07 調査完了。`features.rich_previews` が Work Objects（Work Object Previews）を manifest で有効化するキーであることを確認。UI の「Work Object Previews」トグルが `is_active`、entity type 選択が `entity_types` に対応する。link unfurl ベースには加えて `unfurl_domains`・`link_shared` イベント・`links:read`/`links:write` スコープも必要。
