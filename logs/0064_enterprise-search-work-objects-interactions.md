# Enterprise Search と Work Objects・Interactions の組み合わせでできること

## 調査情報

- タスクファイル: `kanban/0064_enterprise-search-work-objects-interactions.md`
- 調査日: 2026-05-07
- 調査者: Claude Code (kanban スキル)

## 調査ファイル一覧

- `docs/enterprise-search/index.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/connection-reporting.md`
- `docs/enterprise-search/enterprise-search-access-control.md`
- `docs/messaging/work-objects-overview.md`
- `docs/messaging/work-objects-implementation.md`
- `docs/interactivity/index.md`
- `docs/interactivity/handling-user-interaction.md`
- `docs/reference/events/entity_details_requested.md`
- `docs/reference/methods/entity.presentdetails.md`
- `docs/reference/interaction-payloads/view-interactions-payload.md`
- `docs/changelog/2025/10/22/work-objects.md`

## 調査アプローチ

1. Enterprise Search ドキュメント全体を確認し、Work Objects への言及を特定
2. Work Objects ドキュメントの Enterprise Search セクション (`#enterprise-search`) を重点調査
3. Work Objects 実装ドキュメントでインタラクション要素（アクションボタン、編集、認証）を調査
4. Interactions 関連ドキュメントで `block_actions`, `view_submission` 等のペイロードを確認
5. `entity_details_requested` イベントと `entity.presentDetails` API メソッドのリファレンスを確認

---

## 調査結果

### 1. Enterprise Search と Work Objects の関係

#### docs/enterprise-search/index.md より

Enterprise Search の Overview ページ末尾に以下の記述あり（line 19）:

```
➡️ Refer to support for Enterprise Search to learn more about how Work Objects support Enterprise Search features.
(→ /messaging/work-objects-overview#enterprise-search)
```

Enterprise Search アプリが Work Objects を活用するためのリンクが明示されている。

#### docs/enterprise-search/developing-apps-with-search-features.md より

**`external_ref` オブジェクトの重要な記述**（line 162-163）:

```
`id` (Required): A unique identifier for referencing within the search results. 
If your app implements Work Objects, this should be same value used for that implementation.
```

→ **Enterprise Search の検索結果 `external_ref.id` と Work Objects の `external_ref.id` は同じ値を使う必要がある**。これが2つの機能を結びつけるキーとなる。

**`entity_details_requested` イベントの購読が必要**（line 44-47）:

```json
"settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
        "bot_events": [
            "function_executed",
            "entity_details_requested"
        ]
    }
}
```

Enterprise Search アプリは `function_executed` に加えて `entity_details_requested` を購読する必要がある。

**Work Objects サポートセクション**（line 357-359）:

```
## Work Objects support
Refer to support for Enterprise Search for more details.
```

---

### 2. Work Objects による Enterprise Search サポート

#### docs/messaging/work-objects-overview.md の `#enterprise-search` セクション（line 87-93）

```
To support Work Objects for your app's Enterprise Search results, traditional search results, 
and AI answers citations, your app must subscribe to the `entity_details_requested` event. 
You can define the type of Work Objects for your search results, such as an item, within 
the Work Object Previews view within app settings.

Once your app is subscribed to the `entity_details_requested` event, it can respond to the 
event and call the `entity.presentDetails` API method with Work Object metadata to launch 
the flexpane experience.
```

**3つのシナリオで Work Objects が機能する**:
1. Enterprise Search 結果（新機能）
2. 従来の検索結果（traditional search results）
3. AI アンサーの引用（AI answers citations）

---

### 3. Work Objects の2つのコンポーネント

#### docs/messaging/work-objects-overview.md（line 9-29）

**Unfurl コンポーネント**:
- リンクがアンフォールドされた際に表示されるカード形式のプレビュー
- チャンネル内の全員に見える
- Entity タイプ（Task, File, Incident, Content Item, Item）ごとにカスタマイズ可能

**Flexpane コンポーネント**:
- Unfurl をクリックすると Slack 右側に表示されるパネル
- よりリッチなコンテキスト情報・カスタマイズオプションを提供
- **オプションで第三者サービスへの認証を要求できる**（センシティブ情報に対応）
- **Related Conversations（関連会話）タブ**: この Work Object が参照された全 Slack 会話を集約して表示

---

### 4. Interactions（インタラクション）の種類と動作

#### 4a. Block Kit アクションボタン (docs/messaging/work-objects-implementation.md, line 606-728)

Work Objects の unfurl カードと flexpane の両方に**アクションボタンを追加可能**。

- **Primary actions**: 最大2つ（unfurl フッター・flexpane フッターに表示）
- **Overflow actions**: 最大5つ（「More actions」オーバーフローメニューに表示）

デフォルトでオーバーフローメニューに追加されるアクション:
- Share [Object]（例: Share Issue）
- Copy link to [Object]（例: Copy link to Issue）
- Add to To-do
- View in App

アクション定義の例（entity_payload の `actions` フィールド）:

```json
{
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
        "action_id": "github_wo_button_pin_issue"
      },
      {
        "text": "Assign to me",
        "action_id": "github_wo_button_assign_issue"
      }
    ]
  }
}
```

ボタンが押されると `block_actions` ペイロードがアプリに送信される。

**重要なペイロードの差異**（line 715）:
- unfurl 上のアクション → `container.type: "message_attachment"`
- flexpane 上のアクション → `container.type: "entity_detail"`

`container` に含まれる Work Object 固有プロパティ: `entity_url`, `external_ref`, `app_unfurl_url`, `message_ts`, `thread_ts`, `channel_id`

#### 4b. アクション後の応答方法（line 717-728）

ボタンクリック後のアプリの応答方法:
1. **認証が必要な場合**: `entity.presentDetails` に `user_auth_required=true` と `user_auth_url` を設定 → flexpane が自動で開き認証フローへ
2. **モーダルを開く**: `trigger_id` を使って `/views.open` でモーダルを開き、追加情報を収集
3. **スレッドにメッセージ投稿**: unfurl メッセージがあるスレッドにメッセージを投稿
4. **DM を送信**: アクションが失敗した場合、ユーザーの DM に送信
5. **unfurl を更新**: 成功時に `chat.unfurl` API を呼び出して新しい `metadata` を渡し unfurl を更新
6. **flexpane を更新**: 成功時に `entity.presentDetails` API を呼び出して新しい `metadata` を渡し flexpane を更新

#### 4c. フィールド編集 (line 224-604)

Work Object flexpane 内でユーザーが**フィールドを直接編集**できる機能。

- `entity_payload.fields` の各フィールドに `"edit": {"enabled": true}` を追加するだけで編集可能になる
- フィールドの型に合わせた Block Kit 入力要素に自動マッピングされる
  - 日付フィールド → Date picker
  - ユーザーフィールド → Users select
  - 文字列フィールド → Plain-text input
  - 日時フィールド → Datetime picker
  - ブール値フィールド → Checkbox / Radio / Select

ユーザーが **Save** をクリックすると `view_submission` ペイロードが送信される。このペイロードには:
- `view.type: "entity_detail"`（Work Object 専用のタイプ）
- `view.state.values`（更新されたフィールド値）
- `view.external_ref`（編集された Work Object の ID）
- `view.entity_url`（外部システムでのエンティティ URL）
- `trigger_id`（`entity.presentDetails` で flexpane を更新するために使用）

編集バリデーションの3レベル:
1. **クライアントサイドのフィールドレベルバリデーション**: `edit` プロパティで設定（max_length 等）。フォーム送信前に Slack 側でチェック
2. **サーバーサイドのフィールドレベルバリデーション**: `view_submission` への応答で `{"response_action": "errors", "errors": {...}}` を返す（3秒以内に応答が必要）
3. **サーバーサイドのフォームレベルバリデーション**: `entity.presentDetails` API に `edit_error` ステータスを渡す

#### 4d. Dynamic External Select (line 548-561)

`edit.select.fetch_options_dynamically: true` を設定すると、ユーザーが入力するたびに `block_suggestion` リクエストがアプリに送信され、動的にセレクトオプションを提供できる。

```json
{
  "type": "block_suggestions",
  "block_id": "assignee",
  "action_id": "assignee.input",
  "value": "jo"
}
```

応答例:
```json
{
  "options": [
    {"text": {"type": "plain_text", "text": "joe.bob@example.com"}, "value": "U123"},
    {"text": {"type": "plain_text", "text": "joan.rivers@example.com"}, "value": "U456"}
  ]
}
```

#### 4e. 認証フロー / Connection Reporting (docs/enterprise-search/connection-reporting.md)

ユーザーが未認証の場合:
- `entity.presentDetails` API に `user_auth_required=true` と `user_auth_url` を設定
- flexpane が自動で開き、認証を促す UI が表示される

Connection Reporting（Enterprise Search との統合）:
- `user_connection` イベントを購読（`subtype: connect` または `subtype: disconnect`）
- 接続時: イベント内の `trigger_id` を使ってモーダルを開き認証情報を収集
- 認証完了後: `apps.user.connection.update` API でステータスを Slack に報告

---

### 5. Flexpane の自動更新

#### docs/messaging/work-objects-implementation.md（line 59-72）

**Flexpane インタラクション後の自動更新**:
- フレクスペインで操作があると、unfurl も自動更新される
- ブロックアクションクリック後は自動的にリフレッシュがスケジュールされる

**TTL と更新タイミング** (line 1259-1283):
- 最初に flexpane を開いた時: 即座に `entity_details_requested` イベント送信
- TTL: 10分
- TTL 経過後に2回目以降の flexpane 操作 → イベント再送信
- 手動リフレッシュボタン: 常に即座にイベント送信
- TTL 未満でも「更新なし」の間は再送信しない（ユーザーがタブを切り替えたり flexpane を開閉しても）

---

### 6. エンティティ参照（Work Objects 間のリレーション）

#### docs/messaging/work-objects-implementation.md（line 979-981）

`slack#/types/entity_ref` 型を使うと、**同一アプリ内の複数 Work Object エンティティ間のリレーションを表現**できる。

例: タスクエンティティに複数のサブタスクがある場合、各サブタスクを `entity_ref` 型フィールドで関連付けることができる。

---

### 7. Related Conversations（関連会話）追跡

`external_ref.id` は Related Conversations のトラッキングに使われる（work-objects-overview.md, line 98）:

```
The `external_ref` format or IDs must not change for a given Work Object, as it is used 
for related conversations tracking. Slack scopes related conversations to the app sending 
the entity, so if you have multiple apps sending the same Work Object that you'd like to 
appear in the Related Conversations tab, then please let the Slack Marketplace team know.
```

→ `external_ref.id` を変更すると Related Conversations が壊れる。Enterprise Search の `external_ref.id` と Work Objects の `external_ref.id` を一致させることで、検索結果とチャンネルでの会話が紐付けられる。

---

### 8. SDK サポート状況

#### docs/messaging/work-objects-overview.md（line 31-35）

- **Bolt for JavaScript**: サポート済み
- **Bolt for Java**: サポート済み
- **Bolt for Python**: Coming soon（現時点では限定的）

---

## 総合まとめ: 3つを組み合わせることで実現できること

### シナリオ A: 検索 → リッチプレビュー → アクション

1. ユーザーが Slack で検索 → Enterprise Search アプリが外部システムの検索結果を返す
2. 検索結果の1件をクリック → Work Object の flexpane が開く（リッチな詳細情報が表示）
3. flexpane 内のアクションボタンを押す（例: "Close issue", "Assign to me"）→ `block_actions` ペイロードをアプリが受け取り、外部システムを更新
4. アプリが `entity.presentDetails` を呼び出して flexpane を最新状態に更新

### シナリオ B: 検索 → フィールド編集

1. ユーザーが Slack で検索 → Enterprise Search 結果から対象アイテムを見つける
2. 検索結果の flexpane を開く → 鉛筆アイコンをクリックして編集モードに入る
3. 担当者・ステータス・期日などのフィールドを直接 Slack 内で編集
4. Save ボタンを押す → `view_submission` (type: `entity_detail`) がアプリに送信
5. アプリが外部システムを更新 → `entity.presentDetails` で flexpane を更新

### シナリオ C: 検索 → 認証 → 詳細表示

1. 未認証ユーザーが Slack で検索 → 検索結果には基本情報のみ表示
2. 結果をクリックして flexpane を開こうとする → アプリが `user_auth_required=true` で返す
3. flexpane に認証ボタンが表示 → ユーザーが認証 URL にアクセスして認証
4. 認証完了後、再度クリックするとフルの flexpane が表示される

### シナリオ D: AI アンサー + Work Object引用

1. ユーザーが自然言語で Slack を検索（AI アンサー機能）
2. Enterprise Search が `description`・`content` フィールドに詳細テキストを含む検索結果を返す
3. Slack の AI がそれらを使って自然言語で回答を生成
4. 回答内の引用アイテムをクリックすると Work Object の flexpane が開く

### シナリオ E: 関連会話の活用

1. 外部システムの同じアイテム（同じ `external_ref.id`）が複数の Slack チャンネルで共有された
2. ユーザーが検索または unfurl からそのアイテムの flexpane を開く
3. flexpane の "Related Conversations" タブで、そのアイテムが参照された全会話を確認できる

---

## 制約・注意点

1. **Enterprise Search アプリは Slack Marketplace 公開不可**: 組織内利用のみ
2. **org-ready（オーグ対応）が必須**: `org_deploy_enabled: true` が必要
3. **`external_ref.id` は一貫性が必要**: 変更すると Related Conversations が壊れる。Enterprise Search と Work Objects で同じ値を使う
4. **Bolt for Python は Work Objects の SDK サポートが限定的**: "Coming soon" 状態
5. **`entity_details_requested` イベントの注意点**: Enterprise Search 結果から開いた場合、`channel`, `message_ts`, `thread_ts` フィールドは提供されない。`external_ref` も保証されない（Slack 開発のサーチプロバイダーから開いた場合）
6. **フレクスペインの TTL**: 10分。頻繁な更新が必要な場合はユーザーに手動リフレッシュを促すか、`metadata_last_modified` を活用
7. **同期処理が必須**: `function_executed` イベント（検索関数）は10秒以内に処理して応答する必要がある
8. **アクションのアプリ認証エラー**: 非認証エラーの場合 flexpane は自動で開かない。ユーザーへの DM 送信が推奨

---

## 調査中の疑問・未解決事項

1. Enterprise Search 結果から flexpane を開いた際に `external_ref` が「保証されない」とドキュメントに記載があるが、その具体的なケースは不明。Slack 開発のサーチプロバイダー限定の問題か?
2. Work Objects の Bolt for Python サポートが "Coming soon" 状態だが、現時点での制限の詳細が不明
3. Enterprise Search + Work Objects の組み合わせでサポートされるエンティティタイプに制限があるかどうか（ドキュメントは全タイプが使えるように読めるが、明示的な記載なし）
