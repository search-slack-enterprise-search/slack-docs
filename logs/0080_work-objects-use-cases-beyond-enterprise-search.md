# ログ: Work Objects の Enterprise Search 以外での利用用途

## 調査ファイル一覧

- `docs/messaging/work-objects-overview.md`
- `docs/messaging/work-objects-implementation.md`
- `docs/changelog/2025/10/22/work-objects.md`
- `docs/concepts/choosing-the-right-surface.md`
- `docs/messaging/unfurling-links-in-messages.md`（rg 検索）
- `docs/messaging/creating-interactive-messages.md`（rg 検索）
- `docs/messaging/formatting-message-text.md`（rg 検索）
- `docs/messaging/working-with-files.md`（rg 検索）
- `docs/enterprise-search/index.md`（rg 検索）
- `docs/slack-marketplace/slack-marketplace-app-guidelines-and-requirements.md`（rg 検索）
- `docs/reference/methods/chat.postmessage.md`（rg 検索）
- `docs/reference/methods/chat.unfurl.md`（rg 検索）
- `docs/reference/events/link_shared.md`（rg 検索）

## 調査アプローチ

1. `fd` と `rg` で Work Objects 関連ファイルを網羅的に発見
2. 主要な概要ドキュメント (`work-objects-overview.md`、`work-objects-implementation.md`) を全文精読
3. `choosing-the-right-surface.md` でブロードな利用シーン比較を確認
4. 各リファレンスファイルに対して `rg` で Work Objects の言及箇所を確認

---

## 調査結果

### 1. Work Objects の全体像（`work-objects-overview.md` より）

Work Objects は Slack 内で「会話以外のあらゆるエンティティやデータ」を表現するための仕組み。ファイル、タスク、インシデントなどが例として挙げられる。

主要コンポーネントは 2 つ:
- **アンファールコンポーネント**: リンクがアンファールされた際にリッチプレビューを表示
- **フレックスペインコンポーネント**: Work Object クリック時に Slack 右側に開くサイドパネル

関連イベントと API:
- `link_shared` イベント → `chat.unfurl` API（metadata パラメータを追加使用）
- `entity_details_requested` イベント → `entity.presentDetails` API

> 「Work Objects can represent any type of entity or data _other_ than conversations within Slack.」

---

### 2. Enterprise Search 以外の具体的な利用用途

#### 2-1. リンクアンファール（Link Unfurl）

- `choosing-the-right-surface.md`: 「Work Objects are available in channels, DMs, notifications, canvases, Salesforce Lightning Experience (LEX) client, and mobile.」
- `unfurling-links-in-messages.md`: Work Objects はリンクアンファールの拡張機能として紹介されている
- `creating-interactive-messages.md` l.15: 「Work Objects allow you to facilitate rich user interactions by implementing flexpane components, unfurl cards, and supporting Block Kit actions such as action buttons.」

ユーザーがチャンネルや DM にリンクを貼ると `link_shared` イベントが発火し、アプリが `chat.unfurl` API にエンティティメタデータを渡すことで Work Object としてリッチプレビューが表示される。

利用可能な場所（チャンネル・DM・スレッド全て）で機能する。

**更新リフレッシュ機能**: ユーザーがホバーするとリフレッシュボタンが表示され、最新データに更新できる。また、フレックスペインでの操作後やボタンクリック後に自動リフレッシュも発生する。

---

#### 2-2. 通知（Notifications）/ chat.postMessage

`chat.postMessage` API を使って、リンクアンファールを経由せずに Work Object エンティティを直接メッセージとして投稿できる。

- `work-objects-implementation.md` l.76: 「The `chat.postMessage` API method can also be used to post Work Object entities by re-using the existing `metadata` parameter. In this case, no link has been unfurled, so the `app_unfurl_url` property is not required.」
- `chat.postmessage.md` l.124: 「You can also provide Work Object entity metadata using this parameter.」

`choosing-the-right-surface.md` の注意事項（l.256）:
> 「Don't use Work Objects for ephemeral notifications. If the content is a one-time alert with no persistent identity, the overhead of registering a Work Object adds complexity without value.」

→ 通知に Work Object を使えるが、永続的なエンティティを表すものに限るべきで、一時的なアラートには Block Kit の方が適切。

Bolt for Java での実装例:
```java
EntityMetadata entity = ...;
EntityMetadata[] entities = {entity};
EventAndEntityMetadata metadata = EventAndEntityMetadata.builder().entities(entities).build();
ChatPostMessageRequest request = ChatPostMessageRequest.builder()
    .token(ctx.getBotToken())
    .channel(ctx.getChannelId())
    .text("Check out this entity:")
    .eventAndEntityMetadata(metadata)
    .build();
```

---

#### 2-3. フレックスペイン（Flexpane）単体機能

Enterprise Search とは独立してフレックスペインを実装できる。Work Object アンファールをクリックすると起動。

機能:
- ユーザーが認証されていない場合に第三者サービスへの認証を要求できる (`user_auth_required=true`)
- Work Object が参照されたすべての Slack 内会話を「Related Conversations」タブに集約表示
- フィールドを編集可能に設定できる（`edit.enabled: true`）
  - 対応入力: テキスト、日付ピッカー、選択メニュー、チェックボックス、数値、メール、URL、タイムピッカー、マルチセレクト
  - `view_submission` ペイロードで編集内容がアプリに送信される
- カスタムエラー画面（`custom_partial_view`）でアクセス制限やカスタムメッセージ表示

TTL: フレックスペインコンテンツは 10 分間キャッシュされる。

---

#### 2-4. AI Answers の引用（Enterprise Search 付随機能）

`work-objects-overview.md` l.89:
> 「To support Work Objects for your app's Enterprise Search results, traditional search results, and AI answers citations, your app must subscribe to the `entity_details_requested` event.」

→ Enterprise Search の文脈で「AI answers の引用」として Work Objects が使われる。これは Enterprise Search に付随する機能だが、Enterprise Search そのものとは別のユーザー体験。

---

#### 2-5. Unified Files Browser（統合ファイルブラウザ）

`work-objects-implementation.md` l.159: 「**Unified file management**: Files are managed through Slack's file system, making them accessible in the unified files browser.」

`work-objects-implementation.md` l.771:
> 「If your app is providing remote files, you'll want to use the same value for the `remote_file.external_id` property and the Work Object's `external_ref.id`. This will allow us to provide the same `external_ref` back to your app in the `entity_details_requested` event triggered by a user opening the flexpane or preview from the files browser.」

→ `File` エンティティタイプと `slack_file` オブジェクトを組み合わせた Work Object は、Slack の統合ファイルブラウザからも開ける（`entity_details_requested` イベントが発火し、フレックスペインが表示される）。

---

#### 2-6. 利用可能なプラットフォーム・サーフェス（`choosing-the-right-surface.md` l.247 より）

```
Work Objects are available in channels, DMs, notifications, canvases,
Salesforce Lightning Experience (LEX) client, and mobile.
```

| サーフェス | 詳細 |
|---|---|
| チャンネル | Link Unfurl 表示、通知メッセージとして投稿 |
| DM | Link Unfurl 表示、通知メッセージとして投稿 |
| 通知 | chat.postMessage による直接投稿 |
| キャンバス（Canvases） | Work Object リンクを埋め込み可能 |
| Salesforce Lightning Experience (LEX) クライアント | Salesforce 側クライアントでも表示可能 |
| モバイル | モバイルアプリでも表示 |

---

### 3. Enterprise Search との関係整理

`enterprise-search/index.md` l.19:
> 「Refer to support for Enterprise Search to learn more about how Work Objects support Enterprise Search features.」

`work-objects-overview.md` の「Support for Enterprise Search」セクション (l.87-93):
> 「To support Work Objects for your app's Enterprise Search results, traditional search results, and AI answers citations, your app must subscribe to the `entity_details_requested` event.」

→ Enterprise Search での利用は Work Objects の利用シーンの一つに過ぎず、Enterprise Search 自体が Work Objects に依存しているというわけではない。

---

### 4. Block Kit vs. Work Objects の使い分け（`choosing-the-right-surface.md` より）

Work Objects が適切なケース:
- **システム・オブ・レコードに対応するもの**: Asana タスク、Box ファイル、Salesforce レコード、Tableau メトリクス、メール、イベントなど
- **共有可能である必要があるもの**: Work Object はリンクを貼るとどこでも一貫したリッチプレビューが再構築される
- **信頼できる情報源（Source of Truth）**: 何日も何週間もデータを参照する必要がある場合
- **高い相互運用性が必要**: Enterprise Search でインデックス化され、関連会話も追跡される

Block Kit が適切なケース:
- システム・オブ・レコードに結びつかない一時的な通知
- カスタムレイアウト制御が必要な場合
- フォームや入力収集（モーダル経由の方が適切な場合も）

比較表（`choosing-the-right-surface.md` の表より）:

| | Work Objects | Block Kit |
|---|---|---|
| 用途 | 永続的なレコード・エンティティ | 通知、カスタムUI |
| アイデンティティ | 永続的なディープリンク | メッセージタイムスタンプに紐付け |
| 共有可能性 | 高い（リンクがどこでも展開） | 元のメッセージに限定 |
| カスタマイズ | 中（スキーマ駆動） | 高（フルレイアウト制御） |
| インタラクティビティ | フレックスペインアクション | ブロックアクション、モーダル、入力 |
| 検索・発見性 | Enterprise Search にインデックス | インデックスされない |
| ストリーミング対応 | 対応（マークダウン・アンファール） | 非対応 |

---

### 5. サポートするエンティティタイプ

| タイプ | `entity_type` | 用途 |
|---|---|---|
| File | `slack#/entities/file` | ドキュメント、スプレッドシート、画像など |
| Task | `slack#/entities/task` | チケット、To-do など |
| Incident | `slack#/entities/incident` | インシデント、サービス停止など |
| Content Item | `slack#/entities/content_item` | コンテンツページ、記事など |
| Item | `slack#/entities/item` | 汎用（`custom_fields` のみ使用） |

---

### 6. Slack Marketplace への提出条件

`work-objects-overview.md` l.96-100:
- 既にリンクアンファール機能を持つアプリで必要なスコープを持っている場合、ワークスペースの再認証は不要
- Work Objects は新しいイベントサブスクリプションを必要とするため、新たな Slack Marketplace 提出が必要
- `external_ref` の形式・ID は変更不可（関連会話トラッキングに使用されるため）
- 複数のアプリから同じ Work Object を送信して「Related Conversations」タブに表示したい場合は、Slack Marketplace チームへの連絡が必要

---

## 問題・疑問点

- Salesforce LEX クライアントでの Work Object 表示の具体的な仕組みは本ドキュメント内では詳述されていない
- キャンバスへの Work Object 埋め込みの具体的な実装方法は本ドキュメントでは確認できなかった（別途 Canvases ドキュメントの確認が必要）
- 「AI answers citations」が Enterprise Search 以外の文脈でも機能するかは不明（ドキュメント上の記述では Enterprise Search と合わせて言及されている）
