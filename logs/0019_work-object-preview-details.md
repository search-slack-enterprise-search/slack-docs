# Work Object Preview の詳細 — 調査ログ

## 調査日
2026-04-16

## タスク概要
Work Object Preview とは何かを具体的に調査し、使うべき時・使わない方が良い時を明確にする。

---

## 調査ファイル一覧

- `docs/messaging/work-objects-overview.md`
- `docs/messaging/work-objects-implementation.md`
- `docs/reference/events/entity_details_requested.md`
- `docs/reference/methods/entity.presentDetails.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`（Work Objects support セクション）
- `docs/changelog/2025/10/22/work-objects.md`

---

## 調査アプローチ

1. `Grep` で "Work Object Preview" をドキュメント全体から検索 → 2 ファイルがヒット（work-objects-overview.md / work-objects-implementation.md）
2. 両ファイルを全文 Read
3. 関連する API リファレンス（entity.presentDetails, entity_details_requested）を Read
4. Enterprise Search との接点を確認
5. changelog でリリース日・経緯を確認

---

## 調査結果

### 1. Work Objects とは何か（work-objects-overview.md）

**ソース:** `docs/messaging/work-objects-overview.md:1-101`

> One of the primary ways to share external content within Slack is by posting URL links in conversations. However, links in their primitive form don't provide a lot of information. That's why we originally introduced link unfurling, so that Slack apps could provide rich previews and actions inside of conversations without requiring users to click the link. With Work Objects, apps can take the unfurling experience even further.

Work Objects は「リンクアンファーリングを更に進化させた体験」と位置づけられている。

> Work Objects can represent any type of entity or data *other* than conversations within Slack. Examples include files, tasks, and incidents. Work Objects aim to standardize the presentation of these entities inside Slack and to provide users with richer previews and greater feature extensibility.

Work Objects は Slack 内の会話以外あらゆるエンティティを表現できる。ファイル・タスク・インシデントが例として挙げられている。表示の標準化とリッチなプレビュー、機能拡張性の提供が目的。

**2つの主要コンポーネント（line 9）:**

> Work Objects have two primary components: the unfurl component, and the flexpane component.

---

### 2. Unfurl コンポーネント

**ソース:** `docs/messaging/work-objects-overview.md:11-19`

> Work Objects appear when a link is unfurled in a conversation. Each Work Object is represented by an entity, such as the `Task` entity.

> Similar to link unfurls, the content of a Work Object is visible to everyone in the conversation. Therefore, it's important to avoid sending sensitive information and to ensure the content is relevant to all users.

- URL をメッセージに貼ると unfurl として表示される
- **会話内の全員に見える** → 機密情報を含んではいけない
- `chat.unfurl` API に `metadata` パラメータを渡すことで実装

---

### 3. Flexpane コンポーネント

**ソース:** `docs/messaging/work-objects-overview.md:21-29`

> When a user clicks on a Work Object unfurl, a flexpane opens on the right side of Slack to reveal more content. This new surface provides an additional layer of rich contextual information and customization options for apps.

> It can also optionally require user authentication into a third-party service, which is useful in scenarios where the flexpane may display sensitive information. As general guidance, any information that you would not like to show in the unfurl can be shown in the flexpane following authentication.

- unfurl クリックで Slack 右側に開く詳細ビュー（「フレックスペイン」）
- **ユーザーごとに個別の情報**を表示できる（per-user）
- **認証を要求できる** → 機密情報をここに表示可能
- 関連会話（Related Conversations）もここに集約される
- `entity_details_requested` イベント + `entity.presentDetails` API で実装

---

### 4. "Work Object Previews" とはアプリ設定のメニュー名

**ソース:** `docs/messaging/work-objects-implementation.md:10-14`

```
1. Visit https://api.slack.com/apps and select your app.
2. Navigate to **Work Object Previews** under the left sidebar menu.
3. Enable the toggle.
4. Select the entity type(s) that you would like to add to your app.
5. Click Save.
```

「Work Object Previews」とは、アプリ設定のサイドバーメニュー項目の名前。ここで Work Objects 機能を有効化し、使用するエンティティタイプを選択する。

**Enterprise Search との関係（work-objects-overview.md:89）:**

> To support Work Objects for your app's Enterprise Search results, traditional search results, and AI answers citations, your app must subscribe to the `entity_details_requested` event. You can define the type of Work Objects for your search results, such as an item, within the Work Object Previews view within app settings.

Enterprise Search の検索結果・通常の検索結果・AI 回答の引用にも Work Objects を適用する場合も、**アプリ設定の Work Object Previews でエンティティタイプを定義する**必要がある。

---

### 5. サポートされているエンティティタイプ（5種類）

**ソース:** `docs/messaging/work-objects-implementation.md:729-819`

| タイプ名 | entity_type | 用途例 |
|---|---|---|
| File | `slack#/entities/file` | ドキュメント・スプレッドシート・画像など |
| Task | `slack#/entities/task` | チケット・ToDo など |
| Incident | `slack#/entities/incident` | インシデント・サービス停止など |
| Content Item | `slack#/entities/content_item` | コンテンツページ・記事ページなど |
| Item | `slack#/entities/item` | 汎用エンティティ（custom_fields のみ使用） |

`Item` タイプは `fields` を持たず、全プロパティを `custom_fields` で定義する汎用エンティティ。

---

### 6. Entity Payload スキーマ

**ソース:** `docs/messaging/work-objects-implementation.md:106-119`

```json
{
  "entity_payload": {
    "attributes": {},    // タイトル・表示タイプ・プロダクト名・アイコン・フルサイズプレビューなど
    "fields": {},        // エンティティタイプ固有のフィールド（推奨フィールド名あり）
    "custom_fields": [], // 任意のカスタムフィールド（オプション）
    "display_order": []  // フィールドの表示順（オプション）
  }
}
```

`attributes` の主要フィールド（work-objects-implementation.md:122-124）:
- `title.text` — 必須。エンティティのタイトル
- `display_id` — 任意。ユーザーフレンドリーな文字列 ID
- `display_type` — 任意。デフォルトは File なら "File"、Task なら "Task"
- `product_name` — 任意。Work Objects ヘッダーに表示するプロダクト名（デフォルト: アプリ名）
- `product_icon` — 任意。Work Objects ヘッダーのアイコン
- `full_size_preview` — 任意。フルサイズプレビュー（画像・PDF のみ対応）
- `metadata_last_modified` — UNIX タイムスタンプ。メタデータの最終変更日時（自動更新の制御に使用）

---

### 7. フレックスペインの実装詳細

**ソース:** `docs/messaging/work-objects-implementation.md:78-104`

フレックスペインの実装には `entity_details_requested` イベントの購読が必要:

1. api.slack.com/apps からアプリを選択
2. Events & Subscriptions > Subscribe to bot events
3. `entity_details_requested` イベントを追加

イベントペイロードの例（`docs/messaging/work-objects-implementation.md:1247-1253`）:
```json
{
  "type": "entity_details_requested",
  "user": "U0123456",
  "external_ref": { "id": "123", "type": "my-type" },
  "entity_url": "https://example.com/document/123",
  "app_unfurl_url": "https://example.com/document/123?myquery=param",
  "trigger_id": "...",
  "user_locale": "en-US",
  "channel": "C123ABC456",  // Enterprise Search からの場合は含まれない
  "message_ts": "..."
}
```

**重要:** `channel`・`message_ts`・`thread_ts` は「メッセージコンテキスト外（Enterprise Search など）から開かれた場合は提供されない」とドキュメントに明記されている。

イベント受信後、`entity.presentDetails` API を呼んでフレックスペインを表示:
```
POST https://slack.com/api/entity.presentDetails
```
- `trigger_id` — 必須
- `metadata` — フレックスペイン用メタデータ（`chat.unfurl` と同じスキーマだが `entities` 配列と `app_unfurl_url` は不要）
- `user_auth_required` — 認証が必要な場合は true
- `user_auth_url` — 認証 URL

---

### 8. フレックスペインコンテンツのリフレッシュ仕様

**ソース:** `docs/messaging/work-objects-implementation.md:1259-1283`

- 初回クリック時: 常に `entity_details_requested` イベントが送信される
- リフレッシュボタンクリック: 常にイベント送信
- **10分間の TTL**: フレックスペインを一度開いた後、10分間はキャッシュされる
  - 10分以内に再度開いても、タブ切替をしてもイベントは送信されない
  - 10分経過後は再度イベントが送信される
  - フレックスペインを開いているときは「データが古い可能性」を示す赤いドットがリフレッシュボタンに表示される

---

### 9. 編集機能（Editing）

**ソース:** `docs/messaging/work-objects-implementation.md:224-604`

フレックスペインでフィールドを編集可能にできる。`edit.enabled: true` を設定するだけで該当フィールドが編集可能になる。

```json
{
  "fields": {
    "description": {
      "value": "...",
      "format": "markdown",
      "edit": { "enabled": true }
    }
  }
}
```

- ユーザーが「Save」をクリックすると `view_submission` イベントが送信される
- `view.type` は `entity_detail` に設定される
- 3種類のバリデーション: クライアントサイドフィールドレベル・サーバーサイドフィールドレベル・サーバーサイドフォームレベル

---

### 10. アクション（ボタン）

**ソース:** `docs/messaging/work-objects-implementation.md:606-728`

- `primary_actions`: 最大2個（フッターに常時表示）
- `overflow_actions`: 最大5個（「More actions」メニュー内）
- unfurl カードとフレックスペインで別々のアクションを定義できる

---

### 11. 自動ファイルシェア

**ソース:** `docs/messaging/work-objects-implementation.md:152-201`

エンティティメタデータの画像フィールドに `slack_file` オブジェクトを含めると、Slack が自動的に会話にファイルシェアを作成する。
- セキュリティ強化: Slack 内にホストされるため公開インターネットに露出しない
- `files.remote.share` の呼び出しや別途ファイルブロックが不要になる

---

### 12. Slack Marketplace への提出に関する注意事項

**ソース:** `docs/messaging/work-objects-overview.md:95-100`

> If your app already supports the link unfurls feature and has all the required scopes, workspace re-authentication is not needed for Work Object unfurls to appear in customer workspaces. Since the Work Objects feature requires a new event subscription, a new Slack Marketplace submission is required.

> The `external_ref` format or IDs must not change for a given Work Object, as it is used for related conversations tracking.

- 既存のリンクアンファーリングアプリも再認証不要で Work Objects を利用できる
- ただし新たな Marketplace 提出が必要
- `external_ref` の ID は**変更不可**（Related Conversations トラッキングに使用される）

---

### 13. リリース情報（changelog）

**ソース:** `docs/changelog/2025/10/22/work-objects.md`

> As you may have spied in the Slack CLI v3.9.0 release yesterday, support for Work Objects is now generally available! 🎉

2025年10月22日に一般提供（GA）開始。

---

## 考察: 使うべき時・使わない方が良い時

### 使うべき時

1. **外部サービスのリンクをリッチな形式で表示したい時**
   - GitHub Issues/PRs、Jira チケット、Confluence ページ、Notion など
   - リンクを貼るだけで概要（ステータス・担当者・期日など）が一目でわかるようにしたい
   
2. **ユーザーが Slack を離れなくても操作できるようにしたい時**
   - フレックスペインでの詳細確認・編集・アクション実行

3. **機密情報を含む詳細を表示したい時**
   - unfurl（全員に見える）は最小限の情報
   - フレックスペインに認証を要求し、認証後に詳細を表示

4. **Enterprise Search の検索結果をリッチにしたい時**
   - 検索結果をクリックした際にフレックスペインで詳細表示
   - AI 回答の引用表示にも適用される

5. **外部データをリアルタイムで表示・更新したい時**
   - refresh ボタンで最新情報を取得
   - フレックスペイン内での編集→外部システムへの反映

### 使わない方が良い時

1. **機密情報が unfurl（会話全員に見える）に漏れてしまう場合**
   - unfurl は会話参加者全員に表示されるため、センシティブな情報を unfurl に含めてはいけない

2. **Slack Marketplace への公開を予定している Enterprise Search アプリ**
   - Enterprise Search アプリは Marketplace に公開・配布不可（CLAUDE.md の重要事項）

3. **シンプルな静的情報だけを表示したい場合**
   - 通常の link unfurling の方が実装コストが低い

4. **`external_ref` の ID が頻繁に変わる仕組みの場合**
   - `external_ref` は変更不可（Related Conversations トラッキングが壊れる）
   - ID が変わるなら Work Objects は不向き

5. **アプリが link unfurling を実装していない場合（フレックスペインのみ必要な場合）**
   - フレックスペインは unfurl コンポーネントの実装が前提
   - `entity.presentDetails` API の `channel`・`message_ts` がないシナリオ（Enterprise Search）もあることを念頭に置く

---

## 問題・疑問点

- SDK サポート状況: changelog では「SDK support for these API updates is coming soon」とあったが、overview ドキュメントでは Bolt for JavaScript・Bolt for Java のコード例が掲載されているため、少なくとも一部は既にサポート済みと思われる。Bolt for Python は「coming soon」の記述が残っている。
- フレックスペインの `entity.presentDetails` API のレートリミット: Tier 3（50+/分）。高頻度のアクセスが予想される場合は注意が必要。
