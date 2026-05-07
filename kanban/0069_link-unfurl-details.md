# Link Unfurl 詳細調査

## 知りたいこと

0068の更問い。link unfurlについて詳しく知りたい。Work Objectsとの関係も含めて

## 目的

manifest.jsonに書くべき内容を特定するのに情報が欲しい。link unfurlが必要かどうかの参考情報にしたい。

## 調査サマリー

詳細ログ: `logs/0069_link-unfurl-details.md`

### link unfurl の3種類

1. **Classic**: Slack デフォルト（OpenGraph クロール）
2. **Slack app unfurling**: アプリが登録ドメインURLを検知してカスタムプレビュー提供
3. **Work Objects**: Slack app unfurling のさらなる拡張（リッチプレビュー＋フレックスペイン）

### Work Objects と link unfurl の関係

- Work Objects の unfurl は **link unfurl の拡張**（`work-objects-implementation.md` line 17–20 より明記）
- link unfurl ベースでは `link_shared` → `chat.unfurl`（`metadata` に entity data を含める）
- Enterprise Search ベースでは `entity_details_requested` → `entity.presentDetails`（`link_shared` は不要）

### manifest.json への影響（主要な判断基準）

| 機能 | `link_shared` | `unfurl_domains` | `links:read`/`links:write` |
|---|---|---|---|
| Enterprise Search のみ | 不要 | 不要 | 不要 |
| link unfurl ベースの Work Objects | 必要 | 必要 | 必要 |

### `features.rich_previews` は両シナリオで必要

Work Object Previews（`features.rich_previews`）は、link unfurl 経由でも Enterprise Search 経由でも Work Objects を表示する場合に必要。

## 完了サマリー

2026-05-07 調査完了。link unfurl の3種類（Classic/Slack app unfurling/Work Objects）と仕組みを整理。Work Objects は link unfurl の拡張として設計されており、Enterprise Search 経由の Work Objects では `link_shared`・`unfurl_domains`・`links:read`/`links:write` は全て不要であることを確認。manifest.json 設定の判断基準が明確になった。
