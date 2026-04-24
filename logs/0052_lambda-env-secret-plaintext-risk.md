# Lambda 環境変数への Secret 平文設定のリスクと代替手段 — 調査ログ

## 調査アプローチ

- `docs/security.md` を通読（シークレット管理のベストプラクティス節に注目）
- `docs/app-management/hosting-slack-apps.md` を確認（AWS Lambda 言及を確認）
- `docs/tools/bolt-js/deployments/aws-lambda.md` の serverless.yml 例を再確認（IaC でのシークレット参照パターン）
- キーワード `secret.manager`, `secrets.manager`, `parameter.store`, `SSM`, `plaintext`, `平文` で docs/ 全体を rg 検索 → 該当なし（Slack ドキュメントは AWS 固有の実装詳細を扱わない）
- キーワード `env.*variable`, `environment.variable`, `.env` で検索 → 直接の記述なし

---

## 調査ファイル一覧

- `docs/security.md`
- `docs/app-management/hosting-slack-apps.md`
- `docs/tools/bolt-js/deployments/aws-lambda.md`（0051 調査時から参照継続）

---

## 調査結果

### 1. Slack 公式の秘密情報管理ポリシー

**ファイル**: `docs/security.md`

#### セクション: Securely manage credentials and secrets（行 13〜22）

> Your app's tokens, keys, and credentials are highly sensitive. Never hardcode them directly into your application's source code or store them in non-secure locations, like in public repositories.
>
> * For development: Use local environment variables (`.env` files) to store secrets. Ensure your `.gitignore` file includes `.env` to prevent accidental commits.
> * **For production: Use a dedicated, industry-standard secrets management solution, such as GitHub Actions Secrets, AWS Secrets Manager, or HashiCorp Vault. These services securely inject sensitive tokens at build or runtime.**
> * Client Secret: Your client secret is used to securely identify your app's rights when exchanging tokens with Slack. Do not distribute client secrets in email, distributed native apps, client-side JavaScript, or public code repositories.
> * Bot and user tokens: Store all bot and user tokens with care, and never place them in a public code repository or client-side code.

#### セクション: Network, data link, and physical layers（行 235〜242）

> * If your app is not web-based, ensure that you are using recommendations for the platform it's running on for how to store secrets. **You should never have an instance in which you are writing a token to disk in plaintext when there is a system keychain or other encryption mechanism available.**

#### セクション: Application and presentation layers（行 209〜218）

> * Use a database to store tokens, and do not hard-code any tokens.

---

### 2. IaC（Serverless Framework）での環境変数参照パターン

**ファイル**: `docs/tools/bolt-js/deployments/aws-lambda.md`（行 133〜138）

Serverless Framework の serverless.yml における環境変数設定例:

```yaml
service: serverless-bolt-js
frameworkVersion: "4"
provider:
  name: aws
  runtime: nodejs22.x
  environment:
    SLACK_SIGNING_SECRET: ${env:SLACK_SIGNING_SECRET}   # ← ローカル環境変数から参照
    SLACK_BOT_TOKEN: ${env:SLACK_BOT_TOKEN}
functions:
  slack:
    handler: app.handler
    events:
      - http:
          path: slack/events
          method: post
```

ドキュメントのノート:

> `SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN` must be environment variables on your local machine.

この構成では:
- serverless.yml 自体には平文のシークレット値は含まれない
- デプロイ時にローカル環境変数 or CI の Secret Store から値が注入される
- ただし、デプロイ後に Lambda の環境変数として AWS Console 上で可視になる

---

### 3. 問いに対する分析

ユーザーの懸念は「IaC レベルで環境変数は平文になる」という点。これには 2 つの問題が含まれる。

#### 問題 A: IaC テンプレート（serverless.yml / CloudFormation / CDK）に平文シークレットが含まれる

**Slack ドキュメントの立場**:
- ソースコードにハードコードしてはいけない（明示的に禁止）
- 公開リポジトリや非セキュアな場所に保存してはいけない

**評価**: IaC テンプレートに `SLACK_SIGNING_SECRET: "abc123"` と直書きする行為は Slack の推奨に反する。

#### 問題 B: Lambda 環境変数自体の平文可視性

Lambda の環境変数は:
- AWS KMS によってデフォルトで暗号化されているが、**AWS Console 上では平文で表示される**
- CloudFormation のスタック設定でも参照可能
- CloudWatch Logs の関連情報から漏洩するリスクがある

**Slack ドキュメントの立場**:
> For production: Use a dedicated, industry-standard secrets management solution, such as **AWS Secrets Manager**

明示的に AWS Secrets Manager を推奨しており、Lambda の環境変数のみへの依存は「より安全な代替手段がある場合に平文を使うべきでない」という原則に照らして非推奨と解釈できる。

---

### 4. 推奨される代替手段（Slack ドキュメントが言及しているもの）

| 手段 | Slack ドキュメント言及 | 内容 |
|------|---------------------|------|
| AWS Secrets Manager | 明示的に推奨（`docs/security.md`） | 実行時にコードから取得。Lambda 環境変数に平文が残らない |
| GitHub Actions Secrets | 明示的に推奨（`docs/security.md`） | CI/CD パイプラインでのシークレット注入 |
| HashiCorp Vault | 明示的に推奨（`docs/security.md`） | 自前のシークレット管理基盤 |

---

### 5. Signing Secret の位置づけ

Signing Secret（署名検証シークレット）は OAuth トークン（Bot Token 等）とは性質が異なる:
- **Signing Secret**: Slack からのリクエストが本物かを検証するための HMAC キー。漏洩した場合、攻撃者が偽のリクエストを送り込める
- **Bot Token (xoxb)**: Slack API を呼び出すための認証情報。漏洩した場合、攻撃者が Bot として Slack 操作できる

どちらも機密情報だが、Signing Secret の漏洩は「なりすましリクエストの送り込み」というリスクに限定される。Slack ドキュメントでは両者とも同等に保護すべき情報として扱っている（`docs/security.md` は区別していない）。

---

## まとめ・回答

### 「IaC で環境変数が平文になるのは問題か？」

**Slack の公式見解: 問題あり（プロダクションでは非推奨）**

`docs/security.md` の明示的な推奨:
- プロダクション環境: **AWS Secrets Manager, GitHub Actions Secrets, HashiCorp Vault** を使用する
- トークン・シークレットは暗号化の仕組みが使えるときに平文で保存してはいけない

具体的なリスクレベル（IaC パターン別）:

| IaC パターン | リスクレベル | Slack 推奨との整合性 |
|-------------|------------|-------------------|
| IaC テンプレートに平文ハードコード | 高 | 明確に NG |
| `${env:SLACK_SIGNING_SECRET}` でローカル env 参照（値はリポジトリに含まれない） | 中 | 許容範囲だが Lambda env vars に平文残る |
| CI/CD の Secret Store から注入 | 中 | 許容範囲（GitHub Actions Secrets は推奨リストに含まれる） |
| **AWS Secrets Manager から実行時取得** | 低 | **推奨** |

### 推奨対応

Slack ドキュメントが明示的に推奨する AWS Secrets Manager を使い、Lambda 実行時にコードで取得する:

```python
import boto3
import json

def get_secret(secret_name):
    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])

secrets = get_secret("my-slack-app/secrets")
app = App(
    token=secrets["SLACK_BOT_TOKEN"],
    signing_secret=secrets["SLACK_SIGNING_SECRET"]
)
```

こうすることで:
- IaC テンプレートに平文が含まれない
- Lambda の環境変数にも平文が残らない
- Slack の推奨（AWS Secrets Manager）に準拠

---

## 問題・疑問点

- Slack ドキュメント自体は Bolt の Lambda 例（`lazy-listeners.md`）で `export SLACK_SIGNING_SECRET=***` のようなシェルへのベタ設定を示しており、AWS Secrets Manager 統合のサンプルは提供されていない。ドキュメントとサンプルコードの間に若干のギャップがある
- Slack ドキュメントは AWS 固有の実装詳細（KMS 暗号化の有効化、SSM Parameter Store の使い方など）には踏み込んでいない。より具体的な AWS Lambda でのシークレット管理は AWS ドキュメントを別途参照する必要がある
- Signing Secret は定期的に再生成可能（Slack Console の "Regenerate" ボタン）。漏洩した場合の対処は再生成すること
