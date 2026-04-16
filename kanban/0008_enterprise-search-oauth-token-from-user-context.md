# Enterprise Search: user_context から外部認証 OAuth Token を取得する方法

## 知りたいこと

Enterprise Search において user_context を受け取った際に、外部認証機能の OAuth Token をどうやって取得したら良いのか。

## 目的

外部認証機能との連携を想定しているようだが、OAuth Token を取得しないと外部への認可を通せないため。

---

## 調査サマリー

### 結論: user_context と OAuth Token は別々の仕組み

`user_context` 自体には OAuth Token も Token ID も含まれない（`id` と `secret` のみ）。  
外部認証の OAuth Token は `Schema.slack.types.oauth2` 型の**別の入力パラメータ**として受け取る。

### OAuth Token 取得フロー

1. Manifest で `DefineOAuth2Provider` を使い OAuth2 Provider を定義（`provider_key` 指定）
2. CLI で `slack external-auth add-secret` → クライアントシークレットを登録
3. CLI で `slack external-auth add` → OAuth フロー実行。Slack が Token ID を生成・保存
4. Search Function の入力パラメータに `type: Schema.slack.types.oauth2`（`oauth2_provider_key` 指定）を追加
5. Workflow で `credential_source: "END_USER"` を指定 → Slack が検索実行ユーザーの Token ID を自動注入
6. Function 内で `client.apps.auth.external.get({ external_token_id: inputs.tokenId })` を呼び出し → 実際の OAuth アクセストークンを取得
7. 取得した `external_token` を `Authorization: Bearer` ヘッダーに使い外部 API を呼び出す

### 主要 API

- **`apps.auth.external.get`**: Token ID（`external_token_id`）からアクセストークンを取得
  - `POST https://slack.com/api/apps.auth.external.get`
  - レスポンス: `{ "ok": true, "external_token": "..." }`

### 主要ドキュメント

- `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`
- `docs/reference/methods/apps.auth.external.get.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`

---

## 完了サマリー

`user_context` から直接 OAuth Token を取得する仕組みは存在しない。  
`Schema.slack.types.oauth2` 型の入力パラメータに `credential_source: "END_USER"` を指定することで、Slack が検索実行ユーザーの Token ID を自動注入する。Function 内では `client.apps.auth.external.get` で Token ID を実際の OAuth アクセストークンに変換して外部 API 呼び出しに使用する。
