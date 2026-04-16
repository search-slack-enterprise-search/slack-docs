# Enterprise Search と外部認証機能の組み合わせ実装方法

## 知りたいこと

Enterprise Search と外部認証機能をどうやって組み合わせたら良いのか

## 目的

Enterprise Search の user report 機能の存在から明らかに外部認証機能を使って外部への検索時に認可を効かせることを想定しています。どのように実装したら良いかがわからない。

## 調査サマリー

### 基本方針

Enterprise Search（`function_runtime: "remote"` の Bolt アプリ）では、Deno SDK の `credential_source: "END_USER"` / `oauth2` 型パラメータは使えない（Link Trigger 専用のため）。代わりに **Connection Reporting** + **アプリ独自の OAuth トークン管理** の組み合わせが公式ドキュメントで想定されているアプローチ。

### 3つのフェーズで構成される統合パターン

#### フェーズ1: 接続フロー

1. ユーザーが検索 UI の「Connect」ボタンをクリック
2. Slack → アプリ: `user_connection` イベント（`subtype: connect`）が発火
   - `event.user` = Slack user_id
   - `event.trigger_id` = モーダルを開く用
3. アプリ → Slack: `views.open` でモーダルを表示（OAuth 認可 URL を案内）
4. ユーザーが外部サービスで認証完了
5. アプリが OAuth callback を受け取り、アクセストークンを自社 DB に保存（キー: Slack user_id）
6. アプリ → Slack: `apps.user.connection.update` (`user_id`, `status: "connected"`)
7. 検索 UI が「Connected」に更新

#### フェーズ2: 切断フロー

1. `user_connection` イベント（`subtype: disconnect`）が発火
2. アプリ: DB からトークン削除
3. アプリ → Slack: `apps.user.connection.update` (`user_id`, `status: "disconnected"`)

#### フェーズ3: 検索フロー

1. `function_executed` イベント（search_function）が発火
   - `inputs.user_context.id` = 検索ユーザーの Slack user_id
2. アプリ: `user_context.id` で DB からトークン取得
3. トークンなし → `functions.completeError` で認証要求メッセージを返す
   - Slack 公式例: `"Authentication Required: Please visit https://... to authenticate your account."`
4. トークンあり → 外部 API を `Bearer {token}` で呼び出し → `functions.completeSuccess` で結果返却

### 重要な設計ポイント

| 観点 | 内容 |
|---|---|
| Slack が管理するもの | 「Connect」/「Connected」の UI 表示のみ |
| アプリが管理するもの | OAuth フロー、トークンの保存・取得・リフレッシュ・削除すべて |
| 必要なスコープ | `users:write`（`apps.user.connection.update` の呼び出しに必要） |
| Manifest 設定 | `bot_events` に `user_connection` を追加、`features.search` に callback_id を設定 |

### 調査で確認できなかった点

- search_function で `oauth2` 型パラメータが使えるか（記載がないだけで不可とは断言できない）
- モーダルで OAuth 完了後に自動クローズする具体的な実装パターン
- Bolt サンプルテンプレートの実際のコード（GitHub 上に存在するが調査対象外）

## 完了サマリー

- **調査日**: 2026-04-16
- **ログファイル**: `logs/0009_enterprise-search-external-auth-integration.md`
- **結論**: Enterprise Search + 外部認証は Connection Reporting（`user_connection` イベント + `apps.user.connection.update`）と アプリ独自の OAuth トークン管理（DB 保存 + `user_context.id` によるルックアップ）を組み合わせて実装する。Slack が提供するのは UI の「接続状態」管理のみ。
