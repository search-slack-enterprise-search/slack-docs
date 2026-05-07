# entity_details_requested のタイムアウト制限

## 知りたいこと

Work Objectsのevent "entity_details_requested"においてBolt実装のサンプルを見るとAckがない。タイムアウトの上限などを知りたい。

## 目的

entity_details_requestedの制限を知りたい

## 調査サマリー

- `entity_details_requested` は **Events API** イベントであり、インタラクティブペイロードではない
- Bolt のイベントハンドラー（`@app.event(...)`）では Bolt フレームワークが自動で HTTP 200 を返すため、開発者が `ack()` を明示的に呼ぶ必要はない
- Events API の HTTP 応答制限は **3秒以内**（Bolt が自動処理するので通常問題なし）
- `entity.presentDetails` API 呼び出し自体のタイムアウト（trigger_id 有効期限）はドキュメントに明示的な記載なし
- フレックスペインコンテンツには **10分 TTL** があり、TTL経過後に再アクセスすると再度イベントが送信される
- アクションボタンの `processing_state.enabled: true` によるローディング表示は最大 **30秒**
- フレックスペイン編集保存の `view_submission` ペイロードは別途 **3秒以内の ack** が必要

## 完了サマリー

entity_details_requested はEvents APIイベントでBoltが自動ack処理するためack()記述不要。trigger_idの有効期限はドキュメント未記載だが、迅速なentity.presentDetails呼び出しを推奨。
