# Enterprise Search User Report 詳細

## 知りたいこと

Enterprise SearchのUser Reportの詳細

## 目的

User Reportで何ができるのか、何を実装しないといけないのかを詳しく知りたい。特に接続と切断で何を実装しないといけないかを知りたい。

## 調査サマリー

**User Report（Connection Reporting）は Enterprise Search アプリがユーザーごとの「外部データソースへの認証状態」を Slack に報告する機能。Slack が Connect/Disconnect の UI を管理し、アプリは実際の OAuth フローとトークン管理を担当する。**

### 機能の本質

- **Push モデル**: アプリが `apps.user.connection.update` を呼んで Slack に状態を報告する（Slack がトークン存在を確認するわけではない）
- **オプション機能**: Enterprise Search のコア機能（検索結果の返却）とは独立
- **UI の委譲**: Slack が Connect/Connected/Disconnect ボタンを管理する

### 接続（Connect）フローで実装が必要なもの

1. `user_connection` イベント（subtype: connect）のハンドラ
2. `event.trigger_id` を使って `views.open` でモーダルを開く（OAuth URL表示）
3. OAuth callback エンドポイント（外部サービスからの認可コード受け取り）
4. トークン交換と自社 DB への保存（キー: Slack user_id）
5. `apps.user.connection.update(user_id, status: "connected")` の呼び出し

### 切断（Disconnect）フローで実装が必要なもの

1. `user_connection` イベント（subtype: disconnect）のハンドラ（`trigger_id` なし、モーダル不要）
2. 自社 DB からのトークン削除
3. `apps.user.connection.update(user_id, status: "disconnected")` の呼び出し

### 必要なスコープ

- `users:write`（`user_connection` イベント受信 + `apps.user.connection.update` 呼び出し）

### その他

- 初期状態は「disconnected」が設計の出発点（機能の失敗ではない）
- `apps.user.connection.update` のドキュメントは User token のみ記載だが、Bot token でも動作すると推定（Bolt SDK がデフォルトで Bot token を使用）

## 完了サマリー

- **調査日**: 2026-04-20
- **ログファイル**: `logs/0042_enterprise-search-user-report-details.md`
- **結論**: User Report（Connection Reporting）の詳細を確認した。接続フローと切断フローそれぞれで必要な実装を整理した。接続フローでは `trigger_id` を使ったモーダル表示と OAuth フローの実装が必要で、切断フローではトークン削除のみ（モーダル不要）。
