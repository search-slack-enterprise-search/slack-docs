# ログ: 検索ハンドラーの external_ref type に Work Objects Task エンティティを使う方法

## 調査概要

- **タスク番号**: 0075
- **調査日時**: 2026-05-07
- **前提タスク**: 0070（link unfurl なしの manifest.json と実装まとめ）

---

## 調査ファイル一覧

1. `kanban/0070_manifest-and-impl-without-link-unfurl.md` — 前回のコンテキスト確認
2. `kanban/0066_work-object-task-entity-required-fields.md` — Task エンティティの必須フィールド確認
3. `docs/enterprise-search/developing-apps-with-search-features.md` — external_ref object の仕様
4. `docs/reference/events/entity_details_requested.md` — イベントペイロード確認
5. `docs/reference/methods/entity.presentdetails.md` — entity.presentDetails のメタデータ仕様
6. `docs/messaging/work-objects-overview.md` — external_ref に関する注意事項
7. `docs/messaging/work-objects-implementation.md` — external_ref の定義と chat.unfurl での使用例

---

## 調査結果

### 1. `external_ref.type` の仕様

**出典**: `docs/enterprise-search/developing-apps-with-search-features.md` L169-L175

```
`type`

An optional internal type for entity in the source system. Only needed if the ID
is not globally unique or needed when retrieving the item.

string

Optional
```

**重要ポイント**:
- `external_ref.type` は **Optional**（必須ではない）
- 目的は「ソースシステム（外部システム）内部でのエンティティ型識別」
- IDがグローバルに一意でない場合や、アイテム取得時に必要な場合のみ使用

### 2. `external_ref.type` と Work Objects entity_type は完全に別概念

`external_ref.type` と Work Objects の `entity_type` は**まったく別のフィールド**:

| フィールド | 値の例 | 役割 |
|---|---|---|
| `external_ref.type` | `"document"`, `"task"`, `"issue"` 等 任意の文字列 | 外部（ソース）システムでのエンティティ型 |
| `entity_type` | `"slack#/entities/task"`, `"slack#/entities/file"` | Slack が定義した Work Objects エンティティ型 |

`entity_type` は `entity.presentDetails` の `metadata` オブジェクト内で指定する（`external_ref.type` ではない）。

**出典**: `docs/messaging/work-objects-implementation.md` L26（chat.unfurl の metadata サンプル）

```json
"metadata": {
  "entities": [{
    "external_ref": {
      "id": "123",
      "type": "document"  // ← ソースシステム内部の型（任意）
    },
    "entity_type": "slack#/entities/file",  // ← Slack Work Objects のエンティティ型
    "entity_payload": {}
  }]
}
```

### 3. Work Objects Task エンティティを使う場合の正しい構成

検索ハンドラー（`function_executed`）での返却値:

```python
{
    "external_ref": {"id": r["id"], "type": "task"},  # type は任意・何でもよい（"document"のままでも可）
    "title": r["title"],
    "description": r["summary"],
    "link": r["url"],
    "date_updated": r["updated_at"],
}
```

フレックスペインハンドラー（`entity_details_requested`）での `entity.presentDetails` 呼び出し:

```python
metadata = {
    "entity_type": "slack#/entities/task",  # ← ここで Task エンティティを指定
    "url": entity_url,
    "external_ref": {"id": entity_id},      # ← search の外_ref.id と同じ値を使用
    "entity_payload": {
        "attributes": {"title": {"text": item["title"]}},
        ...
    }
}
client.entity_presentDetails(trigger_id=trigger_id, metadata=metadata)
```

### 4. `external_ref.id` の一致が必須

**出典**: `docs/enterprise-search/developing-apps-with-search-features.md` L163

> A unique identifier for referencing within the search results. **If your app implements Work Objects, this should be same value used for that implementation.**

検索ハンドラーで返す `external_ref.id` と、`entity.presentDetails` で渡す `external_ref.id` は**同一値**でなければならない。

### 5. `external_ref` の変更禁止

**出典**: `docs/messaging/work-objects-overview.md` L98

> The `external_ref` format or IDs must not change for a given Work Object, as it is used for related conversations tracking.

一度設定した `external_ref`（IDおよびtype）は変更してはならない。Related Conversations 追跡に使用されているため。

### 6. entity_details_requested イベントに `type` は含まれる

**出典**: `docs/reference/events/entity_details_requested.md` — イベントペイロードサンプル

```json
"external_ref": {
    "id": "123",
    "type": "my-type"   // ← 検索ハンドラーで指定した type がそのまま返ってくる
}
```

`entity_details_requested` のペイロードには、検索ハンドラーで指定した `external_ref.type` がそのまま含まれる。アイテム取得ロジックで `type` を使いたい場合はここから参照できる。

---

## 結論

**`external_ref.type` が `"document"` でも Work Objects Task エンティティは問題なく使える。**

理由:
1. `external_ref.type` は Optional のソースシステム内部識別子
2. Slack の Work Objects エンティティ型は `entity_type`（`"slack#/entities/task"`）で指定する
3. 両者は完全に独立したフィールド

Task エンティティを使う場合に重要なのは:
- 検索ハンドラーと `entity.presentDetails` で `external_ref.id` を一致させること
- `entity.presentDetails` の `metadata.entity_type` を `"slack#/entities/task"` にすること
- `external_ref.type` は `"document"` のままでも、`"task"` に変えても、省略しても動作する

---

## 調査アプローチ

1. 0070 のサンプルコードで `external_ref.type = "document"` が使われている背景を確認
2. `external_ref` のドキュメント仕様を直接確認（`developing-apps-with-search-features.md`）
3. Work Objects 実装ドキュメントで `external_ref.type` と `entity_type` の関係を確認
4. `entity_details_requested` イベントペイロードで `type` がどう伝達されるか確認
