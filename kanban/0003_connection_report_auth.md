# connection reportで表示される認証状態とは何か？
## 知りたいこと

connection reportでは認証状態が表示されると `kanban/0002_what_connection_report.md` で回答されたが、Enterprise Searchにおいてそもそもユーザーは認証していないですよね？
何との認証状態を表示しているのですか？

## プラン

### 調査結果の要約

Connection Report の「認証状態」= **ユーザーが Enterprise Search アプリが統合する「外部データソース（外部サービス）」に認証しているかどうか**。

- Slack への認証（Slack ログイン）は全員済みの前提 → Connection Report とは無関係
- Enterprise Search アプリが統合する先の**外部サービス**（社内 Wiki・Google Drive・独自システムなど）への認証が別途ユーザーごとに必要
- 各ユーザーが異なる外部サービスアカウントを持つため、接続状態はユーザーごとに異なる

### 核心的な証拠

1. **`docs/enterprise-search/developing-apps-with-search-features.md`**
   - エラーメッセージ例: *"Authentication Required: Please visit https://getauthhere.slack.dev to authenticate your account."*
   - ユーザーが外部サービスに未認証の場合、検索が失敗し「Authentication Required」を返す
   - Connection Report のフロー（Connect → モーダル → 外部認証）がこのエラーへの解決策

2. **`docs/enterprise-search/connection-reporting.md`**
   - 「Connect」クリック後のモーダルは「allows the user to connect to your app（外部アプリへの接続を案内）」
   - 「認証状態（authentication status）」＝「接続状態（connection status）」は外部サービスへのログイン状態

3. **`docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`**
   - Slack は OAuth2 ベースの「外部認証システム」を提供
   - ユーザーごとに外部サービスのトークンを暗号化して保管・管理

### 具体例

Enterprise Search アプリが「社内 Wiki」を統合している場合：
- 社員Aが社内 Wiki に認証済み → **connected**（検索結果を返せる）
- 社員Bが社内 Wiki に未認証 → **disconnected**（検索すると「Authentication Required」エラー）
- 社員Bが「Connect」をクリック → モーダルで社内 Wiki の認証ページへ誘導 → 認証 → `connected`

### 調査対象ドキュメント

- `docs/enterprise-search/connection-reporting.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`
- `docs/reference/methods/apps.auth.external.get.md`
- `docs/reference/methods/apps.auth.external.delete.md`
- `docs/reference/events/user_connection.md`
- `docs/reference/methods/apps.user.connection.update.md`

### 成果物

- ログファイル（`logs/0003_connection_report_auth.md`）に調査結果の詳細を記録
- kanban ファイルに完了サマリーを追記

---

## 完了サマリー

- **完了日時**: 2026-04-16T14:24:00+09:00
- **ログファイル**: `logs/0003_connection_report_auth.md`

### Connection Report の「認証状態」= 外部データソースへの認証

Enterprise Search の Connection Report が示す「認証状態」は、**Slack への認証ではなく、Enterprise Search アプリが統合する外部データソース（外部サービス）へのユーザー個人の認証状態**を指す。

| 認証の種類 | 対象 | Connection Report との関係 |
|-----------|------|--------------------------|
| Slack への認証 | Slack | 全員済みの前提、Connection Report とは無関係 |
| **外部データソースへの認証** | **社内 Wiki・Google Drive・独自システムなど** | **Connection Report が示す認証状態** |

### なぜユーザーごとに認証状態が異なるのか

- 各ユーザーが**独自の外部サービスアカウント**（社内 Wiki のアカウントなど）を持つ
- Slack の「外部認証（External Authentication）」システムが OAuth2 でユーザーごとのトークンを暗号化保管
- ユーザーAは認証済み（connected）、ユーザーBは未認証（disconnected）といった状態が共存する

### 未認証時の動作

ユーザーが外部サービスに未認証のまま検索すると、アプリは `functions.completeError` で以下のようなエラーを返す：
> *Authentication Required: Please visit https://getauthhere.slack.dev to authenticate your account.*

Connection Report の「Connect」ボタンは、このエラーを解消するための認証フローへの入口となる。

### 参照ドキュメント

- `docs/enterprise-search/connection-reporting.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`
- `docs/reference/methods/apps.auth.external.get.md`
- `docs/reference/methods/apps.auth.external.delete.md`
