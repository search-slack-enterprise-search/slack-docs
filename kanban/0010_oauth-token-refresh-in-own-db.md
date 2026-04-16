# 自社 DB の OAuth トークン更新方法

## 知りたいこと

OAuthトークンを自社のDBに保存する運用ということだが、OAuthトークンを更新した時に自社DBのトークンを更新できるのか

## 目的

自社のDBに保存しているということはSlackが保存しているOAuthトークンが更新された際に自社DBに保存しているトークンも更新する必要がある。
その手段を知りたい。

## 調査サマリー

### 重要：前提の訂正

**「Slackが保存しているOAuthトークンが更新される」という前提は誤り**。

Enterprise Search + Connection Reporting と Deno SDK External Auth では、トークンストアが1つしか存在しない：

| アプローチ | トークンを管理するのは誰か |
|---|---|
| Enterprise Search + Connection Reporting（Bolt） | **アプリ独自 DB のみ**（Slack はトークンを持たない） |
| Deno SDK External Auth | **Slack のみ**（アプリは DB を持たない） |

2つのストアが共存して同期が必要なシナリオは存在しない。

### Enterprise Search + Connection Reporting での対応

Slack は外部 OAuth トークンを管理しない。アプリが独自に標準 OAuth2 リフレッシュフローを実装する：

1. **DB に保存する情報**: `access_token`・`refresh_token`・`expires_at`（UNIX 時刻）
2. **リフレッシュ方法**: 外部サービスの token endpoint に `grant_type=refresh_token` で POST し、新しいトークンで DB を更新
3. **リフレッシュ失敗時**: `apps.user.connection.update(status: "disconnected")` + `functions.completeError` でユーザーに再接続を促す

### 10秒制約への対応

search_function は 10 秒以内に完了が必要（`developing-apps-with-search-features.md` 行 307）。リアクティブリフレッシュ（検索中にトークン切れ検知）は時間的に危険なため、**バックグラウンドジョブでのプロアクティブリフレッシュ**（有効期限前に更新）を推奨。

### Slack からの失効通知は存在しない

`tokens_revoked` イベントは Slack の bot/user トークン（`xoxb-`/`xoxp-`）専用。外部サービスの OAuth トークン失効・期限切れに対するイベントは Slack から発火しない。

## 完了サマリー

- **調査日**: 2026-04-16
- **ログファイル**: `logs/0010_oauth-token-refresh-in-own-db.md`
- **結論**: Enterprise Search では Slack が外部 OAuth トークンを管理することはない。アプリが独自 DB でトークンを管理し、標準 OAuth2 リフレッシュトークンフローで更新する。Slack からのトークン更新通知は存在しないため、バックグラウンドジョブでのプロアクティブリフレッシュが推奨。
