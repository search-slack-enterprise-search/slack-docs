# not_found 時のカスタムメッセージ表示方法

## 知りたいこと

0078の更問い。not foundのときにカスタムメッセージを表示する方法

## 目的

not foundだけどカスタムメッセージも表示したい

## 調査サマリー

`status: "not_found"` は Slack デフォルト UI を表示するだけで `custom_message` の添付は**不可**。カスタムメッセージを表示したい場合は `status: "custom"` を使う。アクションボタンも表示したい場合は `status: "custom_partial_view"`。

### 選択ガイド

| やりたいこと | 使う status |
|---|---|
| シンプルな「見つかりません」（デフォルト UI） | `not_found` |
| カスタムタイトル・メッセージを表示したい | `custom` |
| カスタムメッセージ + アクションボタンも表示したい | `custom_partial_view` |

### Bolt Python 実装例（`status: "custom"`）

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

## 完了サマリー

- `custom_message` は `status: "custom"` 専用フィールド（ドキュメント明記）
- `not_found` + `custom_message` の組み合わせはサポートされていない
- not found 時にカスタムメッセージを表示したければ `status: "custom"` に切り替える
