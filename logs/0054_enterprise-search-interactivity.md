# Enterprise Search と Interactivity の連携 調査ログ

## 調査日時
2026-04-24

## タスク概要
manifest.json を調べていたら `settings.interactivity` があり、検索結果にボタンが使えるように見えた。Enterprise Search と Interactivity を連携できるのか、できるならどう使えるのかを調査する。

---

## 調査アプローチ

1. `enterprise-search/` ディレクトリでの interactivity 言及を確認
2. `reference/app-manifest.md` の interactivity 設定の詳細を読む
3. `messaging/work-objects-overview.md` と `messaging/work-objects-implementation.md` を読む
4. `interactivity/index.md` と `interactivity/handling-user-interaction.md` を読む
5. `reference/events/entity_details_requested.md` を確認

---

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/index.md`
- `docs/reference/app-manifest.md`
- `docs/messaging/work-objects-overview.md`
- `docs/messaging/work-objects-implementation.md`
- `docs/interactivity/index.md`
- `docs/interactivity/handling-user-interaction.md`
- `docs/reference/events/entity_details_requested.md`

---

## 調査結果

### 1. Enterprise Search の検索結果オブジェクト（interactivity は含まれない）

`docs/enterprise-search/developing-apps-with-search-features.md` によると、`search_results` オブジェクトのフィールドは以下の通り：

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `external_ref` | object | 必須 | 一意の識別子オブジェクト |
| `title` | string | 必須 | タイトル |
| `description` | string | 必須 | 説明 |
| `link` | string | 必須 | URI |
| `date_updated` | string | 必須 | 更新日時（YYYY-MM-DD形式） |
| `content` | string | 任意 | 詳細コンテンツ（AI アンサー用） |

**結論: 検索結果オブジェクト自体にはボタン等の interactive elements は存在しない。**

Enterprise Search のドキュメント（`docs/enterprise-search/` 配下）には「interactivity」という単語は一切登場しない。

---

### 2. manifest.json の `settings.interactivity` の位置づけ

`docs/reference/app-manifest.md`（line 729-767）に詳細：

```
settings.interactivity
  A subgroup of settings that describe interactivity configuration for the app.
  Optional

settings.interactivity.is_enabled
  A boolean that specifies whether or not interactivity features are enabled.
  Required (if using interactivity settings)

settings.interactivity.request_url
  A string containing the full https URL that acts as the interactive Request URL.
  Optional

settings.interactivity.message_menu_options_url
  A string containing the full https URL that acts as the interactive Options Load URL.
  Optional
```

サンプル（JSON）：
```json
"settings": {
  "interactivity": {
    "is_enabled": true,
    "request_url": "https://example.com/slack/message_action",
    "message_menu_options_url": "https://example.com/slack/message_menu_options"
  }
}
```

**`settings.interactivity` は Enterprise Search 専用ではなく、アプリ全体の Interactivity（Block Kit ボタンクリック・ショートカット・モーダル送信等）のリクエスト URL を設定するもの。**

`interactivity/handling-user-interaction.md` によると：
- `block_actions` ペイロード：Block Kit interactive component をクリックしたとき
- `shortcut` / `message_actions` ペイロード：ショートカット使用時
- `view_submission` ペイロード：モーダル送信時
- `view_closed` ペイロード：モーダルキャンセル時

これらすべてが `settings.interactivity.request_url` に送信される。

---

### 3. Work Objects を通じた Enterprise Search との interactivity 連携

**`docs/messaging/work-objects-overview.md` の「Support for Enterprise Search」セクション（line 87-93）に明記：**

> To support Work Objects for your app's Enterprise Search results, traditional search results, and AI answers citations, your app must subscribe to the `entity_details_requested` event. You can define the type of Work Objects for your search results, such as an item, within the Work Object Previews view within app settings.
> 
> Once your app is subscribed to the `entity_details_requested` event, it can respond to the event and call the `entity.presentDetails` API method with Work Object metadata to launch the flexpane experience.

**連携の仕組み：**

1. Enterprise Search の検索結果で `external_ref.id` を設定する（Work Objects の `external_ref.id` と同じ値を使う）
2. ユーザーが検索結果をクリックすると `entity_details_requested` イベントが発火する
3. アプリが `entity.presentDetails` を呼び出してフレックスペインにコンテンツとアクションボタンを表示する
4. ユーザーがボタンをクリックすると `block_actions` イベントが interactivity の Request URL に送信される

---

### 4. Work Objects のアクション（ボタン）仕様

`docs/messaging/work-objects-implementation.md`（line 606-713）に詳細：

**アクションの定義場所：** `entity_payload.actions`

```json
{
  "actions": {
    "primary_actions": [],   // 最大2つ（アンフォールカード/フレックスペインフッターに表示）
    "overflow_actions": []   // 最大5つ（オーバーフローメニューに表示）
  }
}
```

**各アクションのプロパティ：**

| プロパティ | 必須 | 型 | 説明 |
|---|---|---|---|
| `text` | 必須 | string | ボタンに表示するテキスト |
| `action_id` | 必須 | string | アクションの識別子（最大255文字） |
| `value` | 任意 | string | interaction payload に送信する値（最大2000文字） |
| `style` | 任意 | string | `"primary"`（緑背景）または `"danger"`（赤背景） |
| `url` | 任意 | string | クリック時にブラウザで開くURL（最大3000文字） |
| `accessibility_label` | 任意 | string | スクリーンリーダー用ラベル（最大75文字） |

**サンプル（entity_payload全体の構造）：**

```json
{
  "entities": [
    {
      "app_unfurl_url": "https://github.com/issues",
      "entity_type": "slack#/entities/task",
      "entity_payload": {
        "attributes": {},
        "fields": {},
        "actions": {
          "primary_actions": [
            {
              "text": "Summarize issue with AI",
              "action_id": "github_wo_button_summarize_issue",
              "style": "primary",
              "value": "user"
            },
            {
              "text": "Close issue",
              "action_id": "github_wo_button_close_issue",
              "style": "danger",
              "value": "user"
            }
          ],
          "overflow_actions": [
            {
              "text": "Pin issue",
              "action_id": "github_wo_button_pin_issue",
              "style": "primary",
              "value": "user"
            }
          ]
        }
      }
    }
  ]
}
```

---

### 5. block_actions イベントの特徴（Enterprise Search 経由の場合）

`docs/messaging/work-objects-implementation.md`（line 701-716）：

> When a user clicks a button, a `block_actions` interactivity request is sent to your app.

> Note that `container.type` will be `message_attachment` when the event is coming from an action on the unfurl, and will be `entity_detail` when the event is coming from an action on the flexpane.

ペイロードの `container` オブジェクトには以下が含まれる（Enterprise Search 経由でも同様）：
- `entity_url`
- `external_ref`
- `app_unfurl_url`
- `message_ts`
- `thread_ts`
- `channel_id`

---

### 6. entity_details_requested イベントの Enterprise Search 特有の動作

`docs/messaging/work-objects-implementation.md`（line 1252）の event payload コメントより：

```
// These fields will not be provided when the entity details are opened
// from outside of a message context (i.e., Enterprise Search)
"channel": "C123ABC456",
"message_ts": "1755035323.759739",
"thread_ts": "1755035323.759739",
```

**Enterprise Search 経由でユーザーが検索結果をクリックした場合、`channel`・`message_ts`・`thread_ts` は提供されない。**

---

### 7. manifest.json の必要な設定まとめ

Enterprise Search + Work Objects + Interactivity を実装するには以下の設定が必要：

```json
{
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "bot_events": [
        "function_executed",
        "entity_details_requested"
      ]
    },
    "interactivity": {
      "is_enabled": true,
      "request_url": "https://example.com/slack/actions"
    },
    "function_runtime": "remote"
  },
  "features": {
    "search": {
      "search_function_callback_id": "search_function",
      "search_filters_function_callback_id": "search_filters_function"
    }
  }
}
```

加えて、アプリ設定の「Work Object Previews」でエンティティタイプを設定する必要がある（UIでの操作、manifest では設定不可）。

---

### 8. フロー全体図

```
ユーザーが Slack 検索を実行
  ↓
[Enterprise Search] function_executed イベント発火
  ↓
アプリが search_results を返す（external_ref.id を含む）
  ↓
Slack が検索結果を表示
  ↓
ユーザーが検索結果をクリック
  ↓
[Work Objects] entity_details_requested イベント発火（Enterprise Search 経由では channel/message_ts なし）
  ↓
アプリが entity.presentDetails を呼び出す（entity_payload.actions にボタンを含む）
  ↓
フレックスペインが開き、アクションボタンが表示される
  ↓
ユーザーがボタンをクリック
  ↓
[Interactivity] block_actions ペイロードが request_url に送信される
  ↓
アプリがアクションを処理・応答する
```

---

## 問題・疑問点

1. **Work Objects の Previews 設定はUI操作が必要**: アプリ設定画面の「Work Object Previews」でエンティティタイプを有効化する必要がある。これは manifest.json では設定できない可能性が高い（ドキュメントに明記なし）。

2. **Enterprise Search の検索結果と Work Objects の紐付け**: `search_results` の `external_ref.id` と Work Object の `external_ref.id` が一致することで紐付けられるとドキュメントに記載あり（`developing-apps-with-search-features.md` line 163: "If your app implements Work Objects, this should be same value used for that implementation."）。

3. **block_actions ペイロードの `container`**: Enterprise Search 経由の場合の `container` の詳細な差異についてドキュメントに明確な記述が見当たらない（`message_attachment` vs `entity_detail`）。

---

## 調査結論

**Enterprise Search と interactivity は直接連携しない。** しかし、**Work Objects** を経由することでボタン等のインタラクティブな要素を利用できる。

具体的には：
- Enterprise Search の検索結果をクリックすると Work Objects のフレックスペインが開く
- フレックスペインには `primary_actions`（最大2つ）と `overflow_actions`（最大5つ）のボタンが配置可能
- ボタンをクリックすると `block_actions` イベントが manifest の `settings.interactivity.request_url` に送信される

manifest.json の `settings.interactivity` は Enterprise Search 専用の設定ではなく、アプリ全体の interactivity 設定。Enterprise Search + Interactivity を実現するには Work Objects の実装が必要で、`entity_details_requested` イベントの購読と `entity.presentDetails` の実装が必要になる。
