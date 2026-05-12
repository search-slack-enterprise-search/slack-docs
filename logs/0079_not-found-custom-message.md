# ログ: not_found 時のカスタムメッセージ表示方法

## 調査日時

2026-05-12

## タスク概要

0078 の更問い。`entity_details_requested` イベントで対象エンティティが存在しない場合に、`not_found` を返しつつカスタムメッセージも表示できるか調査する。

---

## 調査ファイル一覧

- `logs/0078_entity-details-requested-not-found-response.md`（前回ログの確認）
- `docs/reference/methods/entity.presentdetails.md`
- `docs/messaging/work-objects-implementation.md`

---

## 調査アプローチ

1. 0078 のログで確認済みの `error` オブジェクト仕様を再確認
2. `entity.presentdetails.md` の `error` オブジェクト仕様を精読し、`custom_message` が使えるステータスを確認
3. `work-objects-implementation.md` で `custom` / `custom_partial_view` の実例を確認

---

## 調査結果

### 1. `custom_message` は `status: "custom"` 専用

`docs/reference/methods/entity.presentdetails.md` 行 110〜124 に以下が明記されている：

| プロパティ | 説明 |
|---|---|
| `custom_message` | **Used when status is 'custom'** to provide a specific message to the client. |
| `custom_title` | **Used when status is 'custom'** to provide a specific title. |

→ **`not_found` と `custom_message` の組み合わせはサポートされていない**。カスタムメッセージを表示したい場合は `status: "custom"` または `status: "custom_partial_view"` を使う必要がある。

### 2. `status` の各値と用途

`docs/reference/methods/entity.presentdetails.md` 行 138：

```
String. Can be one of ["restricted", "internal_error", "not_found" "custom", "custom_partial_view", "timeout", "edit_error"]
```

| status | 用途 |
|---|---|
| `not_found` | エンティティが存在しない（固定メッセージ、カスタム不可） |
| `custom` | 任意のタイトル・メッセージを表示する全カスタムエラー画面 |
| `custom_partial_view` | `custom` + アクションボタン付き部分表示エラー画面 |
| `restricted` | アクセス制限（固定メッセージ） |
| `internal_error` | アプリ側内部エラー（固定メッセージ） |
| `timeout` | タイムアウト（固定メッセージ） |
| `edit_error` | フォーム編集後のサーバーエラー（`custom_message` 指定可） |

### 3. `status: "custom"` の使い方

ドキュメント上に `status: "custom"` の単独実例はないが、`custom_message` / `custom_title` の説明から次の構造が導出できる：

```python
client.entity_presentDetails(
    trigger_id=body["event"]["trigger_id"],
    error={
        "status": "custom",
        "custom_title": "アイテムが見つかりません",
        "custom_message": "このアイテムは削除されたか、存在しません。",
        "message_format": "markdown"
    }
)
```

### 4. `status: "custom_partial_view"` の使い方（アクションボタン付き）

`docs/messaging/work-objects-implementation.md` 行 1294〜1296 の実例：

```json
{
  "trigger_id": "...",
  "error": {
    "status": "custom_partial_view",
    "custom_title": "Ruh roh",
    "custom_message": ":hand: This item is *restricted* per our [company policy](https://example.com). Don't worry though, you can request access using the button below.",
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

「削除されました」などのメッセージ + ボタンなしにしたい場合は `actions` を省略し `custom_partial_view` のみ使うことも可能（行 1302〜1304 の例がアクションなし `custom_partial_view`）。

### 5. `edit_error` での `custom_message` 使用例

`docs/messaging/work-objects-implementation.md` 行 601 の実例：

```json
{
  "trigger_id": "...",
  "error": {
    "status": "edit_error",
    "custom_message": "Something went wrong but we're not sure what. Try again later"
  }
}
```

`edit_error` も `custom_message` が使えるが、こちらはフォーム保存時のエラー専用（通常の `entity_details_requested` ハンドラーでは使わない）。

---

## 結論

`status: "not_found"` は固定の Slack デフォルト UI を表示するだけで、カスタムメッセージの添付は**できない**。

**not found だがカスタムメッセージも表示したい場合は `status: "custom"` を使う：**

```python
client.entity_presentDetails(
    trigger_id=body["event"]["trigger_id"],
    error={
        "status": "custom",
        "custom_title": "アイテムが見つかりません",
        "custom_message": "このアイテムは削除されたか、存在しません。",
        "message_format": "markdown"
    }
)
```

アクションボタンも添えたい場合は `status: "custom_partial_view"` を使う。

### 選択ガイド

| やりたいこと | 使う status |
|---|---|
| シンプルな「見つかりません」（デフォルト UI） | `not_found` |
| カスタムタイトル・メッセージを表示したい | `custom` |
| カスタムメッセージ + アクションボタンも表示したい | `custom_partial_view` |

---

## 問題・疑問点

- `status: "not_found"` 時の Slack UI の実際の見た目（ラベルテキスト等）はドキュメントに画像なし。`custom` を使えばメッセージをコントロールできるため、UX 要件次第では `custom` の方が望ましい。
- `custom` vs `custom_partial_view` の UI 上の差異はドキュメント上の画像が `custom_partial_view` のみのため不明。実機での確認が必要。
