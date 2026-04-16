# Slack 外部認証 UIからの認証フロー 調査ログ

## タスク概要

- **kanban ファイル**: `kanban/0005_external-auth-slack-ui-flow.md`
- **知りたいこと**: Slackの外部認証機能はプロバイダーを設定すればSlack上から認証を通すことができるのか？
- **目的**: 前回の調査では Slack CLI を使った認証フローを確認した。しかし実運用では Slack UI から認証を通せないと実用性が低い。数百名が CLI を使うのは現実的でなく、CLI 操作に不慣れな人もいる。
- **調査日**: 2026-04-16

---

## 調査ファイル一覧

| ファイルパス | 内容 |
|---|---|
| `logs/0004_slack-external-auth.md` | 前回調査ログ（外部認証の全体像） |
| `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md` | 外部認証統合メインガイド（END_USER / DEVELOPER フロー） |
| `docs/tools/deno-slack-sdk/guides/creating-link-triggers.md` | Link Trigger（ショートカットリンク）ガイド |
| `docs/tools/deno-slack-sdk/tutorials/open-authorization.md` | OAuth2チュートリアル（Simple Surveyアプリ） |
| `docs/tools/slack-cli/reference/commands/slack_external-auth_select-auth.md` | CLIコマンド: select-auth |
| `docs/workflows/run-on-slack-infrastructure.md` | ROSI アーキテクチャ（サードパーティ認証セクション） |
| `docs/reference/app-manifest.md` | アプリマニフェスト（external_auth_providers） |

---

## 調査アプローチ

1. 前回調査ログ（log 0004）を読み込み、前回判明した情報を整理
2. 外部認証メインガイドの `credential_source` セクション（END_USER / DEVELOPER）を詳細確認
3. Link Trigger ガイドを読みUIからのトリガー発動の仕組みを確認
4. ROSI ガイドでサードパーティ認証の概念を確認
5. アプリマニフェストで `SLACK_PROVIDED` プロバイダータイプを発見

---

## 調査結果

### 1. 前回調査の復習

**ソース**: `logs/0004_slack-external-auth.md`

前回調査では、外部認証（External Authentication）は主に CLI コマンドを使ったフローとして説明されていた：

- `slack external-auth add-secret` でクライアントシークレット追加
- `slack external-auth add` で OAuth2 フロー開始（ブラウザが開く）
- `slack external-auth select-auth` でワークフローに使うアカウントを選択

**疑問点として残っていたこと**: これがエンドユーザーにも CLI を使わせる必要があるのか？

---

### 2. `credential_source` の2種類のモード

**ソース**: `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`（lines 289-320）

外部認証には2種類のモードがある。これが今回の調査の核心部分。

#### モード1: `credential_source: "END_USER"` — Slack UI から認証可能

```typescript
const sampleFunctionStep = SampleWorkflow.addStep(SampleFunctionDefinition, {
  user: SampleWorkflow.inputs.user,
  googleAccessTokenId: {
    credential_source: "END_USER"
  },
});
```

公式ドキュメントの説明（原文）:

> "If you would like the workflow to use the account of the end user running the workflow, use `credential_source: "END_USER"`.
>
> **The end user will be asked to authenticate with the external service in order to connect and grant Slack access to their account before running the workflow.** This workflow can only be started by a [Link Trigger], as this is the only type of trigger guaranteed to originate directly from an end-user interaction."

**重要ポイント**:
- ユーザーがワークフローを実行すると、**Slackが外部サービスへの認証を要求する**（UI経由）
- ユーザーはブラウザが開き、OAuth2 フロー（Googleへのサインインなど）を完了する
- 認証完了後、`oauth2.slack.com` のページで「アカウントが接続されました」と表示される
- Slack がトークンを保存し、以降のワークフロー実行で使用される
- **エンドユーザーは Slack CLI を使う必要がない**
- **ただし Link Trigger（ショートカットリンク）でのみ動作** — スケジュールトリガー、Webhookトリガー、イベントトリガーは対象外

#### モード2: `credential_source: "DEVELOPER"` — CLI が必要

```typescript
const sampleFunctionStep = SampleWorkflow.addStep(SampleFunctionDefinition, {
  user: SampleWorkflow.inputs.user,
  googleAccessTokenId: {
    credential_source: "DEVELOPER"
  },
});
```

公式ドキュメントの説明（原文）:

> "If you would like the workflow to use the account of one of the app collaborators, use `credential_source: "DEVELOPER"`."
>
> "After deploying the manifest changes above, you have to select a specific account for each of your workflows in this app. Assuming that you had run `slack external-auth add` before to add an external account, use the command `slack external-auth select-auth`..."

**重要ポイント**:
- 開発者（コラボレーター）が CLI で `slack external-auth add` を実行してトークンを作成
- 開発者が CLI で `slack external-auth select-auth` を実行してワークフローに紐付け
- 全ワークフロー実行で開発者のトークンを使用（エンドユーザーは外部サービスに認証不要）
- **エンドユーザーは認証不要だが、開発者は CLI での操作が必須**
- 複数コラボレーターがいる場合、各自が `slack external-auth select-auth` を自分で実行する必要がある（代理実行不可）

---

### 3. Link Trigger の仕組み

**ソース**: `docs/tools/deno-slack-sdk/guides/creating-link-triggers.md`

Link Trigger（ショートカットリンク）とは:
- `https://slack.com/shortcuts/Ft0123ABC456/abc123...` のような URL
- Slack チャンネルに投稿するとボタンとして展開される（unfurl）
- チャンネルのブックマークバーに追加できる
- スラッシュコマンド経由でも呼び出せる
- Workflow Builder のボタン（workflow_button）としても利用可能

Link Trigger がエンドユーザー認証に必要な理由:
> "This workflow can only be started by a Link Trigger, as this is the only type of trigger guaranteed to originate directly from an end-user interaction."

つまり、Link Trigger だけが「特定のユーザーがワークフローを起動した」ことを保証できる。他のトリガー（スケジュール、Webhook、イベント）ではユーザーを特定できないため、END_USER 認証は使えない。

---

### 4. ROSI での認証の位置づけ

**ソース**: `docs/workflows/run-on-slack-infrastructure.md`（lines 71-75）

> "Developers integrating their apps with third-party systems often use APIs as the primary means of integration. To simplify and secure the integration process, the Slack platform has implemented a feature called third-party authentication. With an abundance of external systems and APIs that can be used in a Slack app, the industry has adopted OAuth2 as a standard protocol to streamline the authorization process. This feature relies on OAuth2 for authentication. **When a developer is creating a workflow, they can authenticate with the third-party service, and this authorization will be used during the execution of the workflow when API calls are made to the external service.**"

このセクションでは主に DEVELOPER モードの説明をしているが、外部認証が Slack の ROSI（Run On Slack Infrastructure）の標準機能として組み込まれていることを確認できる。

---

### 5. SLACK_PROVIDED プロバイダータイプ（新発見）

**ソース**: `docs/reference/app-manifest.md`（lines 1539-1557）

アプリマニフェストのドキュメントに `SLACK_PROVIDED` というプロバイダータイプが記載されていた（前回調査では確認していなかった）：

> "`external_auth_providers.provider_type` Can be either `CUSTOM` or `SLACK_PROVIDED`."
>
> "If `provider_type` is `SLACK_PROVIDED`, the object will contain a string `client_id` and string `scope`."

`CUSTOM` タイプでは `provider_name`、`authorization_url`、`token_url`、`scope`、`identity_config` などを全て自分で設定する必要があるが、`SLACK_PROVIDED` タイプでは `client_id` と `scope` だけで済む。

**推測**: `SLACK_PROVIDED` は Slack が事前に設定したプロバイダー（Google、GitHubなど）を使うモードと思われる。ただし、このドキュメントには詳細な説明がなく、`DefineOAuth2Provider` でどのように指定するかも不明。（要別途調査）

---

### 6. OAuthコールバックURL（CLIとUIの違い）

**ソース**: `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`（line 25-27）

OAuth プロバイダーに設定するリダイレクト URL は：

```
https://oauth2.slack.com/external/auth/callback
```

これは CLI からのフローでも、Slack UI からのフローでも同一の URL を使う。つまり OAuth2 のコールバックは Slack が一元管理している。ユーザーが CLI で認証してもSlack UI経由で認証しても、最終的にこのエンドポイントに戻ってくる。

---

## 判断・意思決定

1. **END_USER モードが今回の調査の核心**: `credential_source: "END_USER"` を使うことで、エンドユーザーは CLI 不要で Slack UI から外部認証を完了できる。これが前回調査で未確認だった「CLI なしで認証可能か」という疑問の答え。

2. **Link Trigger 必須という制約**: END_USER モードは Link Trigger（ショートカットリンク）でのみ動作する。これは技術的必然（ユーザーを特定するため）。

3. **開発者側の CLI 操作は依然必要**: エンドユーザーは CLI 不要だが、開発者はアプリのデプロイ（`slack deploy`）とクライアントシークレットの設定（`slack external-auth add-secret`）に CLI が必要。

4. **DEVELOPER モードと END_USER モードの使い分け**:
   - 特定の管理者アカウントのトークンで全ユーザーに対してAPIを呼び出す場合 → `DEVELOPER`
   - 各ユーザー自身のアカウントで外部APIを呼び出す場合（パーソナライズ） → `END_USER`

5. **SLACK_PROVIDED プロバイダーの詳細は未確認**: これについては別途調査が必要。

---

## 問題・疑問点

1. **END_USER 認証のUI体験の詳細不明**: ユーザーがLink Triggerをクリックしてから認証を求められるまでの具体的なUI（ダイアログの外観、ボタンの位置など）はドキュメントに記載なし。スクリーンショット等も見当たらなかった。

2. **SLACK_PROVIDED プロバイダータイプ**: `provider_type: "SLACK_PROVIDED"` の詳細（対応プロバイダー一覧、`DefineOAuth2Provider` での指定方法）が不明。

3. **一度認証したトークンの持続性**: END_USER モードで一度認証したトークンはいつまで有効か？トークンが期限切れになった場合、ユーザーは再度 Slack UI から認証する必要があるか？（`force_refresh: true` で自動リフレッシュは可能だが、リフレッシュトークンが必要）

4. **Enterprise Grid でのマルチワークスペース対応**: 数百名が使用する場合、Enterprise Grid 環境での動作や制約（オーグレベルでのトークン管理など）は未確認。
