# 検索ハンドラーの external_ref type に Work Objects Task エンティティを使う方法

## 知りたいこと

0070の更問い。
検索ハンドラーにおいて、external_refのtypeが "document"になっているが、Work ObjectsのTaskエンティティを使いたい場合もこれで良いのか？

## 目的

何が正しいレスポンスなのかを知りたい。

## 調査サマリー

### 結論

**`external_ref.type = "document"` のままでも Work Objects Task エンティティは問題なく使える。**

`external_ref.type` と `entity_type` は**完全に別のフィールド**:

| フィールド | 役割 |
|---|---|
| `external_ref.type` | 外部ソースシステムでのエンティティ型（Optional、任意文字列） |
| `entity_type` | Slack Work Objects のエンティティ型（`"slack#/entities/task"` 等） |

### 重要ポイント

1. `external_ref.type` は Optional で「IDがグローバルに一意でない場合や取得時に使う内部識別子」
2. Work Objects Task を使う場合は `entity.presentDetails` の `metadata.entity_type` を `"slack#/entities/task"` にする
3. `external_ref.type` は `"document"` のまま、`"task"` に変更、省略のどれでも動作する
4. **必須**: 検索ハンドラーの `external_ref.id` と `entity.presentDetails` の `external_ref.id` を同一値にすること
5. `entity_details_requested` イベントのペイロードには検索ハンドラーで指定した `external_ref.type` がそのまま含まれる（アイテム取得ロジックで使いたい場合はここから参照可）
6. 一度設定した `external_ref`（id・type）は変更してはならない（Related Conversations 追跡に使用）

### 出典

- `docs/enterprise-search/developing-apps-with-search-features.md` — `external_ref` object 仕様
- `docs/messaging/work-objects-implementation.md` — chat.unfurl の metadata サンプル
- `docs/messaging/work-objects-overview.md` — external_ref の変更禁止

## 完了サマリー

`external_ref.type`（ソースシステム内部の型識別子）と `entity_type`（Slack Work Objects のエンティティ型）は独立したフィールドであることを確認。検索ハンドラーの `"type": "document"` は Work Objects Task 利用の妨げにならない。Work Objects Task を有効にするには `entity.presentDetails` の `metadata.entity_type` を `"slack#/entities/task"` にするだけで十分。詳細は `logs/0075_external-ref-type-for-work-objects-task.md` を参照。
