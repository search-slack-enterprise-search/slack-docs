# Slack 外部認証

## 知りたいこと

Slackの外部認証について

## 目的

どういった機能なのか、どうやって使うのか、どうやって実装するのかを知りたい

## 調査サマリー

### 外部認証とは
Slack の外部認証（External Authentication）は、**OAuth2** を使ってワークフローアプリが Google Sheets・GitHub・Salesforce などの外部サービスに安全にアクセスするための仕組み。パスワードではなくアクセストークンで認証する。

**前提条件**: 有料プラン + Deno Slack SDK + Slack CLI が必要（ワークフローアプリ専用機能）。

### 実装フロー（全9ステップ）

1. **OAuth2 認証情報の取得**: 外部サービスでクライアントID・シークレットを取得。リダイレクトURLは `https://oauth2.slack.com/external/auth/callback`
2. **OAuth2 プロバイダーの定義**: `manifest.ts` に `DefineOAuth2Provider()` でプロバイダーを定義
3. **マニフェストへの追加**: `externalAuthProviders: [GoogleProvider]` を追加
4. **クライアントシークレットの保存**: `slack deploy` 後に `slack external-auth add-secret --provider google --secret "..."` で暗号化保存
5. **OAuth2 フロー初期化**: `slack external-auth add` でブラウザ経由でログイン・トークン作成
6. **カスタム関数への統合**: 入力パラメータに `type: Schema.slack.types.oauth2` を定義し、関数内で `client.apps.auth.external.get({ external_token_id })` でトークン取得
7. **ワークフローでの認証設定**: `credential_source: "END_USER"` か `"DEVELOPER"` を指定。DEVELOPER の場合は `slack external-auth select-auth` でアカウント選択が必要
8. **強制リフレッシュ**: `apps.auth.external.get` に `force_refresh: true` を渡す
9. **トークン削除**: `client.apps.auth.external.delete({ external_token_id })` で削除（プロバイダー側では無効化されない）

### CLIコマンド一覧

| コマンド | 用途 |
|---|---|
| `slack external-auth add` | OAuth2フロー開始・トークン作成 |
| `slack external-auth add-secret` | クライアントシークレットの保存 |
| `slack external-auth select-auth` | ワークフローに使う開発者アカウントを選択 |
| `slack external-auth remove` | 保存済みトークンの削除 |

### Web API

| API | 説明 |
|---|---|
| `apps.auth.external.get` | トークンIDから外部サービスのアクセストークンを取得 |
| `apps.auth.external.delete` | Slack側でトークンを削除 |

### 重要な注意点
- `slack external-auth remove` / `apps.auth.external.delete` はSlack側の参照を削除するだけ。プロバイダー側での無効化は別途必要
- `END_USER` 認証はリンクトリガーでのみ動作
- 複数コラボレーターは各自でアカウントを設定する必要あり（代理設定不可）
- ログ確認は `slack activity` コマンドで行う

## 完了サマリー

- **調査日**: 2026-04-16
- **調査ファイル数**: 9ファイル
- **詳細ログ**: `logs/0004_slack-external-auth.md`
- **結論**: Slack 外部認証は Deno SDK ワークフローアプリ専用の OAuth2 統合機能。9ステップの実装フローが明確に定義されており、CLI コマンドと Web API の両方で操作可能。
