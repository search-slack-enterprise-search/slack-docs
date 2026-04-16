# Enterprise Search エンドユーザー有効化手順の詳細

## 知りたいこと

0022番への更問いです。エンドユーザーへの有効化の方法について詳しく教えてください

## 目的

エンドユーザーへの有効化が必要そうというのはわかっていたのでその手段を知りたかった。前回はその指示が明確でなかったため詳しい手順を今回は聞きたい。

## 調査サマリー

### 開発者ドキュメントに記載されている内容

`docs/enterprise-search/enterprise-search-access-control.md` には以下の情報がある：

- オーグレベルへのインストール・ワークスペース追加後も、**デフォルトでエンドユーザーには非表示**
- Org Admin が別途有効化操作を行う必要があるが、**具体的な手順は外部 Slack Help Center 記事に委ねられている**
- 参照先: https://slack.com/help/articles/39044407124755-Set-up-and-manage-Slack-enterprise-search

有効化後のエンドユーザーの状態：
- Slack 内の検索でアプリの検索結果が表示される（条件：アプリがアクセス許可されたワークスペースのメンバーであること）
- エンドユーザーは個別に無効化もできる（サイドバー右クリック → Disable、または Manage から無効化）

### 確認できなかった内容

- **Org Admin がエンドユーザーへの有効化操作を行う具体的な手順**は、開発者ドキュメントスナップショット内には存在しない
- Slack Help Center 記事（https://slack.com/help/articles/39044407124755）にのみ記載されているが、WebFetch でのアクセスも失敗（リダイレクト過多）

### 類似機能として参照した API（直接関係するかは不明）

- `admin.functions.permissions.set`: Workflow Builder のカスタム関数の公開範囲（everyone / named_entities 等）を設定する API。Enterprise Search の検索関数が対象になる可能性があるが、ドキュメントでの確認不可。

## 完了サマリー

**調査結果**: エンドユーザーへの有効化手順の詳細は、開発者ドキュメントスナップショット内に存在しない。

ドキュメントには「Org Admin が有効化する必要がある」という事実と、エンドユーザー側の無効化方法のみ記載。具体的な Org Admin の操作手順は Slack Help Center 記事にのみ掲載されており、そのページは認証が必要なため WebFetch でも取得不可。

**ユーザーへの案内**: https://slack.com/help/articles/39044407124755-Set-up-and-manage-Slack-enterprise-search を直接ブラウザで閲覧する必要がある（Slack 管理者権限でログインした状態でアクセスすることを推奨）。

ログ: `logs/0024_enterprise-search-end-user-activation.md`
