# entity_details_requested でエンティティが存在しない場合のレスポンス

## 知りたいこと

Work Objects の `entity_details_requested` イベントにおいて、該当のエンティティが存在しなかったときは何を返せばいいの？

## 目的

ないとは思うけど、一応なかったときの対応方法を知りたい。

## 備考

Bolt を使用しています

## 調査サマリー

`entity_details_requested` イベントでエンティティが存在しない場合は、`entity.presentDetails` API を `error.status = "not_found"` で呼び出す。

**Bolt Python 最小実装：**

```python
client.entity_presentDetails(
    trigger_id=body["event"]["trigger_id"],
    error={"status": "not_found"}
)
```

`entity.presentDetails` の `error.status` に指定できる値は `"restricted"` / `"internal_error"` / `"not_found"` / `"custom"` / `"custom_partial_view"` / `"timeout"` / `"edit_error"` の 7 種類。エンティティが存在しない場合は `"not_found"` が対応する。

カスタムメッセージ（「このアイテムは削除されました」等）を表示したい場合は `"custom"` ステータスと `custom_message` / `custom_title` を組み合わせて使用可能。

## 完了サマリー

- 調査完了日: 2026-05-12
- 結論: エンティティが存在しない場合は `entity.presentDetails` に `error: {"status": "not_found"}` を渡す
- 参照ドキュメント: `docs/reference/methods/entity.presentdetails.md`、`docs/messaging/work-objects-implementation.md`
- ログ: `logs/0078_entity-details-requested-not-found-response.md`
