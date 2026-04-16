# Enterprise Search 外部サービス認証の実装方法

## 知りたいこと

Enterprise Searchにおいて、外部サービスに認証を行う場合、どういう実装をしなければならないですか？

## 目的

user_reportにおいてSlackの外部認証機能を使っていないことはわかった。
ということはEnterprise Search内で認証を行っているということになる。
その認証のやり方を知りたい。

## 調査サマリー

Enterprise Search で外部サービスへの認証を実装するには、**Connection Reporting + アプリ独自の OAuth フロー + 自社トークンストア**の組み合わせが必要。

### 実装の3フェーズ

**フェーズ 1: 接続フロー**
1. ユーザーが「Connect」ボタンをクリック
2. Slack → アプリ: `user_connection` イベント（`subtype: connect`, `trigger_id`）
3. アプリ: `views.open` でモーダルを表示 → 外部サービスの OAuth 認可 URL を案内
4. ユーザーが外部サービスで OAuth を完了
5. アプリの OAuth callback エンドポイント: 認可コード → アクセストークンに交換 → **自社 DB に保存**（キー: Slack user_id）
6. アプリ → Slack: `apps.user.connection.update(status: "connected")`

**フェーズ 2: 切断フロー**
1. ユーザーが「Disconnect」をクリック
2. `user_connection` イベント（`subtype: disconnect`）
3. アプリ: DB からトークン削除 → `apps.user.connection.update(status: "disconnected")`

**フェーズ 3: 検索フロー**
1. `function_executed` イベントで `user_context.id` を受け取る
2. DB からトークンを取得
3. トークンなし → `functions.completeError`（認証要求メッセージ表示）
4. トークンあり → 外部 API 呼び出し → `functions.completeSuccess`（10秒以内に完了必須）

### 重要な区別

- **Slack が提供するもの**: Connect ボタン UI・`user_connection` イベント・`apps.user.connection.update` API・`functions.completeError` でのメッセージ表示
- **アプリが実装するもの**: OAuth 認可 URL 生成・callback エンドポイント・トークン交換・DB 保存・トークンリフレッシュ
- **Deno SDK External Auth は使用不可**（Link Trigger 専用であり Enterprise Search の search_function には適用できない）

### 参照ログ

`logs/0016_enterprise-search-external-auth-implementation.md`

## 完了サマリー

- **調査日**: 2026-04-16
- **結論**: Enterprise Search での外部認証は「Connection Reporting（UI/イベント）+ アプリ独自の OAuth フロー + 自社 DB によるトークン管理」の三位一体で構成される。Slack が提供するのは Connect ボタンの UI と `user_connection` イベントのみ。OAuth の本体実装はすべてアプリの責任。
- **詳細**: `logs/0016_enterprise-search-external-auth-implementation.md`
