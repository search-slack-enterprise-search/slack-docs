# Slack外部認証 UIからの認証フロー確認

## 知りたいこと

Slackの外部認証機能はプロバイダーを設定すればSlack上から認証を通すことができるのか？

## 目的

前回の調査結果ではSlack CLIを使って認証を行っていた。しかし実運用ではSlack上から認証を通せないのなら実用性が低い。数百名もSlack CLIでやるのは現実でないし、CLI操作に不慣れな人もいる。

---

## 調査サマリー

**結論: `credential_source: "END_USER"` を使えば、エンドユーザーは CLI 不要で Slack UI から外部認証を完了できる。**

### 2つの credential_source モード

| モード | 認証者 | CLI 必要か | トリガー制約 |
|---|---|---|---|
| `END_USER` | ワークフロー実行ユーザー本人 | **不要**（エンドユーザーは CLI 不要） | Link Trigger のみ |
| `DEVELOPER` | 開発者/コラボレーター | **必要**（`slack external-auth add` + `select-auth`） | 制約なし |

### END_USER モードのフロー

1. 開発者が `credential_source: "END_USER"` でワークフローを実装・デプロイ
2. Link Trigger のショートカットリンクを Slack チャンネルに投稿
3. ユーザーがそのリンクをクリック → **Slack が外部サービスへの認証を要求**
4. ユーザーはブラウザが開き OAuth2 フロー（例: Google サインイン）を完了
5. `oauth2.slack.com` で「アカウントが接続されました」と確認
6. Slack がトークンを保存し、ワークフローが実行される
7. 2回目以降はトークンが保存済みのため認証不要

### 重要な制約

- **Link Trigger 専用**: Link Trigger（`https://slack.com/shortcuts/...`）からのみ動作。スケジュール・Webhook・イベントトリガーでは END_USER 認証は使えない
- **有料プラン必須**: ワークフローアプリは有料プランが必要
- **Deno Slack SDK 専用**: 通常の Bolt.js/Bolt-py アプリでは使えない機能
- **開発者の初期セットアップは CLI 必須**: `slack deploy`、`slack external-auth add-secret` は開発者が CLI で実施（エンドユーザーには不要）

### 新発見: SLACK_PROVIDED プロバイダータイプ

アプリマニフェストに `provider_type: "SLACK_PROVIDED"` というタイプが存在。`client_id` と `scope` のみで設定可能（`CUSTOM` より簡略化）。詳細は要別途調査。

---

## 完了サマリー

- **調査日**: 2026-04-16
- **ログファイル**: `logs/0005_external-auth-slack-ui-flow.md`
- **結論**: `credential_source: "END_USER"` を使えば、エンドユーザーは Slack CLI なしで Slack の Link Trigger 経由でブラウザの OAuth2 フローにて外部認証を完了できる。数百名のユーザーも CLI 操作不要。ただし Link Trigger 専用・有料プラン必須・Deno Slack SDK 専用という制約がある。
