# ログ: Work Objects の actions でモーダルフォームを開いて入力させることは可能か

## 調査ファイル一覧

- `docs/messaging/work-objects-implementation.md`（actions セクション l.606-728、特に l.712 と l.721-727 を確認）
- `docs/surfaces/modals.md`（modals の opening セクション、`trigger_id` の使い方を確認）
- `docs/interactivity/handling-user-interaction.md`（modal_responses セクション l.171-184 を確認）

## 調査アプローチ

1. `work-objects-implementation.md` の `block_actions` ペイロード例に `trigger_id` が含まれるかを確認
2. Work Objects ドキュメントにモーダルを開く方法が明示されているかを確認
3. `surfaces/modals.md` で `trigger_id` からモーダルを開く標準手順を確認

---

## 調査結果

### 1. Work Objects の `block_actions` ペイロードに `trigger_id` が含まれる（`work-objects-implementation.md` l.712）

Work Objects の actions ボタンをクリックした際の `block_actions` ペイロード例に `trigger_id` が明示されている:

```json
{
  "type": "block_actions",
  "user": { "id": "U123ABC456", ... },
  "api_app_id": "A123ABC456",
  "token": "abc123",
  "container": {
    "type": "message_attachment",
    "message_ts": "1753813500.959789",
    "channel_id": "C123ABC456",
    "is_app_unfurl": true,
    "entity_url": "https://github.com/issues/139",
    "external_ref": { "id": "139" }
  },
  "trigger_id": "1234567890123.1234567890123.abcdef01234567890abcdef012345689",  // ← 存在する
  "response_url": "https://hooks.slack.com/actions/T123/123/abc123",
  "actions": [
    {
      "type": "button",
      "action_id": "github_wo_button_summarize_issue",
      ...
    }
  ]
}
```

---

### 2. Work Objects ドキュメントがモーダルを開くことを明示的に推奨（`work-objects-implementation.md` l.721-727）

「Handling authentication」セクションの **「Other ways to handle the request」** で、ボタンクリック後の対応として明示的にモーダルが挙げられている:

> **Other ways to handle the request**
> - [Open a modal](/interactivity/handling-user-interaction/#modal_responses) to collect more information from the user.  ← 明示的に記載
> - Post a message to the thread where the unfurl message is posted.
> - Send a message to the user's DM if the action has failed.
> - If the action is successful in the unfurl card, then refresh the unfurl by making a request to the `chat.unfurl` API method and by passing the new `metadata`.
> - If the action is successful in the flexpane, then refresh the flexpane by making a request to the `entity.presentDetails` API method with the new `metadata`.

→ **「ユーザーから追加情報を収集するためにモーダルを開く」ことが公式ドキュメントに明示されている**。

---

### 3. モーダルの開き方（`surfaces/modals.md` より）

**モーダルを開くには `trigger_id` が必要**（`surfaces/modals.md` l.185）:
> 「To open a new modal, your app _must_ possess a valid, unexpired `trigger_id`, obtained from an interaction payload.」

**`trigger_id` の制約**（`surfaces/modals.md` l.187、`handling-user-interaction.md` l.177-179）:
- **3秒で失効する**: 受け取ってから3秒以内に使う必要がある
- **1回しか使えない**: 2回目以降は `trigger_exchanged` エラーになる

**モーダルを開く手順**（`surfaces/modals.md` l.189-195）:

`views.open` API を呼び出す:
```http
POST https://slack.com/api/views.open
Content-type: application/json
Authorization: Bearer YOUR_ACCESS_TOKEN

{
  "trigger_id": "156772938.1827394",
  "view": {
    "type": "modal",
    "callback_id": "modal-identifier",
    "title": { "type": "plain_text", "text": "Just a modal" },
    "blocks": [...]
  }
}
```

**モーダルでのフォーム入力の受け取り**（`surfaces/modals.md` l.206）:
> 「**`view_submission` payloads.** When a view is submitted, you'll receive a `view_submission` payload. This payload will contain a `state` object with the values and contents of any stateful blocks that were in the submitted view.」

---

### 4. 実装フローの全体像

Work Objects actions → モーダル → `view_submission` の流れ:

```
1. Work Object の unfurl/flexpane にボタンを定義
   (entity_payload.actions.primary_actions/overflow_actions)

2. ユーザーがボタンをクリック
   → アプリに block_actions イベントが届く（trigger_id 付き）

3. アプリが trigger_id を使って views.open を呼び出す（3秒以内）
   → Slack にモーダルが表示される

4. ユーザーがモーダルのフォームに入力して [Submit] をクリック
   → アプリに view_submission イベントが届く

5. アプリが view.state.values から入力データを取得して処理
```

**Bolt Python での実装例**（`surfaces/modals.md` のサンプルコードを参考に Work Objects 向けに示す）:

```python
# Work Objects action ハンドラ
@app.action("my_work_object_button")
def handle_action(ack, body, client):
    ack()  # 3秒以内にACK
    # trigger_id を使ってモーダルを開く
    client.views_open(
        trigger_id=body["trigger_id"],
        view={
            "type": "modal",
            "callback_id": "my_form",
            "title": {"type": "plain_text", "text": "Input Form"},
            "submit": {"type": "plain_text", "text": "Submit"},
            "blocks": [
                {
                    "type": "input",
                    "block_id": "comment_block",
                    "label": {"type": "plain_text", "text": "Comment"},
                    "element": {
                        "type": "plain_text_input",
                        "action_id": "comment_input",
                        "multiline": True
                    }
                }
            ]
        }
    )

# view_submission ハンドラ
@app.view("my_form")
def handle_form_submit(ack, body, view):
    ack()
    comment = view["state"]["values"]["comment_block"]["comment_input"]["value"]
    # 入力データを処理...
```

---

### 5. Work Objects の「editing」機能との違い

Work Objects にはフレックスペインでのフィールド編集機能（`edit.enabled: true`）も存在するが、これはフレックスペイン専用。

| 比較 | actions → modal | flexpane editing |
|---|---|---|
| 起点 | unfurl card / flexpane のボタン | フレックスペインの鉛筆アイコン |
| フォームの場所 | モーダル（オーバーレイ） | フレックスペイン内 |
| カスタマイズ | Block Kit input ブロックで自由設計 | entity_payload の `edit` プロパティで設定 |
| view_submission callback_id | 任意の文字列 | `work-object-edit` 固定 |

---

## 問題・疑問点

- `trigger_id` が3秒で失効するため、`ack()` と `views.open` の両方を3秒以内に呼ぶ必要がある
  - Bolt Python では `ack()` を先に呼べば残り時間内に `views.open` を呼べる
  - Lambda 等のサーバーレス環境で遅延が発生した場合のリスクがある（0046 の3秒 ACK 問題と同様）
- モーダルで収集した情報を Work Object のデータにどう反映させるかは実装次第
