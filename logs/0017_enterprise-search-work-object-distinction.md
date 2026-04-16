# Enterprise Search における Work Object と通常結果の区別方法 調査ログ

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md`（Enterprise Search 実装・search_results オブジェクト）
- `docs/messaging/work-objects-overview.md`（Work Objects 概要・Enterprise Search セクション）
- `docs/messaging/work-objects-implementation.md`（Work Objects 実装詳細・entity_details_requested イベント説明）
- `docs/reference/events/entity_details_requested.md`（entity_details_requested イベントリファレンス）
- `docs/reference/methods/entity.presentDetails.md`（entity.presentDetails メソッドリファレンス）
- `logs/0013_work-object-registration-vs-data-format.md`（先行調査ログ）

---

## 調査アプローチ

1. `developing-apps-with-search-features.md` で `search_results` オブジェクトの構造と `external_ref` の意味を確認
2. `work-objects-overview.md` の Enterprise Search サポートセクションで Work Objects との連携仕様を確認
3. `work-objects-implementation.md` で `entity_details_requested` イベントの詳細ペイロードを確認
4. `reference/events/entity_details_requested.md` でイベントの公式リファレンスを確認
5. 先行調査ログ `0013` を参照して既知情報を活用

---

## 調査結果

### 1. search_results オブジェクトの構造（`developing-apps-with-search-features.md`）

Enterprise Search の検索結果を返す際の `search_results` オブジェクト（`slack#/types/search_results` 型）は以下のフィールドを持つ:

```json
{
  "external_ref": {
    "id": "123",           // 必須: 外部システムでのユニークID
    "type": "document"     // 任意: IDがグローバルに一意でない場合のみ必要
  },
  "title": "...",          // 必須
  "description": "...",   // 必須
  "link": "...",           // 必須
  "date_updated": "...",  // 必須
  "content": "..."         // 任意
}
```

**重要な記述（`external_ref.id` の説明）**:
> "A unique identifier for referencing within the search results. If your app implements Work Objects, this should be same value used for that implementation."

→ アプリが Work Objects を実装している場合、`external_ref.id` は Work Object 側でも使う同じ値にすること、という指示が明示されている。

---

### 2. Enterprise Search と Work Objects の連携仕様（`work-objects-overview.md`）

**Enterprise Search セクションの記述（行 87-93）**:
> "To support Work Objects for your app's Enterprise Search results, traditional search results, and AI answers citations, your app must subscribe to the `entity_details_requested` event. You can define the type of Work Objects for your search results, such as an item, within the Work Object Previews view within app settings."

→ Work Objects を Enterprise Search 結果に対応させるには:
1. `entity_details_requested` イベントをサブスクライブする
2. アプリ設定の「Work Object Previews」で使用するエンティティタイプを定義する

---

### 3. entity_details_requested イベントの詳細ペイロード（`work-objects-implementation.md`）

イベントのペイロードには以下のフィールドが含まれる（行 1251-1253）:

```json
{
  "type": "entity_details_requested",
  "user": "U0123456",
  "external_ref": {
    // `external_ref` that was set in the `metadata` of `chat.unfurl`.
    // This is not guaranteed to be set in all cases. For example,
    // when a work object is opened from an Enterprise Search result
    // provided by a Slack-developed search provider, we cannot provide
    // an `external_ref`.
    "id": "123",
    "type": "my-type"
  },
  "entity_url": "https://example.com/document/123",
  "link": { ... },
  "app_unfurl_url": "...",
  "event_ts": "...",
  "trigger_id": "...",
  "user_locale": "en-US",
  // These fields will not be provided when the entity details are opened
  // from outside of a message context (i.e., Enterprise Search)
  "channel": "C123ABC456",
  "message_ts": "1755035323.759739",
  "thread_ts": "1755035323.759739"
}
```

**重要な注釈（2箇所）**:

1. `external_ref` に関するコメント:
   > "This is not guaranteed to be set in all cases. For example, when a work object is opened from an Enterprise Search result provided by a Slack-developed search provider, we cannot provide an `external_ref`."

   → Enterprise Search 経由で開かれた場合でも `entity_details_requested` は発火するが、`external_ref` が提供されないケースがある（Slack 開発の検索プロバイダの場合）

2. `channel` / `message_ts` / `thread_ts` に関するコメント:
   > "These fields will not be provided when the entity details are opened from outside of a message context (i.e., Enterprise Search)"

   → **Enterprise Search の場合は `channel`、`message_ts`、`thread_ts` が送られてこない**。アプリ側でこれらの有無によって「チャットの unfurl から開かれたのか」「Enterprise Search から開かれたのか」を判別できる。

---

### 4. entity_details_requested イベントリファレンス（`docs/reference/events/entity_details_requested.md`）

リファレンスの説明:
> "This event is sent to your app when a user clicks on a Work Objects unfurl or refreshes the flexpane."

発火条件は 2 種類:
- ユーザーが Work Object の unfurl をクリックしたとき
- ユーザーが flexpane をリフレッシュしたとき

（Enterprise Search の場合も同じイベントが発火することは `work-objects-implementation.md` の注釈から確認済み）

---

### 5. アプリ設定レベルの区別メカニズム（先行調査 0013 の知見を踏まえて整理）

**Work Objects が有効なアプリの条件**:
- `api.slack.com/apps` の「Work Object Previews」を有効化 + エンティティタイプを選択・保存
- `entity_details_requested` イベントをサブスクライブ

**アプリマニフェストでの設定**（Enterprise Search + Work Objects 組み合わせ時）:
```json
{
  "settings": {
    "event_subscriptions": {
      "bot_events": [
        "function_executed",
        "entity_details_requested"
      ]
    }
  }
}
```

---

## 区別の仕組み ── 総合解釈

### Slack が Work Object か否かを判別する基準

**アプリレベルの設定（静的な判別基準）**:

| 条件 | Work Object 有り | Work Object 無し |
|------|-----------------|-----------------|
| Work Object Previews | 有効化済み + エンティティタイプ選択 | 未設定 |
| `entity_details_requested` サブスクリプション | あり | なし |

この設定の有無によって、**Slack はそのアプリの検索結果に Work Object（flexpane）を提供するかどうかを判断する**。

**検索結果レベルのリンク（動的な識別子）**:

- `search_results.external_ref.id` が Work Object の `external_ref.id` と同一値である
- これにより、どの検索結果がどの Work Object エンティティに対応するかが Slack に伝わる

### ユーザーが検索結果をクリックしたときの動作

| アプリ設定 | クリック時の動作 |
|-----------|----------------|
| Work Objects 未設定 | `link` URL に遷移するだけ（通常のリンク） |
| Work Objects 設定済み | `entity_details_requested` イベントが発火 → flexpane を開く |

### entity_details_requested の context 判別

同じ `entity_details_requested` イベントが発火しても、以下の有無で呼び出し元を判別できる:

| フィールド | unfurl（チャット）から開いた場合 | Enterprise Search から開いた場合 |
|-----------|-------------------------------|-------------------------------|
| `channel` | あり | **なし** |
| `message_ts` | あり | **なし** |
| `thread_ts` | あり | **なし** |
| `external_ref` | あり（`chat.unfurl` で設定した値）| ある場合とない場合がある（Slack 開発プロバイダの場合はなし） |

→ **`channel` / `message_ts` / `thread_ts` の存在・不在が最も確実な判別手段**

---

## 問題・疑問点

- Work Objects が設定済みのアプリから検索結果を返す際、`search_results` オブジェクトに `external_ref` を設定しなかった場合の挙動は不明（Work Object として扱われるか、通常結果として扱われるかは記載なし）
- Work Objects の entity type を複数設定した場合、検索結果ごとに異なる entity type を返す方法は記載なし（entity type は `entity_details_requested` の応答 `entity.presentDetails` で指定するため、result ごとに変えることは可能と推測）
