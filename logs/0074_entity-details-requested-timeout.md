# 0074: entity_details_requested のタイムアウト制限

## 調査ファイル一覧

- `docs/reference/events/entity_details_requested.md`
- `docs/messaging/work-objects-implementation.md`
- `docs/messaging/work-objects-overview.md`
- `docs/reference/methods/entity.presentdetails.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/apis/events-api/index.md`

---

## 調査アプローチ

1. `entity_details_requested` を含むファイルを ripgrep で全探索
2. `reference/events/entity_details_requested.md` と `messaging/work-objects-implementation.md` を精読
3. `reference/methods/entity.presentdetails.md` で API 詳細確認
4. `apis/events-api/index.md` でEvents APIのタイムアウト仕様確認
5. `trigger_id` の有効期限・タイムアウト情報を ripgrep で横断検索

---

## 調査結果

### 1. entity_details_requested はEvents APIイベントである

`docs/reference/events/entity_details_requested.md` より:

```
Source: https://docs.slack.dev/reference/events/entity_details_requested

# entity_details_requested event

### This event is sent to your app when a user clicks on a Work Object unfurl or refreshes the flexpane

## Facts

**Required Scopes**
No scopes required!

**Compatible APIs**
[`Events`](/apis/events-api)
```

**重要**: このイベントは `Events API` 経由で配信される通常のイベントであり、インタラクティブペイロード（slash command、shortcut、action等）ではない。

---

### 2. Bolt実装でAckが不要な理由

`docs/messaging/work-objects-overview.md` の JavaScript サンプル:

```js
// When a user opens the flexpane, you'll receive the entity_details_requested event.
// When responding to the event, call the entity.presentDetails API method as follows:
client.entity.presentDetails({
  trigger_id: event.trigger_id,
  metadata: entity_metadata
});
```

`docs/messaging/work-objects-overview.md` の Java サンプル:

```java
public class EntityDetailsRequestedListener implements BoltEventHandler<EntityDetailsRequestedEvent> {
  EntityPresentDetailsRequest request = EntityPresentDetailsRequest.builder()
    .token(ctx.getBotToken())
    .triggerId(payload.getEvent().getTriggerId())
    .metadata(metadata)
    .build();
  var response = ctx.client().entityPresentDetails(request);
}
```

**ackがない理由**: Bolt フレームワークでは、`@app.event(...)` で登録したイベントハンドラーに対して、フレームワーク自身が自動的に HTTP 200 OK を返す（ack処理を内部化している）。
開発者が明示的に `ack()` を呼ぶ必要はない。

これはインタラクティブペイロード（`@app.action`, `@app.shortcut`, `@app.view` など）と異なる点で、そちらは開発者が明示的に `ack()` を呼ぶ必要がある。

---

### 3. Events API の3秒タイムアウト（HTTP応答）

`docs/apis/events-api/index.md` より（line 238）:

> Your app should respond to the event request with an HTTP 2xx **within three seconds**. If it does not, we'll consider the event delivery attempt failed. After a failure, we'll retry three times, backing off exponentially.

推奨事項:
- Respond to events with an HTTP 200 OK as soon as you can.
- Avoid actually processing and reacting to events within the same process.
- **Implement a queue to handle inbound events after they are received.**

この3秒制約は **HTTP 200 の応答** に関するものであり、Bolt を使う場合はフレームワークが自動で返す。
`entity.presentDetails` の呼び出し自体は非同期に実行できる（trigger_idを使って後から呼べる）。

ただし、HTTP モード（非 Socket Mode）で動作している場合、entity.presentDetails の処理が3秒を超えるなら、バックグラウンドスレッドで処理することが推奨される。

---

### 4. processing_state の30秒制限

`docs/messaging/work-objects-implementation.md`（line 1295付近）:

```json
{
  "trigger_id": "...",
  "error": {
    "status": "custom_partial_view",
    "actions": [
      {
        "text": "Request access",
        "action_id": "request_access",
        "processing_state": {
          "enabled": true
          // This can be enabled to disable the button and show a loading state
          // for up to 30 seconds or until your app responds with another call
          // to the entity.presentDetails API method.
        }
      }
    ]
  }
}
```

**重要**: この30秒はクライアント側のUIローディング表示の最大時間であり、`trigger_id` の有効期限ではない。  
アクションボタンに `processing_state.enabled: true` を設定すると、ボタンが disabled になりローディング状態が最大30秒続く。その間に `entity.presentDetails` を再度呼び出せば状態が更新される。

---

### 5. trigger_id の有効期限

ドキュメント上に **trigger_idの明示的な有効期限は記載されていない**。

`docs/reference/methods/entity.presentdetails.md` のエラーリストに:
```
invalid_trigger_id  - Trigger id is not valid
```
とあるため、古い trigger_id を使うと `invalid_trigger_id` エラーが返る可能性はある。

通常の Slack の trigger_id（モーダルオープン等）は **約30秒** とされているが、`entity_details_requested` の trigger_id については明示的な期限の記載は見当たらなかった。

---

### 6. フレックスペインコンテンツの10分TTL

`docs/messaging/work-objects-implementation.md`（line 1268）:

> Assuming a Work Object flexpane was previously opened by a user, the content has a **10 minute refresh timer (TTL)** before another event is sent to your app.

**10分TTLが経過後に** entity_details_requested イベントが送信されるシナリオ:
- ユーザーが Work Object フレックスペインを2回目以降に開く
- ユーザーがフレックスペイン内で `Details` と `Conversations` タブを切り替える
- ユーザーがフレックスペインのリフレッシュボタンをクリックする

**10分TTL内ではイベントが送信されないシナリオ**（明示的にリフレッシュしない限り）:
- フレックスペインを閉じて再度開く
- `Details` と `Conversations` タブを切り替える
- フレックスペイン内の他の要素を操作する

---

### 7. view_submission（フレックスペイン編集保存）の3秒ack

`docs/messaging/work-objects-implementation.md`（line 584）:

> Note that because this is using the `ack` function, you'll need to respond within **3 seconds** to prevent a timeout.

フレックスペインのフィールドを編集して「Save」を押すと `view_submission` ペイロードが送られ、これはインタラクティブペイロードなので **3秒以内に `ack()`** が必要。

この3秒 ack は `entity_details_requested` ではなく `view_submission` に適用される制約。

---

### 8. entity.presentDetails のレート制限

`docs/reference/methods/entity.presentdetails.md` より:

```
Rate Limits: Tier 3: 50+ per minute
```

---

## まとめ

| 項目 | 値 | 根拠 |
|------|-----|------|
| Bolt での `ack()` 要否 | **不要** | Events APIイベントはBoltが自動ack |
| Events API HTTP応答期限 | **3秒** | `apis/events-api/index.md` |
| `entity.presentDetails` 呼び出しのタイムアウト | **記載なし**（trigger_idの有効期限未記載） | `reference/methods/entity.presentdetails.md` |
| フレックスペインコンテンツTTL | **10分** | `messaging/work-objects-implementation.md` |
| processing_state ローディング表示期限 | **30秒** | `messaging/work-objects-implementation.md` |
| view_submission ack 期限 | **3秒** | `messaging/work-objects-implementation.md` |
| entity.presentDetails レート制限 | **Tier 3 (50+/分)** | `reference/methods/entity.presentdetails.md` |

**結論**: `entity_details_requested` イベントハンドラーに `ack()` がないのは仕様通り。Bolt が自動的に HTTP 200 を返すため開発者はackを書かない。`entity.presentDetails` の呼び出しは非同期に行える。trigger_id の明示的な有効期限はドキュメントに記載されていないが、通常の Slack trigger_id と同様に時間制限がある可能性は排除できない。

---

## 問題・疑問点

- `entity_details_requested` の trigger_id の具体的な有効期限はドキュメントに記載なし。実際の開発では迅速に `entity.presentDetails` を呼ぶことが推奨される
- HTTP モード（非 Socket Mode）での Bolt 実装時、entity.presentDetails の処理が長い場合はバックグラウンドスレッドで処理する必要があるが、trigger_id の有効期限内に呼び出せるかどうかは不明
