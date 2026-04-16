# Work Object Preview の詳細

## 知りたいこと

Work Object Previewとは何かを具体的に知ること

## 目的

Work Object Previewとは何かを具体的に知ることで、使うべき時は何なのか、使わない方が良いときは何なのかを知りたい。

## 調査サマリー

### Work Object Preview とは

「Work Object Previews」とはアプリ設定のサイドバーメニュー名であり、Work Objects 機能を有効化してエンティティタイプを選択する設定画面のこと。機能自体は「Work Objects」と呼ばれる。

**Work Objects** = リンクアンファーリングを進化させた体験で、外部サービスのデータをリッチに表現する仕組み。2025年10月22日に GA。2つのコンポーネントを持つ：

#### 1. Unfurl コンポーネント
- URL を貼ると会話内に自動表示されるリッチカード
- **会話参加者全員に見える** → 機密情報は含めない
- `chat.unfurl` API の `metadata` パラメータで実装
- エンティティタイプ: File / Task / Incident / Content Item / Item（汎用）

#### 2. Flexpane コンポーネント
- unfurl クリックで Slack 右側に開く詳細ビュー
- **ユーザーごとの個別情報を表示できる**（per-user）
- **認証を要求できる** → 機密情報はこちらに表示可能
- `entity_details_requested` イベント + `entity.presentDetails` API で実装
- 関連会話（Related Conversations）の集約、フィールド編集、アクションボタンも配置可能

#### Enterprise Search との関係
- Enterprise Search の検索結果・AI 回答の引用にも Work Objects を適用可能
- アプリ設定 Work Object Previews でエンティティタイプを定義し、`entity_details_requested` を購読するだけ
- Enterprise Search から開いた場合は `channel`・`message_ts` がイベントに含まれない点に注意

### 使うべき時
1. 外部サービス（GitHub, Jira, Confluence等）のリンクをリッチ表示したい時
2. Slack を離れずに外部データを確認・編集・操作したい時
3. 機密情報を認証付きフレックスペインに出し分けたい時
4. Enterprise Search の検索結果をクリック時にリッチな詳細を表示したい時
5. 外部データのリアルタイム更新をユーザーに届けたい時

### 使わない方が良い時
1. 機密情報が unfurl（会話全員に見える）に露出する可能性がある時
2. Enterprise Search アプリを Slack Marketplace に公開しようとしている時（不可）
3. 静的な情報だけ表示する場合（通常の link unfurling で十分）
4. `external_ref` の ID が変更される仕組みの場合（Related Conversations が壊れる）

### 詳細ログ
`logs/0019_work-object-preview-details.md` を参照。

## 完了サマリー

- 調査日: 2026-04-16
- 主要調査ファイル: `docs/messaging/work-objects-overview.md`、`docs/messaging/work-objects-implementation.md`、`docs/reference/events/entity_details_requested.md`、`docs/reference/methods/entity.presentDetails.md`
- Work Object Preview の正体: アプリ設定の **Work Object Previews** メニューで有効化する機能。Unfurl（全員に見えるリッチカード）+ Flexpane（per-user の詳細ビュー）の2コンポーネント構成。Enterprise Search の検索結果にも対応。
- 使うべき時: 外部サービスリンクのリッチ化・per-user 認証付き詳細表示・Enterprise Search の結果強化。
- 使わない方が良い時: 機密情報が unfurl に漏れる、`external_ref` が変わる、Marketplace 公開を目指す Enterprise Search アプリ。
