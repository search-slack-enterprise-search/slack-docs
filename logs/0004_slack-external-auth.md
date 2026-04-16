# Slack 外部認証 調査ログ

## タスク概要

- **kanban ファイル**: `kanban/0004_slack-external-auth.md`
- **知りたいこと**: Slackの外部認証について
- **目的**: どういった機能なのか、どうやって使うのか、どうやって実装するのかを知りたい
- **調査日**: 2026-04-16

---

## 調査ファイル一覧

| ファイルパス | 内容 |
|---|---|
| `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md` | 外部認証統合メインガイド |
| `docs/tools/deno-slack-sdk/tutorials/open-authorization.md` | OAuth2チュートリアル（Simple Surveyアプリ） |
| `docs/tools/slack-cli/reference/commands/slack_external-auth.md` | CLIコマンド親リファレンス |
| `docs/tools/slack-cli/reference/commands/slack_external-auth_add.md` | CLIコマンド: add |
| `docs/tools/slack-cli/reference/commands/slack_external-auth_add-secret.md` | CLIコマンド: add-secret |
| `docs/tools/slack-cli/reference/commands/slack_external-auth_remove.md` | CLIコマンド: remove |
| `docs/tools/slack-cli/reference/commands/slack_external-auth_select-auth.md` | CLIコマンド: select-auth |
| `docs/reference/methods/apps.auth.external.get.md` | Web API: apps.auth.external.get |
| `docs/reference/methods/apps.auth.external.delete.md` | Web API: apps.auth.external.delete |

---

## 調査アプローチ

1. Explore エージェントで `docs/` 以下の "external auth" / "外部認証" 関連ファイルを網羅的に検索
2. 主要ドキュメント（メインガイド、チュートリアル、CLIリファレンス、APIリファレンス）を詳細に読み込み

---

## 調査結果

### 1. 外部認証（External Authentication）とは何か

**ソース**: `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`

Slackの外部認証は **OAuth2 (Open Authorization 2.0)** を使って、SlackワークフローアプリがGoogleやGitHubなどの外部サービスにアクセスするための仕組み。

> "You can use the Slack CLI to encrypt and to store OAuth2 credentials. This enables your app to access information from another service without exchanging passwords, but rather, tokens."

パスワードを共有する代わりにアクセストークンを使ってユーザーの身元を確認する。

**用途**: Slack ワークフローアプリが Google Sheets、GitHub、Salesforce などの外部 API に安全にアクセスする際に使用する。

**前提条件**:
- ワークフローアプリには有料プランが必要（"Workflow apps require a paid plan"）
- Deno Slack SDK を使って実装する
- Slack CLI が必要

---

### 2. 実装の全体フロー（9ステップ）

**ソース**: `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`

#### Step 1: OAuth2 認証情報の取得

外部サービス（例: Google）で OAuth2 クライアントID とクライアントシークレットを取得する。

リダイレクト URL には以下を使用する:
```
https://oauth2.slack.com/external/auth/callback
```

#### Step 2: OAuth2 プロバイダーの定義

`manifest.ts` に `DefineOAuth2Provider` をインポートし、プロバイダーインスタンスを作成する。

```typescript
import { DefineOAuth2Provider, Schema } from "deno-slack-sdk/mod.ts";

const GoogleProvider = DefineOAuth2Provider({
  provider_key: "google",                          // 一意のキー（必須）
  provider_type: Schema.providers.oauth2.CUSTOM,   // 唯一サポートされる型（必須）
  options: {
    provider_name: "Google",                       // プロバイダー名（必須）
    authorization_url: "https://accounts.google.com/o/oauth2/auth", // OAuth2認証URL（必須）
    token_url: "https://oauth2.googleapis.com/token",               // トークンURL（必須）
    client_id: "<your_client_id>.apps.googleusercontent.com",       // クライアントID（必須）
    scope: [                                       // 必要なスコープ（必須）
      "https://www.googleapis.com/auth/spreadsheets.readonly",
      "https://www.googleapis.com/auth/userinfo.email",
      "https://www.googleapis.com/auth/userinfo.profile",
    ],
    authorization_url_extras: {                    // 追加クエリパラメータ（任意）
      prompt: "consent",
      access_type: "offline",
    },
    identity_config: {                             // ユーザー識別設定（必須）
      url: "https://www.googleapis.com/oauth2/v1/userinfo",
      account_identifier: "$.email",              // レスポンスからユーザーIDを取得するフィールド
      http_method_type: "GET",
    },
    use_pkce: false,                               // PKCEを使うか（任意、デフォルトfalse）
  },
});
```

**OAuth2 provider properties（完全版）**:

| フィールド | 型 | 説明 | 必須 |
|---|---|---|---|
| `provider_key` | string | プロバイダーの一意識別子。変更すると削除扱いになる。アクティブなトークンがある場合は削除不可 | 必須 |
| `provider_type` | Schema.providers.oauth2 | 現在 `Schema.providers.oauth2.CUSTOM` のみサポート | 必須 |
| `options` | object | プロバイダー固有の詳細設定 | 必須 |

**OAuth2 provider options properties（完全版）**:

| フィールド | 型 | 説明 | 必須 |
|---|---|---|---|
| `provider_name` | string | プロバイダー名 | 必須 |
| `client_id` | string | プロバイダーから取得したクライアントID | 必須 |
| `authorization_url` | string | OAuth2フローのユーザー同意画面へのURL | 必須 |
| `scope` | array | アクセストークンに付与するスコープ | 必須 |
| `identity_config` | object | アクセストークンに関連するアカウントを特定するための設定 | 必須 |
| `token_url` | string | コードをアクセストークンに交換するためのURL | 必須 |
| `token_url_config` | object | `use_basic_auth_scheme` を含むオブジェクト（HTTP Basic Auth をtoken_urlで使うか。デフォルトfalse） | 任意 |
| `authorization_url_extras` | object | authorization_url に付加するクエリパラメータ | 任意 |
| `use_pkce` | boolean | PKCEを使うか（デフォルトfalse） | 任意 |

**identity_config properties（完全版）**:

| フィールド | 型 | 説明 | 必須 |
|---|---|---|---|
| `url` | string | ユーザーIDを取得するエンドポイント | 必須 |
| `account_identifier` | string | レスポンス内のユーザーIDフィールド名 | 必須 |
| `headers` | object | リクエストに付加する追加HTTPヘッダー（Authorizationヘッダーは自動設定） | 任意 |
| `http_method_type` | string | HTTPメソッド（デフォルトGET、GET/POST可） | 任意 |
| `body` | object | identity url へのPOSTリクエストのボディパラメータ | 任意 |

**重要**: `identity_config` フィールドは `external_user_id` を抽出するために使われる。Slackユーザーが複数アカウントを持ち、同じ `external_user_id` を取得した場合、既存トークンが上書きされ、複数アカウントを使用できなくなる。

#### Step 3: マニフェストへの追加

```typescript
export default Manifest({
  //...
  externalAuthProviders: [GoogleProvider],  // ここにプロバイダーを追加
  //...
});
```

#### Step 4: クライアントシークレットの暗号化・保存

まずアプリをデプロイする:
```bash
slack deploy
```

次にクライアントシークレットを追加する:
```bash
slack external-auth add-secret --provider google --secret "GOCSPX-abc123..."
```

成功すると:
```
✨  successfully added external auth client secret for google
```

エラー `provider_not_found` が出た場合は、マニフェストの `externalAuthProviders` を確認する。

#### Step 5: OAuth2 フローの初期化（トークン作成）

```bash
slack external-auth add
```

実行するとワークスペースとプロバイダーの選択リストが表示される:
```
$ slack external-auth add
? Select a provider  [Use arrows to move, type to filter]
> Provider Key: google
  Provider Name: Google
  Client ID: <your_id>.apps.googleusercontent.com
  Client Secret Exists? Yes
  Token Exists? No
```

プロバイダーを選択するとブラウザが開き、OAuth2サインインフローが完了。成功すると `oauth2.slack.com` ページが表示される。

再実行して確認:
```
Token Exists? Yes
```

#### Step 6: カスタム関数への OAuth2 統合

関数定義で `Schema.slack.types.oauth2` 型の入力パラメータを設定する:

```typescript
import { DefineFunction, Schema, SlackFunction } from "deno-slack-sdk/mod.ts";

export const SampleFunctionDefinition = DefineFunction({
  callback_id: "sample_function",
  title: "Sample function",
  source_file: "functions/sample_function.ts",
  input_parameters: {
    properties: {
      googleAccessTokenId: {
        type: Schema.slack.types.oauth2,    // OAuth2トークン型
        oauth2_provider_key: "google",      // 対応するprovider_key
      },
      // ...その他のパラメータ
    },
  },
  // ...
});

export default SlackFunction(
  SampleFunctionDefinition,
  async ({ inputs, client }) => {
    // トークンを取得する
    const tokenResponse = await client.apps.auth.external.get({
      external_token_id: inputs.googleAccessTokenId,
    });
    if (tokenResponse.error) {
      const error = `Failed to retrieve the external auth token due to ${tokenResponse.error}`;
      return { error };
    }

    // トークンを使って外部APIを呼び出す
    const externalToken = tokenResponse.external_token;
    const response = await fetch("https://somewhere.tld/myendpoint", {
      headers: new Headers({
        "Authorization": `Bearer ${externalToken}`,
        "Content-Type": "application/x-www-form-urlencoded",
      }),
    });
    // ...
  },
);
```

#### Step 7: ワークフローステップでの OAuth2 入力設定

ワークフロー内でどのユーザーの認証を使うか `credential_source` で指定する。

**エンドユーザーのトークンを使う場合（END_USER）**:
```typescript
const sampleFunctionStep = SampleWorkflow.addStep(SampleFunctionDefinition, {
  user: SampleWorkflow.inputs.user,
  googleAccessTokenId: {
    credential_source: "END_USER"    // ワークフロー実行者のアカウントを使用
  },
});
```
- エンドユーザーは外部サービスへの認証を求められる
- リンクトリガー（Link Trigger）でのみ動作（ユーザーインタラクションが保証される唯一のトリガータイプ）

**開発者のトークンを使う場合（DEVELOPER）**:
```typescript
const sampleFunctionStep = SampleWorkflow.addStep(SampleFunctionDefinition, {
  user: SampleWorkflow.inputs.user,
  googleAccessTokenId: {
    credential_source: "DEVELOPER"   // アプリコラボレーターのアカウントを使用
  },
});
```
- `slack external-auth add` で追加したアカウントを使用
- `slack external-auth select-auth` でワークフローに対して使うアカウントを選択する必要がある

複数のコラボレーターが同じアプリに存在でき、各自が `slack external-auth add` でトークンを作成できる。ただし、`slack external-auth select-auth` は他のコラボレーターの代わりに選択することはできない（各自が自分で実行する必要がある）。

コラボレーターが `slack external-auth remove` でアカウントを削除すると、そのアカウントを使っていた全ワークフローの選択済み認証が自動的に削除される。その場合、`slack external-auth select-auth` を再度実行する必要がある。

デプロイ後に認証を選択:
```bash
slack external-auth select-auth
```

```
$ slack external-auth select-auth
? Select a workspace <workspace_name> <workspace_id>
? Choose an app environment Deployed <app_id>
? Select a workflow Workflow: #/workflows/<workspace_name>
  Providers:
        Key: google, Name: Google, Selected Account: None
? Select a provider Key: google, Name: Google, Selected Account: None
? Select an external account Account: <your_id>@gmail.com, Last Updated: 2023-05-30
✨  Workflow #/workflows/<workspace_name> will use developer account <your_id>@gmail.com when making calls to google APIs
```

#### Step 8: トークンの強制リフレッシュ（プログラム的）

```typescript
const result = await client.apps.auth.external.get({
  external_token_id: inputs.googleAccessTokenId,
  force_refresh: true    // デフォルトは false
});
```

#### Step 9: トークンの削除（プログラム的）

```typescript
await client.apps.auth.external.delete({
  external_token_id: inputs.googleAccessTokenId,
});
```

注意: これはSlack側でのトークン参照を削除するだけ。プロバイダー側での無効化は別途必要。

---

### 3. CLIコマンドリファレンス

**ソース**: `docs/tools/slack-cli/reference/commands/slack_external-auth*.md`

#### `slack external-auth`（親コマンド）

```
slack external-auth <subcommand> [flags]
```

説明: ワークフローアプリの外部認証プロバイダーの設定を調整する。

Slack managed infrastructure にデプロイされたアプリでサポート。他のアプリは `--force` フラグで試行可能。

#### `slack external-auth add`

```bash
slack external-auth add               # プロバイダーを選択してOAuth2フロー開始
slack external-auth add -p github     # 指定プロバイダーのOAuth2フロー開始
```

フラグ:
- `-p, --provider string`: プロバイダーキーを指定

#### `slack external-auth add-secret`

```bash
slack external-auth add-secret                          # インタラクティブに入力
slack external-auth add-secret -p github -x ghp_token  # プロバイダーとシークレットを直接指定
```

フラグ:
- `-p, --provider string`: プロバイダーキー
- `-x, --secret string`: クライアントシークレット

説明: OAuth2フロー時に使用するクライアントシークレットを追加する。

#### `slack external-auth remove`

```bash
slack external-auth remove                       # リストから選択して削除
slack external-auth remove -p github             # 指定プロバイダーのトークン削除
slack external-auth remove --all -p github       # 指定プロバイダーの全トークン削除
slack external-auth remove --all                 # 全プロバイダーの全トークン削除
```

フラグ:
- `-p, --provider string`: プロバイダーキー
- `-A, --all`: 全トークンを削除

**注意**: 既存トークンはアプリから削除されるだけで、プロバイダー側では無効化・削除されない！プロバイダーの開発者コンソールまたはAPIを使って無効化する必要がある。

#### `slack external-auth select-auth`

```bash
slack external-auth select-auth \
  --workflow #/workflows/workflow_callback \
  --provider google_provider \
  --external-account user@salesforce.com
```

フラグ:
- `-W, --workflow string`: 対象ワークフロー
- `-p, --provider string`: プロバイダー
- `-E, --external-account string`: 外部アカウント識別子

説明: ワークフローアプリの関数から外部APIを呼び出す際に使用する、保存済み開発者認証を選択する。

---

### 4. Web API リファレンス

#### `apps.auth.external.get`

**ソース**: `docs/reference/methods/apps.auth.external.get.md`

```
POST https://slack.com/api/apps.auth.external.get
```

| SDK | メソッド |
|---|---|
| Bolt.js | `app.client.apps.auth.external.get` |
| Bolt-py | `app.client.apps_auth_external_get` |
| Bolt-Java | `app.client().appsAuthExternalGet` |

**レート制限**: Tier 3（50+/分）

**必須引数**:
- `token`: 認証トークン
- `external_token_id`: 取得したいトークンのID（例: `Et12345ABCDE`）

**任意引数**:
- `force_refresh`: trueで有効期限前でも強制リフレッシュ（デフォルト: false）

**成功レスポンス例**:
```json
{
  "ok": true,
  "external_token": "00D3j00000025Zh!AQ4AQMAl46qme3wdZiKo5j3WHcJujZXoB0FtsFuC5JxWZdje2aiecF9vY5KdY5wTPUZIYBekIraDWuw_u_ZUgeIA1.opF6L9"
}
```

**エラーレスポンス例**:
```json
{
  "ok": false,
  "error": "not_allowed_token_type"
}
```

**主なエラー**:
- `access_token_exchange_failed`: トークン交換・リフレッシュエラー
- `no_refresh_token`: リフレッシュトークンが存在しない
- `token_not_found`: 指定したexternal_token_idのトークンが見つからない
- `token_expired`: 認証トークンの期限切れ
- `not_allowed_token_type`: 許可されていないトークンタイプ

#### `apps.auth.external.delete`

**ソース**: `docs/reference/methods/apps.auth.external.delete.md`

```
POST https://slack.com/api/apps.auth.external.delete
```

| SDK | メソッド |
|---|---|
| Bolt.js | `app.client.apps.auth.external.delete` |
| Bolt-py | `app.client.apps_auth_external_delete` |
| Bolt-Java | `app.client().appsAuthExternalDelete` |

**レート制限**: Tier 4（100+/分）

**必須引数**:
- `token`: 認証トークン

**任意引数**:
- `app_id`: 削除対象アプリID
- `provider_key`: 削除対象プロバイダーキー
- `external_token_id`: 削除対象トークンID

**主なエラー**:
- `app_not_found`: 指定されたapp_idが見つからない
- `invalid_auth`: 指定されたexternal_token_idのトークンを削除する権限がない
- `no_tokens_found`: 削除対象のトークンが見つからない
- `providers_not_found`: 指定されたprovider_keyが無効
- `token_not_found`: 指定されたexternal_token_idのトークンが見つからない

---

### 5. チュートリアル（Simple Survey アプリ）

**ソース**: `docs/tools/deno-slack-sdk/tutorials/open-authorization.md`

Google Sheetsを使ったアンケートアプリを例に、OAuth2の実装を解説。

**アプリ構成**:
```
assets/
datastores/
deno.json
deno.lock
external_auth/         ← 外部認証定義ファイルを格納
functions/
import_map.json
manifest.ts
triggers/
workflows/
```

**プロバイダー定義ファイル（`external_auth/google_provider.ts`）の例**:
```typescript
import { DefineOAuth2Provider, Schema } from "deno-slack-sdk/mod.ts";

const GoogleProvider = DefineOAuth2Provider({
  provider_key: "google",
  provider_type: Schema.providers.oauth2.CUSTOM,
  options: {
    "provider_name": "Google",
    "authorization_url": "https://accounts.google.com/o/oauth2/auth",
    "token_url": "https://oauth2.googleapis.com/token",
    "client_id": "",  // クライアントIDをここに設定
    "scope": [
      "https://www.googleapis.com/auth/spreadsheets",
      "https://www.googleapis.com/auth/userinfo.email",
    ],
    "authorization_url_extras": {
      "prompt": "consent",
      "access_type": "offline",
    },
    "identity_config": {
      "url": "https://www.googleapis.com/oauth2/v1/userinfo",
      "account_identifier": "$.email",
    },
  },
});

export default GoogleProvider;
```

**関数内でのトークン取得パターン**:
```typescript
// トークンIDをOAuth2型として入力パラメータに定義
input_parameters: {
  properties: {
    google_access_token_id: {
      type: Schema.slack.types.oauth2,
      oauth2_provider_key: "google",
    },
  },
}

// 関数内でトークンを取得して使用
const auth = await client.apiCall("apps.auth.external.get", {
  external_token_id: inputs.google_access_token_id,
});
if (!auth.ok) {
  return { error: `Failed to collect Google auth token: ${auth.error}` };
}

// トークンを使ってAPIを呼び出す
const response = await fetch("https://sheets.googleapis.com/v4/spreadsheets", {
  method: "POST",
  headers: {
    "Authorization": `Bearer ${auth.external_token}`,
  },
  body: JSON.stringify({ ... }),
});
```

**ワークフロー間でトークンIDを渡すパターン**:
- 関数の output_parameter としてトークンIDを渡すことが可能
- 別のワークフローのステップ入力として使用できる
- ただしその場合、型は `Schema.slack.types.oauth2` ではなく `Schema.types.string` として渡す

---

### 6. トラブルシューティング

**ソース**: `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`

ログは `slack activity` コマンドで確認可能。

| エラー | 説明 |
|---|---|
| `access_token_exchange_failed` | 設定した `token_url` からエラーが返された |
| `external_user_identity_not_found` | 設定した `account_identifier` がユーザーIDレスポンスに見つからない |
| `internal_error` | 内部システムエラー（継続的に発生する場合はSlackに連絡） |
| `invalid_identity_config_response` | `identity_config` の `url` が無効なレスポンスを返した |
| `invalid_token_response` | `token_url` が無効なレスポンスを返した |
| `missing_client_secret` | プロバイダーのクライアントシークレットが見つからない |
| `no_refresh_token` | 期限切れアクセストークンをリフレッシュするためのリフレッシュトークンが存在しない |
| `oauth2_callback_error` | OAuth2プロバイダーがエラーを返した |
| `oauth2_exchange_error` | 設定したプロバイダーからOAuth2トークンを取得中にエラーが発生 |
| `scope_mismatch_error` | プロバイダーに設定した `scope` に一致するOAuth2トークンが見つからない |
| `token_not_found` | このユーザーとプロバイダーのOAuth2トークンが見つからない |

---

### 7. サンプルプロジェクト（参考）

- [Timesheet approval app](https://github.com/slack-samples/deno-timesheet-approval): Google Sheetsにワークフロームで収集した情報を保存
- [Simple survey app](https://github.com/slack-samples/deno-simple-survey): Google Sheetsにアンケート回答を保存
- [GitHub functions repo](https://github.com/slack-samples/deno-github-functions): GitHubのIssue作成などをSlackから実行

---

## 判断・意思決定

- 調査対象を「Slack 外部認証」= OAuth2 を使ったワークフローアプリと外部サービスの統合機能に絞った
- Enterprise Search とは直接関係しない機能（Slack Connect の外部チーム招待、org migration イベントなど）は本調査の対象外とした
- Explore エージェントが検出した28ファイル中、コア機能に関連する9ファイルを詳細調査した

---

## 問題・疑問点

- 外部認証は **Deno Slack SDK（ワークフローアプリ）専用** の機能であり、通常の Bolt.js / Bolt-py アプリでは `apps.auth.external.get` API を直接呼び出す形になるが、`DefineOAuth2Provider` や `Schema.slack.types.oauth2` は使えない可能性がある（要確認）
- Enterprise Search（Web API ベース）との組み合わせでの外部認証利用については情報なし
