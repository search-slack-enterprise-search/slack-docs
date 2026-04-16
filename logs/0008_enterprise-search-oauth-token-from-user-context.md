# Enterprise Search: user_context から外部認証 OAuth Token を取得する方法

## 調査概要

- **タスクファイル**: `kanban/0008_enterprise-search-oauth-token-from-user-context.md`
- **調査日**: 2026-04-16
- **調査者**: Claude Code

---

## 調査したファイル一覧

1. `docs/enterprise-search/developing-apps-with-search-features.md`
2. `docs/tools/deno-slack-sdk/reference/slack-types.md`
3. `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`
4. `docs/reference/methods/apps.auth.external.get.md`
5. `docs/reference/methods/apps.auth.external.delete.md`
6. `docs/enterprise-search/connection-reporting.md`
7. `docs/reference/events/user_connection.md`
8. `docs/reference/methods/apps.user.connection.update.md`

---

## 調査アプローチ

1. Enterprise Search の user_context フィールド構造を確認（前回 kanban 0007 の知識を起点）
2. External Auth の仕組みをドキュメントで追跡
3. `apps.auth.external.get` API の詳細を確認
4. user_context と External Auth Token の連携方法を特定

---

## 調査結果

### 1. user_context の構造

**ファイル**: `docs/tools/deno-slack-sdk/reference/slack-types.md`（行 2652–2743）

`user_context` は型 `slack#/types/user_context` で、以下の2フィールドのみ持つ：

- `id` (string): 検索を実行したユーザーの `user_id`（例: `U123ABC456`）
- `secret` (string): Slack が `id` の真正性を内部検証するためのハッシュ。アプリ側は無視可能。

```
`id` - string
The `user_id` of the person to which the `user_context` belongs.

`secret` - string
A hash used internally by Slack to validate the authenticity of the `id` in the `user_context`. 
This can be safely ignored, since it's only used by us at Slack to avert malicious actors!
```

**重要**: `user_context` 自体には OAuth Token や Token ID は含まれない。

---

### 2. Enterprise Search での user_context の受け取り

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`（行 77–83, 198–203）

**search_function での受け取り**（行 79）:
> "Any additional input parameter with type `slack#/types/user_context`, regardless of its name, will be set to the `user_context` value of the user executing the search."

型 `slack#/types/user_context` の入力パラメータを定義するだけで、検索実行ユーザーの user_context が自動注入される。

**search_filters_function での受け取り**（行 198–199）:
> "Any input parameter with type `slack#/types/user_context` regardless of their field will be set to the `user_context` value of the user executing the search"

---

### 3. External Auth の仕組み

**ファイル**: `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`

#### OAuth2 Provider の定義（行 31–40）

```typescript
const GoogleProvider = DefineOAuth2Provider({
  provider_key: "google",
  provider_type: Schema.providers.oauth2.CUSTOM,
  options: {
    provider_name: "Google",
    authorization_url: "https://accounts.google.com/o/oauth2/auth",
    token_url: "https://oauth2.googleapis.com/token",
    client_id: "<your_client_id>.apps.googleusercontent.com",
    scope: [
      "https://www.googleapis.com/auth/spreadsheets.readonly",
      "https://www.googleapis.com/auth/userinfo.email",
      "https://www.googleapis.com/auth/userinfo.profile",
    ],
  },
});
```

#### Token の登録・保存フロー（行 223–275）

1. `slack external-auth add-secret` でクライアントシークレットを登録
2. `slack external-auth add` で OAuth フローを実行
3. ブラウザで `oauth2.slack.com` 上のフローを完了
4. Slack が Token を暗号化して保存し、Token ID を生成

#### Function での OAuth2 Token 受け取り方（行 279–303）

`Schema.slack.types.oauth2` 型の入力パラメータを定義し、`oauth2_provider_key` を指定する：

```typescript
export const SampleFunctionDefinition = DefineFunction({
  callback_id: "sample_function",
  title: "Sample Function",
  source_file: "functions/sample_function.ts",
  input_parameters: {
    properties: {
      googleAccessTokenId: {
        type: Schema.slack.types.oauth2,
        oauth2_provider_key: "google",
      },
    },
    required: ["googleAccessTokenId"],
  },
});
```

#### Workflow での credential_source 指定（行 291–317）

**END_USER モード**:
```typescript
const sampleFunctionStep = SampleWorkflow.addStep(SampleFunctionDefinition, {
  googleAccessTokenId: {
    credential_source: "END_USER",  // 検索実行ユーザーのトークン
  },
});
```
- ワークフローを実行するエンドユーザーのアカウントを使用
- Link Trigger からのみ開始可能（ユーザーインタラクション必須）
- ユーザーは実行前に外部サービスへの認証が必要

**DEVELOPER モード**:
```typescript
const sampleFunctionStep = SampleWorkflow.addStep(SampleFunctionDefinition, {
  googleAccessTokenId: {
    credential_source: "DEVELOPER",  // 開発者のトークン
  },
});
```
- アプリの協力者アカウントを使用
- `slack external-auth select-auth` で特定のアカウントを選択

---

### 4. apps.auth.external.get API

**ファイル**: `docs/reference/methods/apps.auth.external.get.md`（行 9–82）

**概要**: Token ID から実際のアクセストークンを取得する API

**エンドポイント**:
```
POST https://slack.com/api/apps.auth.external.get
```

**必須引数**:
- `token`: 認証トークン（アプリのボットトークン等）
- `external_token_id`: 取得対象のトークン ID

**オプション引数**:
- `force_refresh` (boolean): 有効期限切れでなくてもトークンをリフレッシュするかどうか

**レスポンス例（成功）**:
```json
{
  "ok": true,
  "external_token": "00D3j00000025Zh!AQ4AQMAl46qme3wdZiKo5j3WHcJu..."
}
```

**レスポンス例（エラー）**:
```json
{
  "ok": false,
  "error": "token_not_found"
}
```

**実装例**（行 81–82）:
```typescript
const auth = await client.apps.auth.external.get({
  external_token_id: inputs.reactor_access_token_id,
});
if (!auth.ok) {
  return { error: `Failed to collect Google auth token: ${auth.error}` };
}
```

---

### 5. Function 内での実際の Token 取得実装

**ファイル**: `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`（行 286–287）

```typescript
export default SlackFunction(
  SampleFunctionDefinition,
  async ({ inputs, client }) => {
    // Token ID を使用して実際のアクセストークンを取得
    const tokenResponse = await client.apps.auth.external.get({
      external_token_id: inputs.googleAccessTokenId,  // Slack が注入した Token ID
    });
    if (tokenResponse.error) {
      return { error: `Failed to retrieve token: ${tokenResponse.error}` };
    }
    // 実際のアクセストークン
    const externalToken = tokenResponse.external_token;
    // 外部 API へのリクエスト
    const response = await fetch("https://somewhere.tld/myendpoint", {
      headers: {
        "Authorization": `Bearer ${externalToken}`,
      },
    });
  },
);
```

---

### 6. user_context と External Auth の連携: 全体像

#### 結論: user_context と OAuth Token は別々の仕組み

`user_context` 自体には OAuth Token も Token ID も含まれない。  
External Auth の OAuth Token は `Schema.slack.types.oauth2` 型の別の入力パラメータとして受け取る。

#### 両者を同時に使う Search Function の構成例

```typescript
export const SearchFunctionDefinition = DefineFunction({
  callback_id: "search_results",
  title: "Get Search Results",
  source_file: "functions/search.ts",
  input_parameters: {
    properties: {
      query: {
        type: Schema.types.string,
      },
      // user_context: 検索ユーザーの識別情報
      requester: {
        type: Schema.slack.types.user_context,
      },
      // External Auth Token ID: OAuth Token を取得するための ID
      externalServiceTokenId: {
        type: Schema.slack.types.oauth2,
        oauth2_provider_key: "custom_service",
      },
    },
    required: ["query"],
  },
  output_parameters: {
    properties: {
      search_results: {
        type: "slack#/types/search_results",
      },
    },
    required: ["search_results"],
  },
});
```

Workflow 側での設定:
```typescript
const searchStep = SearchWorkflow.addStep(SearchFunctionDefinition, {
  query: SearchWorkflow.inputs.query,
  requester: SearchWorkflow.inputs.user,  // user_context の注入
  externalServiceTokenId: {
    credential_source: "END_USER",  // 検索ユーザーの OAuth Token を使用
  },
});
```

Function 実装:
```typescript
export default SlackFunction(
  SearchFunctionDefinition,
  async ({ inputs, client }) => {
    // user_context からユーザー ID を取得
    const userId = inputs.requester.id;

    // Token ID から実際の OAuth Token を取得
    const tokenResponse = await client.apps.auth.external.get({
      external_token_id: inputs.externalServiceTokenId,
    });
    if (!tokenResponse.ok) {
      return { error: `Failed to retrieve OAuth token: ${tokenResponse.error}` };
    }
    const oauthToken = tokenResponse.external_token;

    // 外部サービスへ認可付きリクエスト
    const searchResponse = await fetch(`https://external-service.example.com/search?q=${inputs.query}`, {
      headers: {
        "Authorization": `Bearer ${oauthToken}`,
        "X-User-Id": userId,
      },
    });
    // ...
  },
);
```

---

### 7. Connection Reporting との関連

**ファイル**: `docs/enterprise-search/connection-reporting.md`, `docs/reference/events/user_connection.md`, `docs/reference/methods/apps.user.connection.update.md`

Enterprise Search では、ユーザーが外部サービスに接続状態を管理するための Connection Reporting 機能がある。

フロー:
1. `user_connection` イベント（subtype: `connect`）が発火
2. アプリが接続フロー（OAuth）を処理
3. `apps.user.connection.update` で Slack に接続状態を報告
4. 以降、search_function 呼び出し時に credential_source: "END_USER" で Token が自動注入される

---

## 未解決の疑問点

1. **user_context.secret のアプリへの用途**: ドキュメントでは「Slack が内部検証に使用」とあり、アプリ側は無視可能とされているが、実際に活用できるシナリオがあるかは不明。

2. **END_USER credential_source の Enterprise Search での制限**: Enterprise Search の search_function で `credential_source: "END_USER"` を使用する際、Link Trigger 以外のトリガータイプ（Enterprise Search 専用のトリガー）での動作についてはドキュメントに明記されていない。

3. **Token ID 自動注入の内部メカニズム**: Slack が credential_source から正しい Token ID を決定・注入する内部メカニズムの詳細は不明。

4. **user_context.id と Token の対応関係**: END_USER モードで、user_context.id のユーザーと注入される Token の保有者が一致することが期待されるが、ドキュメントには明示的な記述がない。

---

## まとめ

### OAuth Token 取得フロー（完全版）

1. **Manifest で OAuth2 Provider を定義** → `provider_key` を指定
2. **CLI でクライアントシークレットを登録** → `slack external-auth add-secret`
3. **CLI で Token を生成** → `slack external-auth add` で OAuth フローを実行、Slack が Token ID を生成・保存
4. **Search Function 定義に `oauth2` 型入力パラメータを追加** → `oauth2_provider_key` を指定
5. **Workflow で `credential_source` を指定** → Slack が検索ユーザーの Token ID を自動注入
6. **Function 内で `client.apps.auth.external.get` を呼び出し** → Token ID から実際の OAuth アクセストークンを取得
7. **外部 API への認可リクエスト** → `Bearer ${externalToken}` で実行

### 重要な結論

- `user_context` には OAuth Token は含まれない（`id` と `secret` のみ）
- OAuth Token は `Schema.slack.types.oauth2` 型の別パラメータとして受け取る
- `credential_source: "END_USER"` を指定することで、検索実行ユーザーの OAuth Token が自動注入される
- Function 内では `apps.auth.external.get` を呼び出して実際のアクセストークンを取得する
