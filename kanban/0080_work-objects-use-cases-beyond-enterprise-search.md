# Work Objects の Enterprise Search 以外での利用用途

## 知りたいこと

Work ObjectsはEnterprise Search以外では何で使用することができるのか

## 目的

Work Objectsを何で使えるのかを知って、現在考案中のアプリの設計の参考にしたい

## 調査サマリー

### Enterprise Search 以外での主な利用用途

1. **リンクアンファール（Link Unfurl）**
   - チャンネル・DM・スレッドでURLを貼るとリッチプレビューが表示される
   - `link_shared` イベント → `chat.unfurl` API（`metadata` パラメータ）
   - ユーザーホバー時のリフレッシュボタン、フレックスペイン操作後の自動リフレッシュも対応

2. **通知としての直接投稿（chat.postMessage）**
   - `chat.postMessage` の `metadata`（または `eventAndEntityMetadata`）パラメータで Work Object エンティティを直接投稿可能
   - リンクアンファール不要でメッセージとして Work Object を送れる
   - ただし「一時的な通知」には不向き。永続的なレコードに限るべきとドキュメントに明記

3. **フレックスペイン（Flexpane）**
   - Work Object クリック時に Slack 右側に開くサイドパネル
   - ユーザー認証要求、詳細情報表示、フィールド編集、関連会話一覧（Related Conversations）を提供
   - Enterprise Search とは独立して利用可能

4. **Unified Files Browser（統合ファイルブラウザ）**
   - `File` エンティティタイプと `slack_file` の組み合わせで、Slack のファイルブラウザから Work Object を開ける
   - `entity_details_requested` イベントが発火してフレックスペインが表示される

5. **AI Answers の引用**
   - Enterprise Search に関連するが、AI 回答の引用として Work Objects が使われる

### 利用可能なプラットフォーム・サーフェス

`choosing-the-right-surface.md` に明記:
> Work Objects are available in channels, DMs, notifications, canvases, Salesforce Lightning Experience (LEX) client, and mobile.

| サーフェス | 詳細 |
|---|---|
| チャンネル・DM | Link Unfurl、直接投稿 |
| 通知 | chat.postMessage による投稿 |
| キャンバス（Canvases） | Work Object リンクの埋め込み |
| Salesforce LEX クライアント | Salesforce 側でも表示 |
| モバイル | モバイルアプリでも表示 |

### Block Kit との使い分け

- Work Objects は「外部システムの永続的なレコード（Asana タスク、Box ファイル、Salesforce レコード等）」を表す場合に使用
- Block Kit は一時的な通知やカスタムレイアウトが必要な場合
- Work Objects は Enterprise Search でインデックス化されるが Block Kit はされない
- Work Objects はリンクを貼ればどこでも再現できる永続的なディープリンク

### サポートエンティティタイプ

File / Task / Incident / Content Item / Item（汎用）

### 設計上の注意

- 一時的なアラートには Work Objects を使わない（Block Kit が適切）
- `external_ref` の ID・形式は一度決めたら変更不可（関連会話トラッキングに使用）
- Marketplace 提出アプリは新規提出が必要（新イベントサブスクリプションが必要なため）

## 完了サマリー

Work Objects は Enterprise Search に限らず、以下の用途で利用できることを確認した:
- チャンネル・DM でのリンクアンファール
- chat.postMessage による直接投稿（通知）
- フレックスペイン（詳細表示・編集・関連会話）
- 統合ファイルブラウザとの統合（File エンティティタイプ）
- キャンバス、Salesforce LEX、モバイルでの表示

Enterprise Search は Work Objects の利用シーンの一つに過ぎず、Work Objects 自体は「外部システムの永続的なレコード」を Slack 内で表現する汎用的な仕組みである。アプリ設計上は「外部システムのレコードを Slack 内で共有・閲覧・編集したい」ケースで広く活用できる。
