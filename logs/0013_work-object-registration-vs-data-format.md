# Work Object の登録要否調査ログ

## 調査ファイル一覧

- `docs/messaging/work-objects-implementation.md`（実装詳細）
- `docs/messaging/work-objects-overview.md`（概要・Enterprise Search セクション）
- `docs/enterprise-search/developing-apps-with-search-features.md`（Enterprise Search 実装）
- `logs/0011_work-objects-overview.md`（0011番の先行調査ログ）

---

## 調査アプローチ

1. 0011番の先行調査ログを確認し、今回の深掘りポイントを把握
2. `work-objects-implementation.md` を精読して実装フローの「登録ステップ」を確認
3. `work-objects-overview.md` の Enterprise Search サポートセクションを確認
4. `developing-apps-with-search-features.md` でマニフェスト設定を確認

---

## 調査結果

### 1. アプリレベルの設定（Work Object Previews）— 必要な「登録」手順

`docs/messaging/work-objects-implementation.md` 冒頭に明記:

> "First, you must enable the Work Objects feature on your app. To do so, perform the following steps:
> 1. Visit https://api.slack.com/apps and select your app.
> 2. Navigate to **Work Object Previews** under the left sidebar menu.
> 3. Enable the toggle.
> 4. Select the entity type(s) that you would like to add to your app. Supported entity types can be found here.
> 5. Click **Save**."

**解釈**:
- `api.slack.com/apps` のアプリ設定画面で「Work Object Previews」を有効化する手順が必要
- 使用するエンティティタイプ（File / Task / Incident / Content Item / Item）を事前に選択・保存する
- これは一種の「宣言・登録」に相当する（アプリが Work Objects 機能を使うことを Slack に通知する）

---

### 2. 個々のエンティティデータの事前登録 — 不要

Work Object のデータ（エンティティペイロード）は API 呼び出し時にリクエストに含めるだけ:

**Unfurl パターン（チャット投稿時）**:
```json
// chat.unfurl の metadata パラメータに含める
{
  "metadata": {
    "entities": [
      {
        "app_unfurl_url": "https://example.com/document/123?eid=123456&edit=abcxyz",
        "url": "https://example.com/document/123",
        "external_ref": {
          "id": "123",
          "type": "document"
        },
        "entity_type": "slack#/entities/file",
        "entity_payload": {}
      }
    ]
  }
}
```

**Flexpane パターン（詳細表示時）**:
```json
// entity.presentDetails の metadata パラメータに含める
{
  "metadata": {
    "entity_type": "slack#/entities/file",
    "entity_payload": {}
  }
}
```

**Notifications パターン（リンクアンフールなし）**:
- `chat.postMessage` の `eventAndEntityMetadata` パラメータでも Work Object エンティティを含めることができる

いずれも、Slack にエンティティデータを「事前に登録」するのではなく、**API 呼び出し時にデータをペイロードとして渡すだけ**。

---

### 3. エンティティタイプの定義 — スキーマ固定、選択のみ

使用できるエンティティタイプは Slack が固定で定義済み:

| Type | entity_type | 説明 |
|------|------------|------|
| File | `slack#/entities/file` | ドキュメント・スプレッドシート・画像など |
| Task | `slack#/entities/task` | チケット・To-Do など |
| Incident | `slack#/entities/incident` | インシデント・サービス障害など |
| Content Item | `slack#/entities/content_item` | コンテンツページ・記事ページなど |
| Item | `slack#/entities/item` | 汎用エンティティ（何でも表現できる）|

アプリ側が独自のエンティティタイプを新規定義・登録することはできない。アプリ設定の Work Object Previews で**選択するだけ**（選択肢は Slack が提供する上記 5 種類のみ）。

---

### 4. Enterprise Search との組み合わせ時の追加設定

Enterprise Search と Work Objects を組み合わせる場合、追加でいくつかの設定が必要:

**アプリマニフェスト設定**（`developing-apps-with-search-features.md`）:
```json
"features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```
```json
"settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
        "bot_events": [
            "function_executed",
            "entity_details_requested"
        ]
    },
    "app_type": "remote",
    "function_runtime": "remote"
}
```

**Work Objects Previews の設定**（`work-objects-overview.md` Enterprise Search セクション）:
> "You can define the type of Work Objects for your search results, such as an item, within the Work Object Previews view within app settings."

Enterprise Search の場合も、アプリ設定の Work Object Previews でエンティティタイプを定義する必要がある。

---

### 5. external_ref の制約

`work-objects-implementation.md` および `work-objects-overview.md`:
> "The external_ref format or IDs must not change for a given Work Object, as it is used for related conversations tracking."

一度設定した `external_ref.id` は変更不可。Slack が Related Conversations（関連会話）のトラッキングに使用するため。これは事前登録ではなく、「一度使い始めたら変えてはいけない」という制約。

---

## 調査の判断・解釈

### Work Object の「登録」の実態

**「登録が必要な部分」**:
1. `api.slack.com/apps` の Work Object Previews で機能を有効化し、使用するエンティティタイプを選択・保存する（アプリ設定レベルの登録）
2. `entity_details_requested` イベントをサブスクライブする（Events & Subscriptions の設定）
3. Enterprise Search と組み合わせる場合はアプリマニフェストに `search` オブジェクトを追加する

**「単なるデータ形式（スキーマ）の部分」**:
- 個々の Work Object エンティティデータは事前登録不要
- `chat.unfurl` の `metadata` パラメータや `entity.presentDetails` の `metadata` パラメータに JSON として渡すだけ
- エンティティタイプも Slack が定義済みのものを選ぶだけで、新規作成は不要

### 結論

Work Objects は「アプリ設定での宣言（有効化 + エンティティタイプ選択）」と「API 呼び出し時のデータ形式（スキーマ）」の両方の要素を持つ。

- **アプリ設定レベルの登録は必要**: Work Object Previews の有効化 + 使用エンティティタイプの選択
- **個々のエンティティの事前登録は不要**: データは API 呼び出し時にペイロードとして渡すだけ
- **エンティティタイプは Slack が固定定義**: カスタムエンティティタイプの追加登録はできない

「登録が必要か、単なるデータ形式か」という問いに対しては：**両方**が答えで、アプリ設定レベルでは登録（有効化・宣言）が必要だが、個々のエンティティデータは定義済みスキーマに従った形式で API 呼び出し時に渡すだけ。

---

## 問題・疑問点

- Enterprise Search の場合、Work Object Previews で選択できる entity type は「item」を推奨しているように読めるが（`work-objects-overview.md`の記述）、他のタイプも使えるかは明確でない
- アプリマニフェスト（YAML/JSON）で Work Object Previews の設定を宣言する方法があるかは不明（UI での設定しか確認できなかった）
