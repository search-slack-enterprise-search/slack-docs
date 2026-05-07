# Work Objects Taskエンティティの必須フィールド

## 調査ファイル一覧

- `docs/messaging/work-objects-implementation.md`
- `docs/messaging/work-objects-overview.md`

## 調査アプローチ

1. `rg -l "task" docs/ -i --glob "*.md" | grep -i "work"` で Work Objects 関連ドキュメントを検索
2. `work-objects-implementation.md` に Task エンティティの詳細スキーマが記載されていることを確認
3. `work-objects-overview.md` で全体像を確認

## 調査結果

### 1. 全体スキーマ（chat.unfurl の metadata 内）

```json
"metadata": {
  "entities": [
    {
      "app_unfurl_url": "...",   // 必須（unfurl時）、postMessage時は不要
      "url": "...",               // 必須
      "external_ref": {           // 必須
        "id": "123",              // 必須
        "type": "document"        // 任意（IDがグローバルにユニークでない場合に使用）
      },
      "entity_type": "slack#/entities/task",  // 必須
      "entity_payload": {}        // 必須（詳細は以下）
    }
  ]
}
```

#### トップレベルフィールドの必須/任意

| フィールド | 必須/任意 | 型 | 説明 |
|-----------|---------|---|------|
| `app_unfurl_url` | 条件付き必須 | string | unfurl時は必須。postMessage時は不要 |
| `url` | 必須 | string | 外部システムのリソースURL。クリック時にここへ遷移 |
| `external_ref.id` | 必須 | string | 外部システムでのリソース一意識別子 |
| `external_ref.type` | 任意 | string | IDがグローバルにユニークでない場合のみ必要 |
| `entity_type` | 必須 | string | `"slack#/entities/task"` |
| `entity_payload` | 必須 | object | エンティティの実データ |

---

### 2. entity_payload スキーマ

```json
{
  "entity_payload": {
    "attributes": {},       // 必須（titleを含む）
    "fields": {},           // 任意（推奨）
    "custom_fields": [],    // 任意
    "display_order": [],    // 任意
    "actions": {}           // 任意
  }
}
```

---

### 3. attributes（エンティティヘッダーの情報）

ドキュメント（work-objects-implementation.md L122-124）の記述:

```json
{
  "attributes": {
    // Required fields
    "title": {
      "text": "Document 123"  // Work Object エンティティのタイトル
    },

    // Optional fields
    "display_id": "123",            // 表示用の文字列ID
    "display_type": "Document",     // リソースの種類。Task entityはデフォルト "Task"
    "product_name": "Slack",        // ヘッダーに表示される製品名。デフォルトはアプリ名
    "product_icon": {               // プロダクトアイコン。デフォルトはアプリアイコン
      "alt_text": "...",
      "url": "https://example.com/icon"  // または slack_file
    },
    "full_size_preview": {
      "is_supported": true,          // 必須（この項目を使う場合）
      "preview_url": "https://...",  // full preview対応時は必須
      "mime_type": "image/png"       // full preview対応時は必須
    },
    "metadata_last_modified": 1741164235  // UNIX timestamp。任意
  }
}
```

#### attributes フィールドの必須/任意まとめ

| フィールド | 必須/任意 | 型 | 説明 |
|-----------|---------|---|------|
| `title.text` | **必須** | string | エンティティのタイトル |
| `display_id` | 任意 | string | 表示用ID |
| `display_type` | 任意 | string | リソース種別。Task entityのデフォルトは `"Task"` |
| `product_name` | 任意 | string | ヘッダー表示の製品名。デフォルトはアプリ名 |
| `product_icon` | 任意 | object | プロダクトアイコン。デフォルトはアプリアイコン |
| `full_size_preview.is_supported` | 条件付き必須 | boolean | full_size_previewを使う場合は必須 |
| `full_size_preview.preview_url` | 条件付き必須 | string | is_supported=true の場合は必須 |
| `full_size_preview.mime_type` | 条件付き必須 | string | is_supported=true の場合は必須 |
| `metadata_last_modified` | 任意 | integer | UNIX timestamp。自動リフレッシュ制御に使用 |

---

### 4. fields（Task エンティティ固有フィールド）

ドキュメント（work-objects-implementation.md L788）のTask固有フィールド:

```json
{
  "fields": {
    "description": {
      "value": "task description here",
      "format": "markdown"  // optional
    },
    "created_by": {
      "user": {
        "user_id": "U0123456"
        // または "text": "John Smith", "email": "..."
      },
      "type": "slack#/types/user"
    },
    "date_created": {
      "value": 1741164235  // UNIX timestamp
    },
    "date_updated": {
      "value": 1741164235  // UNIX timestamp
    },
    "assignee": {
      "user": {
        "text": "John Smith",
        "email": "johnsmith@example.com"
      },
      "type": "slack#/types/user"
    },
    "status": {
      "value": "open",
      "tag_color": "blue",  // optional: "red", "yellow", "green", "gray", "blue"
      "link": "https://example.com/tasks?status=open"  // optional
    },
    "due_date": {
      "value": "2025-06-10",  // "YYYY-MM-DD" または UNIX timestamp integer
      "type": "slack#/types/date"  // または "slack#/types/timestamp"
    },
    "priority": {
      "value": "high",
      "icon": {             // optional
        "alt_text": "...",
        "url": "https://example.com/icon/high-priority.png"
      },
      "link": "https://example.com/tasks?priority=high"  // optional
    }
  }
}
```

#### fields の各フィールドの必須/任意まとめ

全 fields フィールドは**全て任意**（optional but recommended）。

| フィールド | 必須/任意 | 型 | 説明 |
|-----------|---------|---|------|
| `description.value` | 任意 | string | タスクの説明 |
| `description.format` | 任意 | string | `"markdown"` のみ対応 |
| `created_by.user.user_id` | 任意 | string | Slack ユーザーID（user_id か text のどちらかを使用）|
| `created_by.user.text` | 任意 | string | ユーザー表示名（user_id が不明な場合）|
| `created_by.user.email` | 任意 | string | ユーザーのメールアドレス |
| `created_by.type` | 任意 | string | `"slack#/types/user"` |
| `date_created.value` | 任意 | integer | UNIX timestamp |
| `date_updated.value` | 任意 | integer | UNIX timestamp |
| `assignee.user.user_id` | 任意 | string | Slack ユーザーID |
| `assignee.user.text` | 任意 | string | ユーザー表示名 |
| `assignee.user.email` | 任意 | string | ユーザーのメールアドレス |
| `assignee.type` | 任意 | string | `"slack#/types/user"` |
| `status.value` | 任意 | string | タスクのステータス |
| `status.tag_color` | 任意 | string | `"red"`, `"yellow"`, `"green"`, `"gray"`, `"blue"` |
| `status.link` | 任意 | string | ステータスのリンクURL |
| `due_date.value` | 任意 | string \| integer | `"YYYY-MM-DD"` または UNIX timestamp |
| `due_date.type` | 任意 | string | `"slack#/types/date"` または `"slack#/types/timestamp"` |
| `priority.value` | 任意 | string | 優先度レベル |
| `priority.icon` | 任意 | object | アイコン（`alt_text` + `url`）|
| `priority.link` | 任意 | string | 優先度のリンクURL |

---

### 5. custom_fields（任意）

```json
{
  "custom_fields": [
    {
      "key": "ticket_type",    // 必須
      "label": "Ticket Type",  // 必須
      "value": "Epic",         // 必須
      "type": "string"         // 必須
    }
  ]
}
```

| フィールド | 必須/任意 | 型 | 説明 |
|-----------|---------|---|------|
| `key` | **必須** | string | Slack が参照に使うキー |
| `label` | **必須** | string | Work Object ボディに表示されるラベル |
| `value` | **必須** | varies | フィールドの値 |
| `type` | **必須** | string | データ型（下記参照）|

---

### 6. サポートされるデータ型

| 型 | 説明 |
|---|------|
| `string` | 文字列 |
| `integer` | 整数 |
| `boolean` | 真偽値 |
| `array` | 単一型の配列（`item_type`も必要）|
| `slack#/types/user` | Slackユーザー |
| `slack#/types/channel_id` | Slack会話ID |
| `slack#/types/timestamp` | UNIX timestamp |
| `slack#/types/date` | `YYYY-MM-DD`形式の日付 |
| `slack#/types/image` | 画像（`image_url` または `slack_file`）|
| `slack#/types/entity_ref` | 他のWork Objectエンティティへの参照 |
| `slack#/types/link` | URLリンク |
| `slack#/types/email` | メールアドレス |

---

### 7. actions（任意）

```json
{
  "actions": {
    "primary_actions": [],   // 最大2件
    "overflow_actions": []   // 最大5件
  }
}
```

各 action のフィールド:

| フィールド | 必須/任意 | 型 | 説明 |
|-----------|---------|---|------|
| `text` | **必須** | string | ボタンのラベルテキスト |
| `action_id` | **必須** | string | アクションの識別子（最大255文字）|
| `value` | 任意 | string | インタラクションペイロードで送られる値（最大2000文字）|
| `style` | 任意 | string | `"primary"` (緑) または `"danger"` (赤) |
| `url` | 任意 | string | クリック時に開くURL（最大3000文字）|
| `accessibility_label` | 任意 | string | スクリーンリーダー用のラベル（最大75文字）|

---

### 8. 重要な注意事項

- **推奨フィールド名を守る必要がある**: スキーマはバリデーションを通過しても、推奨フィールド名を使わないとダウンストリーム機能（AI answerなど）が正しく動作しない。例：`created_by` ではなく `creator` を使うと動作しない
- **user 識別**: `user_id`（Slack ID）または `text`（表示名）のどちらかを使う。両方は不可
- **email** は `user_id` が不明な場合に有効で、Slackユーザーとマッチすれば自動的にSlackユーザーとして表示される
- **entity_payload のスキーマ**: unfurl (`chat.unfurl`) と flexpane (`entity.presentDetails`) でほぼ同じだが、flexpane では `entities` 配列が不要で `app_unfurl_url` も不要

---

### 9. 最小限の有効なTask entityペイロード例

```json
{
  "entities": [
    {
      "app_unfurl_url": "https://example.com/tasks/123",
      "url": "https://example.com/tasks/123",
      "external_ref": {
        "id": "123"
      },
      "entity_type": "slack#/entities/task",
      "entity_payload": {
        "attributes": {
          "title": {
            "text": "タスクのタイトル"
          }
        },
        "fields": {}
      }
    }
  ]
}
```

## 問題・疑問点

- `fields` 内の各フィールドで `type` を省略可能かどうかの明示的な記述がない箇所がある（例：`description` は `type` なし）。implicitly `string` 扱いと思われる
- `user` フィールドの `user_id` と `text` について「どちらかを使う（両方は不可）」とドキュメントに記載があるが、`email` の扱いは `text` と組み合わせる形になっている（`user_id` との組み合わせは記述なし）
