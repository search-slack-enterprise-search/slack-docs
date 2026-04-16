# 0003_connection_report_auth 作業ログ

## 基本情報

- **タスクファイル**: kanban/0003_connection_report_auth.md
- **開始日時**: 2026-04-16T14:23:18+09:00
- **完了日時**: 2026-04-16T14:24:00+09:00

## タスク概要

connection report では認証状態が表示されると `kanban/0002_what_connection_report.md` で回答されたが、Enterprise Search においてそもそもユーザーは認証していないですよね？
何との認証状態を表示しているのですか？

## 調査結果

### 1. `docs/enterprise-search/connection-reporting.md` — 認証状態の定義

#### 公式定義

> Slack's connection reporting feature allows your app to communicate a **user's authentication status, or connection status**, directly to Slack. By offloading the UI management for "connect/disconnect" states to Slack, you can ensure a consistent user experience while reducing development overhead.

「認証状態（authentication status）」と「接続状態（connection status）」が同義語として定義されている。

この定義から読み取れること：
- 「認証状態」とは、ユーザーが**アプリ（＝外部データソース）に認証しているかどうか**を示す
- Slack への認証（Slack ログイン）は無関係 — それはすでに全員済みの前提
- アプリが Slack に対して「このユーザーの認証状態」を報告する構造

#### 具体的なシーケンス（ドキュメント記載）

1. ユーザーが未接続の場合、Slack UI に「Connect」ボタンが表示される
2. ユーザーが「Connect」をクリックすると、アプリが `user_connection` イベント（subtype: connect）を受信。このイベントには `trigger_id` が含まれ、モーダルを開いてユーザーに**アプリへの接続手順を案内**できる
3. ユーザーが接続完了後、アプリは `apps.user.connection.update` API を呼び出して接続ステータスの変更を Slack に報告し、UI が更新される

「アプリへの接続手順を案内できる（allows the user to connect to your app）」という記述が重要。ここでの「接続」は Slack への接続ではなく、**アプリが統合する外部データソースへの接続（認証）**を指す。

---

### 2. `docs/enterprise-search/developing-apps-with-search-features.md` — 「Authentication Required」エラー例

#### 決定的な証拠：外部サービス認証が必要であることを示すエラーメッセージ

> The `functions.completeError` API method provides Slack with a user-friendly error message and informs Slack that the `function_executed` event completed with an error. The error message provided by your app will be displayed to the user on the search page. It can be any plain text value with links you think could be insightful to the user. For example: *Authentication Required: Please visit https://getauthhere.slack.dev to authenticate your account.*

このエラーメッセージの例が示すこと：
- ユーザーが外部サービスに**認証していない状態**で検索を実行すると、検索が失敗する
- アプリは「Authentication Required」メッセージでユーザーを外部サービスの認証画面へ誘導できる
- これが Connection Report（Connect → モーダル → 外部認証）のフローと直接対応している

つまり Connection Report の「認証状態」とは：
- **connected** = ユーザーが外部データソースに認証済み → 検索結果を返せる
- **disconnected** = ユーザーが外部データソースに未認証 → 検索が失敗、「Authentication Required」エラー

#### `slack#/types/user_context` パラメータとの関係

```
The user_context type can optionally be added as an input parameter in the function.
```

検索関数の入力パラメータとして `slack#/types/user_context` 型（検索を実行しているユーザーのコンテキスト）を使うことで、アプリはどのユーザーが検索しているかを識別し、そのユーザーが外部サービスに認証済みかどうかに応じた検索結果の制御が可能になる。

---

### 3. `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md` — 外部認証システムの仕組み

#### Slack の「外部認証（External Authentication）」機能

Slack は OAuth2 ベースの外部サービス認証システムを提供している。これにより、**ユーザーごとに外部サービス（Google、GitHub、独自システムなど）へのアクセストークンを Slack が暗号化して保管**できる。

> You can use the Slack CLI to encrypt and to store OAuth2 credentials. This enables your app to access information from another service without exchanging passwords, but rather, tokens.

#### OAuth2 外部認証フロー

1. **アプリが OAuth2 プロバイダーを定義**
   - `provider_key`: プロバイダーの一意識別子
   - `client_id` / `client_secret`: 外部サービスの認証情報
   - `authorization_url`, `token_url`: OAuth2 エンドポイント
   - `scope`: 要求する権限範囲

2. **ユーザーが認証トークンを取得**
   - `slack external-auth add` コマンド（CLI 操作）
   - またはアプリのモーダルで外部サービスの認証画面へ誘導

3. **ユーザーがブラウザで外部サービスに OAuth2 ログイン**

   > Select the provider you're working on, which will open a browser window for you to complete the OAuth2 sign-in flow according to your provider's requirements. You'll know you're successful when your browser sends you to a `oauth2.slack.com` page stating that your account was successfully connected.

4. **Slack が外部トークンを暗号化して保管**
   - ユーザーごとに異なるトークン ID で管理される
   - `identity_config` フィールドで `external_user_id` を抽出し、ユーザーごとに管理

#### なぜユーザーごとに認証状態が異なるのか

> The `identity_config` field is used to extract an `external_user_id`. This value is then used to allow a single user to issue multiple tokens for multiple provider accounts.

- **各ユーザーが独自の外部サービスアカウントを持つ**（例: user_A@company.com, user_B@company.com）
- **各ユーザーが個別に外部サービスに認証する**
- **Slack は各ユーザーの外部認証トークンを別々に管理**
- したがって接続状態はユーザーごとに異なる（全員で一律に「接続済み」にはならない）

---

### 4. `docs/reference/methods/apps.auth.external.get.md` — 外部トークンの取得

#### API の役割

> Once you have your OAuth2 provider configured, you can use this API method to retrieve the token needed to access your external service by its token ID.

実装例：
```typescript
const auth = await client.apps.auth.external.get({
  external_token_id: inputs.reactor_access_token_id,
});
if (!auth.ok) {
  return { error: `Failed to collect Google auth token: ${auth.error}` };
}
```

Enterprise Search アプリの検索処理フロー：
1. `function_executed` イベントで検索クエリを受け取る
2. `apps.auth.external.get` でそのユーザーの外部サービストークンを取得
3. 外部サービス API を呼び出して検索結果を取得
4. `functions.completeSuccess` で検索結果を Slack に返す
   - 外部トークンがない場合 → `functions.completeError` で「Authentication Required」を返す

---

### 5. `docs/reference/methods/apps.auth.external.delete.md` — 外部トークンの削除

> Delete external auth tokens only on the Slack side

ユーザーが「Disconnect」をクリックした際の処理：
- `user_connection` イベント（subtype: disconnect）受信
- 外部サービス側でのセッション無効化（アプリ独自の処理）
- `apps.auth.external.delete` で Slack 側の外部トークンを削除
- `apps.user.connection.update` で `status: disconnected` を Slack に報告

---

### 調査結果の総合：何との認証状態なのか

**Connection Report の「認証状態」は、ユーザーが Enterprise Search アプリが統合する「外部データソース（外部サービス）」に認証しているかどうかを示す。**

| 認証の種類 | 対象 | Connection Report との関係 |
|-----------|------|--------------------------|
| Slack への認証 | Slack | 全員済み、Connection Report とは無関係 |
| 外部データソースへの認証 | 社内 Wiki、Google Drive、独自システムなど | **Connection Report が示す認証状態** |

#### 具体例

Enterprise Search アプリが「社内 Wiki」を Slack 検索に統合している場合：
- 社員Aが社内 Wiki に「tanaka@company.com」でログイン済み → **connected**
- 社員Bが社内 Wiki にまだログインしていない → **disconnected**、検索すると「Authentication Required」エラー
- 社員Bが Slack の「Connect」ボタンをクリック → モーダルが開き、社内 Wiki の認証ページへ誘導
- 社員Bが社内 Wiki にログイン → アプリが `apps.user.connection.update` で `connected` を Slack に報告

## 実装プラン

このタスクはドキュメント調査タスクであり、コード変更は不要。

1. ログファイル `logs/0003_connection_report_auth.md` を作成（本ファイル）
2. kanban ファイル `kanban/0003_connection_report_auth.md` に `## プラン` セクションを追記
3. kanban ファイルに `## 完了サマリー` を追記
4. 変更ファイルを git add → commit → push

## プランニング経緯

### 初回提案

以下の内容でプランを提示：
- Connection Report の「認証状態」= ユーザーが外部データソースに認証しているかどうか
- Slack への認証（全員済み）とは無関係
- 証拠として 3 つの主要ドキュメントの記述を提示
- 「Authentication Required」エラー例が決定的証拠として機能

### ユーザーフィードバック

初回提案がそのまま承認された。

## 会話内容

### [14:20頃] ユーザー指示

`/kanban` コマンドを実行。引数なしのため、未完了タスクのうち番号最大の `0003_connection_report_auth.md` が自動選択された。

### [14:21頃] Claude 対応 — タスクファイル読み込み・目的セクション確認

- `kanban/0003_connection_report_auth.md` を読み込み、タスク内容を確認
- 前回タスク（0002）の kanban ファイルとログファイルを読み込み、調査済み事項を把握
- `## 知りたいこと` は What に該当し、目的（Why）セクションが存在しないと判定
- ユーザーに確認 → 続行を選択

### [14:22頃] Claude 対応 — Explore エージェントによる調査

Explore エージェントを起動し、以下のドキュメントを調査：
- `docs/enterprise-search/connection-reporting.md` — 「認証状態」の定義
- `docs/enterprise-search/developing-apps-with-search-features.md` — 「Authentication Required」エラー例
- `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md` — 外部認証 OAuth2 フローの詳細
- `docs/reference/methods/apps.auth.external.get.md` — 外部トークン取得 API
- `docs/reference/methods/apps.auth.external.delete.md` — 外部トークン削除 API
- `docs/reference/events/user_connection.md` — イベントリファレンス
- `docs/reference/methods/apps.user.connection.update.md` — API メソッドリファレンス

### [14:23頃] Claude 対応 — プランニング・承認

- プランファイルを作成
- ExitPlanMode でユーザー承認をリクエスト
- ユーザーが承認

### [14:23頃] Claude 対応 — 実装フェーズ開始

- タイムスタンプ取得
- ログファイル作成（本ファイル）

## 編集したファイル

| ファイル | 変更内容 |
|---------|---------|
| `kanban/0003_connection_report_auth.md` | `## プラン` セクションを追記、`## 完了サマリー` を追記 |
| `logs/0003_connection_report_auth.md` | 新規作成（本ファイル） |

## 実行したコマンド

```bash
TZ=Asia/Tokyo date +"%Y-%m-%dT%H:%M:%S+09:00"
# → 2026-04-16T14:23:18+09:00

git add kanban/0003_connection_report_auth.md logs/0003_connection_report_auth.md
git commit -m "Connection Report 認証状態調査: 外部データソースへのユーザー認証状態であることを確認"
git push
```

## 判断・意思決定

- 「認証状態」の解釈を「Slack への認証」ではなく「外部データソース（外部サービス）への認証」と確定した。根拠は以下：
  1. `connection-reporting.md` の "allows the user to connect to your app" という記述（「あなたのアプリへの接続」= 外部サービスへの接続）
  2. `developing-apps-with-search-features.md` の「Authentication Required: Please visit ... to authenticate your account」エラー例（外部サービスへの認証を求めている）
  3. `integrating-with-services-requiring-external-authentication.md` の OAuth2 外部認証システム（ユーザーごとに外部サービスのトークンを管理）
- 「なぜユーザーごとに状態が異なるのか」を明確にするため、外部認証システムの `identity_config` と `external_user_id` の仕組みを調査した

## エラー・問題

- なし
