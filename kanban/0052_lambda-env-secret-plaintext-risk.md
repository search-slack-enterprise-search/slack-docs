# Lambda 環境変数への Secret 平文設定のリスクと代替手段

## 知りたいこと

0051の更問い。環境変数で渡しているがLambdaの場合IaCレベルで環境変数は平文になる。問題ないか？

## 目的

secretを平文で渡す必要が出てくる。問題ないかを知りたい。

## 調査サマリー

**Slack の公式見解: プロダクション環境では問題あり（非推奨）**

`docs/security.md` に明示的な記述:

> For production: Use a dedicated, industry-standard secrets management solution, such as **GitHub Actions Secrets, AWS Secrets Manager, or HashiCorp Vault**. These services securely inject sensitive tokens at build or runtime.

> You should never have an instance in which you are writing a token to disk in plaintext when there is a system keychain or other encryption mechanism available.

### IaC パターン別のリスク評価

| IaC パターン | リスク | 推奨との整合 |
|-------------|--------|------------|
| IaC テンプレートに平文ハードコード | 高 | 明確に NG |
| `${env:SLACK_SIGNING_SECRET}` でローカル/CI 環境変数から参照（値はリポジトリ外） | 中 | 許容範囲だが Lambda 環境変数に平文が残る |
| **AWS Secrets Manager から実行時取得** | 低 | **Slack が明示的に推奨** |

### 推奨対応

AWS Secrets Manager を使い、Lambda 実行時にコードで取得する:

```python
import boto3, json

secrets = json.loads(
    boto3.client("secretsmanager")
        .get_secret_value(SecretId="my-slack-app/secrets")["SecretString"]
)
app = App(
    token=secrets["SLACK_BOT_TOKEN"],
    signing_secret=secrets["SLACK_SIGNING_SECRET"]
)
```

### 補足

- Slack ドキュメントのサンプルコード自体は `export SLACK_SIGNING_SECRET=***` という簡易な形で示しているが、同じページの security.md でプロダクションは Secrets Manager 推奨と明記
- Signing Secret が漏洩した場合: Slack Console の "Regenerate" ボタンで再生成可能
- Signing Secret の漏洩リスク: 攻撃者が偽のリクエストを送り込める（Bot Token 漏洩とは異なり Slack API の直接操作はできない）

## 完了サマリー

Slack の `docs/security.md` はプロダクション環境でのシークレット管理に AWS Secrets Manager / HashiCorp Vault 等の専用ソリューションを明示的に推奨しており、Lambda 環境変数への平文保存はその原則に反する。IaC テンプレートに値を直書きすることは NG、CI の Secret Store から注入する形は許容範囲だが、最も安全な方法は Lambda 実行時に AWS Secrets Manager から取得すること。
