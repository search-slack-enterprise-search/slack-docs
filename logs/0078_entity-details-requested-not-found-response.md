# ログ: entity_details_requested でエンティティが存在しない場合のレスポンス

## 調査日時

2026-05-12

## タスク概要

Work Objects の `entity_details_requested` イベントにおいて、該当のエンティティが存在しなかったときに何を返すべきかを調査する。Bolt Python 使用前提。

---

## 調査ファイル一覧

- `docs/reference/events/entity_details_requested.md`
- `docs/reference/methods/entity.presentdetails.md`
- `docs/messaging/work-objects-implementation.md`

---

## 調査アプローチ

1. `entity_details_requested` を含むファイルを `rg` で全文検索
2. イベントリファレンス (`entity_details_requested.md`) を確認
3. 対応する API メソッド (`entity.presentDetails`) のリファレンスを精読
4. 実装ガイド (`work-objects-implementation.md`) でエラーハンドリングの文脈を確認

---

## 調査結果

### 1. `entity.presentDetails` の `error` パラメータ

`docs/reference/methods/entity.presentdetails.md` の Optional arguments セクション（行 80〜138）に以下が記載されている：

```
**`error`**Optional
```

`error` オブジェクト内の `status` フィールドに指定できる値：

| ステータス | 説明 |
|---|---|
| `restricted` | アクセス制限によりエンティティを表示できない |
| `internal_error` | アプリ側の内部エラー |
| `not_found` | **エンティティが存在しない** |
| `custom` | カスタムメッセージ付きエラー |
| `custom_partial_view` | アクションボタン付きカスタムエラー（部分表示） |
| `timeout` | タイムアウト |
| `edit_error` | 編集時のフォームレベルエラー |

→ **エンティティが存在しない場合は `"not_found"` を使用する。**

`error` オブジェクトのその他のプロパティ：

| プロパティ | 型 | 必須/任意 | 説明 |
|---|---|---|---|
| `status` | string | 必須 | エラーステータス（上記の値） |
| `custom_message` | string | optional | `status: "custom"` 時のメッセージ本文 |
| `custom_title` | string | optional | `status: "custom"` 時のタイトル |
| `message_format` | "markdown" | optional | カスタムメッセージのフォーマット |
| `actions` | array | optional | エラー時に表示するアクションボタン |

### 2. `entity.presentDetails` の Bolt Python 呼び出し名

`docs/reference/methods/entity.presentdetails.md` 行 30：

```
app.client.entity_presentDetails
```

（ドット区切りの API 名はアンダースコア区切りに変換される）

### 3. 実装例（Bolt Python）

エンティティが存在しない場合のレスポンス実装：

```python
@app.event("entity_details_requested")
def handle_entity_details_requested(body, client, logger):
    trigger_id = body["event"]["trigger_id"]
    external_ref_id = body["event"]["external_ref"]["id"]

    # 外部システムでエンティティを検索
    entity = fetch_entity(external_ref_id)

    if entity is None:
        # エンティティが存在しない場合
        client.entity_presentDetails(
            trigger_id=trigger_id,
            error={
                "status": "not_found"
            }
        )
        return

    # 正常系：エンティティが存在する場合
    client.entity_presentDetails(
        trigger_id=trigger_id,
        metadata={
            "entity_type": "slack#/entities/task",
            "entity_payload": { ... }
        }
    )
```

### 4. `edit_error` との使い分け

`docs/messaging/work-objects-implementation.md` 行 596〜604 に記載：

- `edit_error` はフォーム編集完了（`view_submission`）後にエラーが発生した場合に使う
- `not_found` は通常の `entity_details_requested` イベントハンドラーで使う

`edit_error` の例：
```json
{
  "trigger_id": "...",
  "error": {
    "status": "edit_error",
    "custom_message": "Something went wrong but we're not sure what. Try again later"
  }
}
```

### 5. `custom_partial_view` との使い分け

- `not_found`: シンプルな「見つかりません」表示（アクションボタンなし）
- `custom_partial_view`: アクセスリクエストボタンなどを表示したい場合のカスタムエラー画面

`custom_partial_view` の例（`docs/messaging/work-objects-implementation.md` 行 1294〜1296）：

```json
{
  "trigger_id": "...",
  "error": {
    "status": "custom_partial_view",
    "custom_title": "Ruh roh",
    "custom_message": ":hand: This item is *restricted*...",
    "message_format": "markdown",
    "actions": [
      {
        "text": "Request access",
        "action_id": "request_access",
        "value": "some_val"
      }
    ]
  }
}
```

---

## 結論

`entity_details_requested` イベントで対象エンティティが存在しない場合は、`entity.presentDetails` を `error.status = "not_found"` で呼び出す。

Bolt Python での最小実装：

```python
client.entity_presentDetails(
    trigger_id=body["event"]["trigger_id"],
    error={"status": "not_found"}
)
```

---

## 問題・疑問点

- `not_found` 時に Slack クライアント上でどのようなメッセージが表示されるか（UI の見た目）はドキュメントに記載なし。`custom` を使って「このアイテムは削除されました」などのメッセージを表示する方がユーザー体験は良いかもしれない。
