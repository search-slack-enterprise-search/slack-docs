# Work Objects の actions でモーダルフォームを開いて入力させることは可能か

## 知りたいこと

0081の更問い、ワークフローを使えないのなら、actionsでフォームを開き入力をさせることは可能ですか？

## 目的

ワークフローを仕えないのはわかったから代替手段があるかどうかを知りたい

## 調査サマリー

### 結論: Work Objects の actions からモーダルフォームを開くことは**可能**

#### 根拠

`work-objects-implementation.md` の2箇所で確認:

1. **`block_actions` ペイロードに `trigger_id` が含まれる**（l.712）
   Work Objects のボタンクリック時に届く `block_actions` ペイロードの例に `trigger_id` フィールドが明示されている。

2. **モーダルを開くことが公式ドキュメントで明示的に推奨**（l.723）
   「Other ways to handle the request」として以下が列挙されている:
   > * **[Open a modal](/interactivity/handling-user-interaction/#modal_responses) to collect more information from the user.**

#### 実装フロー

```
1. Work Object の actions にボタンを定義
2. ユーザーがボタンをクリック → block_actions イベント（trigger_id 付き）
3. アプリが trigger_id を使って views.open を呼び出す（3秒以内）
4. ユーザーがモーダルに入力して送信 → view_submission イベント
5. アプリが入力データを処理
```

Bolt Python での実装例:
```python
@app.action("my_work_object_button")
def handle_action(ack, body, client):
    ack()
    client.views_open(
        trigger_id=body["trigger_id"],
        view={
            "type": "modal",
            "callback_id": "my_form",
            "title": {"type": "plain_text", "text": "フォーム"},
            "submit": {"type": "plain_text", "text": "送信"},
            "blocks": [...]
        }
    )

@app.view("my_form")
def handle_submit(ack, body, view):
    ack()
    values = view["state"]["values"]
    # 入力データを処理...
```

#### 注意点

- `trigger_id` は **3秒で失効**し、**1回しか使えない**
- `ack()` を先に呼んで、その後 `views.open` を呼ぶことで3秒制約に対応できる
- Lambda 等のサーバーレス環境では遅延リスクあり（0046 の3秒 ACK 問題と同様の制約）

#### Work Objects の editing 機能との比較

| 比較 | actions → modal | flexpane editing |
|---|---|---|
| 起点 | unfurl card / flexpane のボタン | フレックスペインの鉛筆アイコン |
| フォームの場所 | モーダル（オーバーレイ） | フレックスペイン内 |
| カスタマイズ性 | Block Kit input ブロックで自由設計 | entity_payload の `edit` プロパティで設定 |

## 完了サマリー

Work Objects の actions からモーダルフォームを開いてユーザーに入力させることは**可能**であることを確認した。

`block_actions` ペイロードに含まれる `trigger_id` を使って `views.open` API を呼び出すことでモーダルを開ける。これは `work-objects-implementation.md` の「Other ways to handle the request」に明示的に記載されている公式の方法。

Bolt Python では `@app.action()` ハンドラ内で `ack()` を先に呼んだ後、`client.views_open()` でモーダルを開き、`@app.view()` ハンドラで `view_submission` を受け取って入力データを処理できる。ワークフローが使えない代替手段として実用的に機能する。
