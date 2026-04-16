# Enterprise Search エンドユーザー有効化手順の詳細 — 調査ログ

## 調査ファイル一覧

- `docs/enterprise-search/enterprise-search-access-control.md`（再読）
- `docs/enterprise-search/connection-reporting.md`
- `docs/admins/managing-app-approvals.md`
- `docs/admins/managing-workflow-and-connector-permissions.md`
- `docs/reference/methods/admin.functions.permissions.set.md`
- `docs/reference/methods/admin.functions.permissions.lookup.md`
- `docs/reference/methods/admin.apps.config.set.md`
- `docs/reference/scopes/search.read.enterprise.md`
- `docs/tools/deno-slack-sdk/guides/controlling-permissions-for-admins.md`
- `docs/tools/deno-slack-sdk/guides/controlling-access-to-custom-functions.md`
- `docs/enterprise/developing-for-enterprise-orgs.md`
- Slack Help Center 記事: https://slack.com/help/articles/39044407124755-Set-up-and-manage-Slack-enterprise-search
  → **WebFetch 失敗（リダイレクト過多）**

## 調査アプローチ

1. 前回調査 (0022) のログ・kanban ファイルを再読し、未解決点を整理
2. `enterprise-search-access-control.md` を再読（内容は短い）
3. 開発者ドキュメント内で「エンドユーザー有効化」に関係しそうな API メソッド・権限系ドキュメントを横断調査
4. Slack Help Center の該当記事へ WebFetch でアクセスを試みたが、リダイレクト過多で失敗
5. Enterprise 関連の admin ドキュメント全件調査

---

## 調査結果

### 1. `docs/enterprise-search/enterprise-search-access-control.md` の全文

```
Source: https://docs.slack.dev/enterprise-search/enterprise-search-access-control

# End user access control

Even after apps that use Enterprise Search features are installed and configured at the org level,
they will not be available to end users by default.
Instead, your org admin will need to enable them for end users.
Refer to [this article](https://slack.com/help/articles/39044407124755-Set-up-and-manage-Slack-enterprise-search) for more details.

Once this access is enabled by your org admin, end users can search in Slack
and get results from those apps if the end users are members of the workspaces
which the apps are granted access to.

End users can also choose to disable any search apps in the following ways:
- by selecting Manage and then disabling the app
- by right-clicking the app on the sidebar and then selecting Disable
```

**重要な制約**:
- このページは「Org Admin が有効化操作を行う必要がある」という事実と、エンドユーザーが **無効化できる方法** だけを説明している
- Org Admin が有効化する具体的な手順は「詳細はこちらの記事を参照」として **外部ヘルプ記事にのみ記述** されている
- 外部ヘルプ記事（https://slack.com/help/articles/39044407124755）は **Slack Help Center** のページであり、開発者ドキュメントスナップショットには含まれていない
- WebFetch でのアクセスも試みたが「Too many redirects」エラーで取得不可（Slack Help Center は認証・リダイレクト処理が複雑なため）

---

### 2. `docs/enterprise-search/connection-reporting.md` — 接続状態の UI

エンドユーザーが「未接続」状態のときに表示される UI について：

```
1. When the user is not connected, they'll see the following:
   [User not connected UI]

2. Once they click Connect, your app receives a user_connection event with subtype: connect.
   This event contains a trigger_id, which is used to open a modal that allows the user
   to connect to your app.
   [Connect to app modal]

3. Once the user is connected, your app must report the connection status change to Slack
   by calling the apps.user.connection.update API method to update the UI.
   [User connected UI]
```

これは「接続報告（connection reporting）」機能で、Enterprise Search App の外部認証（OAuth 連携など）に関する UI フロー。エンドユーザーが Enterprise Search App に初めて接続するときに表示されるモーダルのこと。

→ これは Org Admin によるエンドユーザー有効化とは別の概念（ユーザー個別の外部認証接続フロー）

---

### 3. `docs/admins/managing-workflow-and-connector-permissions.md` — 関連 API メソッド

```
admin.functions.permissions.set: Sets the visibility of a Slack function and defines the users or workspaces
```

これは Workflow Builder のカスタム関数の公開範囲を設定するメソッド。  
`visibility` の選択肢: `everyone` / `app_collaborators` / `named_entities` / `no_one`

- Enterprise Search の「検索関数（search_function）」もカスタムステップ関数の一種
- もしかすると Org Admin が `admin.functions.permissions.set` を使って検索関数の `visibility` を `everyone` に設定することが「エンドユーザーへの有効化」に相当する可能性がある
- しかし、このメソッドの説明には Enterprise Search への言及がなく、これが Enterprise Search のエンドユーザー有効化の手段かどうかは **ドキュメントから確認できない**

---

### 4. `docs/reference/methods/admin.apps.config.set.md` — App 設定

```
workflow_auth_strategy: The workflow auth permission. Can be one of builder_choice or end_user_only.
rich_link_preview_type: Indicates the app-level override for rich link preview.
domain_restrictions: Domain restrictions for the app.
```

これは Org Admin が App の設定を変更する API。`workflow_auth_strategy` で認証戦略を設定できる。  
→ Enterprise Search のエンドユーザー有効化との直接的な関連は不明

---

### 5. `docs/reference/scopes/search.read.enterprise.md`

```
This scope allows apps using AI features to search content in third-party apps to help them answer user queries.
The user performing the search must have previously connected the app,
and the search will be performed using that user's credentials.
```

`search:read.enterprise` スコープ: AI 機能を使う App が Enterprise Search コンテンツを検索するためのスコープ。  
「ユーザーがアプリに接続済みである必要がある」という条件が明記されている。

---

### 6. `docs/enterprise/developing-for-enterprise-orgs.md` — Org Admin によるワークスペース追加

```
# Enable organization-wide installation

1. Navigate to OAuth & Permissions, add any bot scope (e.g., team:read)
2. In Org Level Apps section, select Opt-In → Yes, Opt-in
   → Reflected in app manifest as: "org_deploy_enabled": true
3. Private Distribution is now enabled
4. Add Org Admin user as a collaborator

Requesting to install the app to an organization means that an Org Admin will receive
a direct message from Slackbot to review the request.
```

ワークスペース追加の URL パターン:
```
https://app.slack.com/manage/ENTERPRISE_ID/integrations/profile/APP_ID/workspaces/add
```

→ このセクションはオーグへのインストール・ワークスペース追加の手順であり、エンドユーザーへの有効化の具体的手順ではない

---

## 結論：ドキュメントスナップショット内で確認できること・できないこと

### 確認できること（開発者ドキュメントに記載あり）

1. **エンドユーザー有効化の要否**:
   - オーグレベルへのインストール・ワークスペース追加後も、**デフォルトでエンドユーザーには非表示**
   - Org Admin が別途有効化操作を行う必要がある

2. **エンドユーザーが有効化されると何ができるか**:
   - Slack 内の検索でアプリの検索結果が表示される
   - 条件: エンドユーザーがアプリにアクセス許可があるワークスペースのメンバーであること

3. **エンドユーザーが個別に無効化する方法**:
   - サイドバーのアプリを右クリック → **Disable** を選択
   - **Manage** を選択 → アプリを無効化

4. **参照先**:
   - Slack Help Center 記事: https://slack.com/help/articles/39044407124755-Set-up-and-manage-Slack-enterprise-search

### 確認できないこと（外部ヘルプ記事に記載、本スナップショット外）

- **Org Admin がエンドユーザーへの有効化操作を行う具体的な手順**
  - 管理ダッシュボードのどこから操作するか
  - どのようなボタン・設定項目があるか
  - 個別ユーザーを指定するのか、全ユーザーに一括で有効化するのか

---

## 問題・疑問点

1. Slack Help Center の記事はウェブブラウザで直接アクセスする必要があるが、Slack の認証やリダイレクト設定によりスクレイピング・WebFetch が機能しない
2. `admin.functions.permissions.set` が Enterprise Search の検索関数に適用可能かどうかが不明
3. 「エンドユーザーへの有効化」が UI 操作（管理ダッシュボード）のみなのか、API 操作でも可能なのかが不明
