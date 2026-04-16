# Work Objects 調査ログ

## 調査ファイル一覧

- `docs/messaging/work-objects-overview.md`
- `docs/messaging/work-objects-implementation.md`
- `docs/changelog/2025/10/22/work-objects.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`（Work Objects サポートセクション）
- `docs/enterprise-search/index.md`
- `docs/reference/events/entity_details_requested.md`
- `docs/reference/events/link_shared.md`
- `docs/reference/methods/entity.presentDetails.md`
- `docs/slack-marketplace/slack-marketplace-app-guidelines-and-requirements.md`（Work Objects セクション）

## 調査アプローチ

1. `grep -i "work.object"` で `docs/` 全体をファイルリスト検索 → 21件のファイルヒット
2. 主要ドキュメント（overview, implementation, changelog）を順次精読
3. Enterprise Search との連携部分を `developing-apps-with-search-features.md` で確認
4. 関連 API / イベントリファレンスを確認（`entity_details_requested`、`entity.presentDetails`、`link_shared`）
5. Marketplace ガイドラインでの Work Objects 要件を確認

---

## 調査結果

### 1. Work Objects の基本概念（`docs/messaging/work-objects-overview.md`）

> "Work Objects can represent any type of entity or data _other_ than conversations within Slack. Examples include files, tasks, and incidents. Work Objects aim to standardize the presentation of these entities inside Slack and to provide users with richer previews and greater feature extensibility."

**Work Objects とは**:
- Slack 内で URL リンクをシェアしたときに表示される「リッチプレビュー」の拡張版
- 元々の link unfurling（URL のリッチプレビュー）をさらに進化させたもの
- ファイル・タスク・インシデントなど、Slack 会話以外のあらゆるエンティティを表現できる
- エンティティの表示を標準化し、よりリッチなプレビューと機能拡張性を提供する

**リリース**: 2025年10月22日に一般公開（GA）

---

### 2. 2つの主要コンポーネント

#### Unfurl コンポーネント
- リンクがチャンネルでアンフールされると表示されるカード形式のプレビュー
- チャンネルにいる全員に見える
- センシティブな情報は送らないよう注意が必要

#### Flexpane コンポーネント
- Unfurl カードをクリックすると Slack 右側に開くパネル（フレックスペイン）
- より詳細な情報・カスタマイズオプションを提供する追加レイヤー
- オプションでサードパーティサービスへのユーザー認証を要求できる（センシティブ情報の保護）
- 未認証ユーザーには unfurl のコンテンツをプレースホルダとして表示
- 関連会話（Related conversations）タブを自動集約

---

### 3. サポートされているエンティティタイプ（`docs/messaging/work-objects-implementation.md`）

| Type | entity_type | 説明 |
|------|------------|------|
| File | `slack#/entities/file` | ドキュメント・スプレッドシート・画像など |
| Task | `slack#/entities/task` | チケット・To-Do など |
| Incident | `slack#/entities/incident` | インシデント・サービス障害など |
| Content Item | `slack#/entities/content_item` | コンテンツページ・記事ページなど |
| Item | `slack#/entities/item` | 汎用エンティティ（何でも表現できる） |

---

### 4. 実装の仕組み（`docs/messaging/work-objects-implementation.md`）

#### Unfurl の実装フロー
1. ユーザーが URL をチャンネルに投稿する
2. Slack が `link_shared` イベントをアプリに送信する
3. アプリが `chat.unfurl` API を呼び出し、`metadata` パラメータに Work Object エンティティ情報を含める
4. Slack が Work Object カードをチャンネルに表示する

`chat.unfurl` の metadata スキーマ:
```json
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

#### Flexpane の実装フロー
1. ユーザーが Unfurl カードをクリックする
2. Slack が `entity_details_requested` イベントをアプリに送信する
3. アプリが `entity.presentDetails` API を呼び出し、フレックスペインのコンテンツを渡す

#### Notifications の実装（リンクアンフールなしのパターン）
- `chat.postMessage` でも `eventAndEntityMetadata` パラメータを使って Work Object エンティティを含めることができる
- この場合 `app_unfurl_url` は不要

---

### 5. Entity Payload スキーマ

エンティティペイロードの基本構造:
```json
{
  "entity_payload": {
    "attributes": {},
    "fields": {},
    "custom_fields": [],
    "display_order": []
  }
}
```

#### attributes（ヘッダー情報）
- `title`（必須）: Work Object のタイトル
- `display_id`: ユーザー向けの表示用 ID
- `display_type`: 表示されるリソースの種類文字列（例: "Document"）
- `product_name`: ヘッダーに表示されるプロダクト名（デフォルトはアプリ名）
- `product_icon`: ヘッダーに表示されるアイコン（公開 URL または `slack_file`）
- `full_size_preview`: フルサイズプレビュー（画像・PDF）のサポート情報
- `metadata_last_modified`: メタデータの最終更新タイムスタンプ（リフレッシュ判定に使用）

#### fields（エンティティ種別ごとの標準フィールド）
エンティティタイプに応じた推奨フィールドが定義されている:
- File: `preview`, `created_by`, `date_created`, `date_updated`, `last_modified_by`, `file_size`, `mime_type`
- Task: `description`, `created_by`, `date_created`, `date_updated`, `assignee`, `status`, `due_date`, `priority`
- Incident: `status`, `severity`, `created_by`, `assigned_to`, `date_created`, `date_updated`, `description`, `service`
- Content Item: `preview`, `description`, `created_by`, `date_created`, `date_updated`, `last_modified_by`

#### custom_fields（カスタムフィールド）
アプリ独自のプロパティを自由に定義できる:
```json
{
  "custom_fields": [{
    "key": "ticket_type",
    "label": "Ticket Type",
    "value": "Epic",
    "type": "string"
  }]
}
```

#### サポートされるデータ型
- `string`, `integer`, `boolean`, `array`
- `slack#/types/user`: Slack ユーザー（user_id または text/email で指定）
- `slack#/types/channel_id`: Slack チャンネル ID
- `slack#/types/timestamp`: UNIX タイムスタンプ
- `slack#/types/date`: YYYY-MM-DD 形式の日付
- `slack#/types/image`: 画像（公開 URL または slack_file）
- `slack#/types/entity_ref`: 同一アプリ内の別 Work Object エンティティへの参照
- `slack#/types/link`: URL リンク
- `slack#/types/email`: メールアドレス

---

### 6. フィールドの編集機能

- フレックスペインで表示されているフィールドをユーザーが直接編集できる機能
- `edit.enabled: true` を設定したフィールドが編集可能になる
- 編集内容は `view_submission` イベントでアプリに送られる（コールバック ID: `work-object-edit`）
- バリデーションは3レベル: クライアントサイドフィールド / サーバーサイドフィールド / サーバーサイドフォーム

---

### 7. アクション機能

- Block Kit のボタンを Unfurl カードやフレックスペインのフッターに追加できる
- Primary actions: 最大2つ（ボタン）
- Overflow actions: 最大5つ（「More actions」メニューに表示）
- デフォルトで一部のアクション（Share / Copy link / Add to To-do / View in App）が含まれる

---

### 8. Enterprise Search との連携（`docs/messaging/work-objects-overview.md` & `docs/enterprise-search/developing-apps-with-search-features.md`）

> "To support Work Objects for your app's Enterprise Search results, traditional search results, and AI answers citations, your app must subscribe to the `entity_details_requested` event."

**Enterprise Search での Work Objects の使い方**:
1. アプリは `entity_details_requested` イベントをサブスクライブする
2. アプリ設定の「Work Object Previews」で検索結果のアイテムの種類（entity type）を定義する（例: Item）
3. ユーザーが Enterprise Search の検索結果のアイテムをクリックすると、`entity_details_requested` イベントが発火
4. アプリは `entity.presentDetails` API を呼び出してフレックスペインを開く

**重要なポイント**:
- Enterprise Search から開かれたフレックスペインでは `external_ref` が提供されない場合がある（"when a work object is opened from an Enterprise Search result provided by a Slack-developed search provider, we cannot provide an `external_ref`"）
- `developing-apps-with-search-features.md` に `search_result_id` に関する記述: "If your app implements Work Objects, this should be same value used for that implementation." → Enterprise Search の `id` と Work Objects の `external_ref.id` を同じ値にすることが推奨

---

### 9. entity_details_requested イベント（`docs/reference/events/entity_details_requested.md`）

```json
{
  "type": "entity_details_requested",
  "user": "U0123456",
  "external_ref": {
    "id": "123",
    "type": "my-type"
  },
  "entity_url": "https://example.com/document/123",
  "link": {
    "url": "https://example.com/document/123",
    "domain": "example.com"
  },
  "app_unfurl_url": "https://example.com/document/123?myquery=param",
  "event_ts": "123456789.1234566",
  "trigger_id": "1234567890123.1234567890123.abcdef01234567890abcdef012345689",
  "user_locale": "en-US",
  "channel": "C123ABC456",
  "message_ts": "1755035323.759739",
  "thread_ts": "1755035323.759739"
}
```

**スコープ**: 不要（No scopes required）

**注意**: `channel`, `message_ts`, `thread_ts` はメッセージコンテキスト外（Enterprise Search）から開かれた場合は含まれない

---

### 10. entity.presentDetails API（`docs/reference/methods/entity.presentDetails.md`）

- **URL**: `POST https://slack.com/api/entity.presentDetails`
- **必須**: `token`, `trigger_id`
- **オプション**: `metadata`, `user_auth_required`, `user_auth_url`, `error`
- **レートリミット**: Tier 3（50+ per minute）
- **スコープ**: 不要

`entity_details_requested` イベントの `trigger_id` を使い、フレックスペインのコンテンツをユーザー単位で提供する（per-user flexpane metadata）。

Enterprise Grid 考慮事項: Slack user ID はグローバルにユニークなため、`team_id` への依存は不要。

---

### 11. Flexpane コンテンツのリフレッシュ

- 最初にフレックスペインを開いたとき: 常に `entity_details_requested` が発火
- ユーザーがリフレッシュボタンをクリック: 常に発火
- 2回目以降の開閉: 10分間の TTL が経過した後に発火
- TTL 未経過の場合は発火しない（単純な開閉、タブ切り替え、操作は再発火しない）

---

### 12. Slack Marketplace との関係（`docs/slack-marketplace/slack-marketplace-app-guidelines-and-requirements.md`）

> "[Work objects] add a whole new dimension to standard unfurls, making it possible to represent external content (e.g files, tasks, incidents, pull requests) in a structured way in Slack."

- Work Objects は Slack Marketplace に提出・配布**可能**（Enterprise Search とは異なる点）
- 既存の link unfurl 対応アプリで必要なスコープを持つ場合、Work Object unfurl 表示に再認証は不要
- ただし新しいイベントサブスクリプション（`entity_details_requested`）が必要なため、新規の Marketplace 提出が必要
- `external_ref` の形式やIDは変更不可（Related Conversations のトラッキングに使用されるため）

Marketplace ガイドラインの DO/DON'T:
- ✅ 認証が必要な場合はフレックスペインにエラーを表示する
- ✅ 認証済みだがアクセス権がない場合もエラーを表示する
- ✅ 認証以外のエラーはエフェメラルメッセージや DM で通知する
- ✅ Slack のメッセージフォーマットでマークダウンを扱う
- ✅ ブロックが壊れたイメージやテキスト切れなく表示されるか確認する
- ✅ 複数エンティティタイプが有効な場合は各タイプを適切に処理する

---

### 13. 自動ファイルシェア機能

- `entity_payload` 内の画像フィールドで `slack_file` オブジェクトを使用すると、Slack が自動でファイルをチャンネルにシェアする
- 公開 URL の代わりに Slack ファイルとして管理できる（セキュリティ向上、統合ファイル管理）
- 対応フィールド: `entity_payload.slack_file`（File エンティティ）、`attributes.product_icon`、`entity_payload.fields` 内の画像/ファイルフィールド、`custom_fields`（type が `slack#/types/image` または `slack#/types/file`）

---

## まとめ（調査の判断・解釈）

**Work Objects の本質**:
Work Objects は「link unfurling の進化版」であり、外部サービスのデータ（ファイル・タスク・インシデントなど）を Slack 内でネイティブに近い体験で表示・操作できるようにするフレームワーク。単なる URL プレビューを超えて、Slack 内からフィールド編集・アクション実行ができる。

**外部情報としての扱い**:
- `external_ref.id` で外部サービス上のIDを管理（Slack 側でリソースを一意識別するため）
- `url` で外部サービス上の正規URLを指定
- Slack はこれらを使って「どのリソースについての情報か」を追跡し、Related Conversations（関連会話）を集約する
- **Enterprise Search との ID 統一**: Enterprise Search の `search_result_id` と Work Objects の `external_ref.id` を同じ値にすることが推奨されている

**Enterprise Search における位置づけ**:
Work Objects は Enterprise Search の検索結果アイテムに対して「フレックスペインで詳細表示」できる仕組みを提供する。Enterprise Search が「検索して見つける」部分を担い、Work Objects が「見つけたアイテムの詳細を Slack 内で確認・操作する」部分を担う。

**Marketplace 配布可否**:
- Enterprise Search アプリ: Marketplace 配布**不可**
- Work Objects 単体のアプリ: Marketplace 配布**可能**
- Enterprise Search + Work Objects を組み合わせたアプリ: 配布不可（Enterprise Search の制約が優先）
