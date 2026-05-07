# Work Objects Taskエンティティの必須フィールド

## 知りたいこと

Work ObjectsにおけるTaskエンティティで必要になる要素

## 目的

各要素の型や必須かどうかを詳しくしりたい

## 調査サマリー

### 必須フィールドまとめ

**トップレベル（entities 配列内）**:
- `app_unfurl_url`: 必須（unfurl時）、postMessage時は不要
- `url`: 必須
- `external_ref.id`: 必須
- `entity_type`: 必須（`"slack#/entities/task"`）
- `entity_payload`: 必須

**entity_payload.attributes**:
- `title.text`: **唯一の必須フィールド**（string）
- それ以外（`display_id`, `display_type`, `product_name`, `product_icon`, `full_size_preview`, `metadata_last_modified`）: 全て任意

**entity_payload.fields**（Task固有、全て任意）:
- `description.value`（string）、`description.format`（"markdown"、任意）
- `created_by.user`（user_id または text）、`created_by.type`（"slack#/types/user"）
- `date_created.value`（UNIX timestamp）
- `date_updated.value`（UNIX timestamp）
- `assignee.user`（user_id または text）、`assignee.type`（"slack#/types/user"）
- `status.value`（string）、`status.tag_color`（任意）、`status.link`（任意）
- `due_date.value`（YYYY-MM-DD または UNIX timestamp）、`due_date.type`（slack#/types/date または timestamp）
- `priority.value`（string）、`priority.icon`（任意）、`priority.link`（任意）

**entity_payload.custom_fields**（任意、配列）:
各アイテムに `key`（必須）、`label`（必須）、`value`（必須）、`type`（必須）

**entity_payload.actions**（任意）:
各 action に `text`（必須）、`action_id`（必須）。その他は任意

### 重要な注意事項
- `fields` 内の全フィールドは「任意だが推奨」
- 推奨フィールド名（`created_by`, `assignee` など）を守らないと AI answer などダウンストリーム機能が動作しない
- user は `user_id`（Slack ID）か `text`（表示名）のどちらかを使用

## 完了サマリー

`docs/messaging/work-objects-implementation.md` の `### Task` セクション（L781-L789）および attributes, fields の共通スキーマを調査。Task エンティティで**実際に必須なのは `attributes.title.text` のみ**で、`fields` 内の全フィールド（description, created_by, date_created, date_updated, assignee, status, due_date, priority）は全て任意（but recommended）であることを確認した。詳細は `logs/0066_work-object-task-entity-required-fields.md` を参照。
