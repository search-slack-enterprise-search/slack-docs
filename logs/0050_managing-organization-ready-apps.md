# Managing Organization-Ready Apps 調査ログ

## 調査ファイル一覧

- `docs/enterprise/organization-ready-apps.md`（主要ドキュメント）
- `docs/enterprise/index.md`（Enterprise Organizations 概要）
- `docs/enterprise/developing-for-enterprise-orgs.md`（開発者向け Enterprise org 対応ガイド）
- `docs/enterprise/migrating-to-organization-wide-deployment.md`（既存アプリのオーグ対応移行ガイド）
- `docs/enterprise-search/index.md`（Enterprise Search 概要・org-ready 要件確認）

## 調査アプローチ

1. `organization-ready` / `org-ready` / `org_deploy_enabled` をキーワードに全 docs を Grep
2. `docs/enterprise/organization-ready-apps.md` が主要ドキュメントと判明
3. Enterprise Search との関連を `docs/enterprise-search/index.md` と `docs/enterprise-search/developing-apps-with-search-features.md` で確認

---

## 調査結果

### 1. `docs/enterprise/organization-ready-apps.md` — 主要ドキュメント

#### org-ready アプリのメリット（管理者視点）

- **Org Admin** がアプリを全ワークスペースに配布、または特定ワークスペースへのアクセスを制限できる
- 事前承認済みアプリをワークスペース作成時に自動インストール可能
- ユーザーは全ワークスペースで**1度だけ認証**すればよい（シングルサインオン的な体験）

**重要な注意点**: Organization-ready アプリはオーグレベルでインストールされるが、**ワークスペースには自動追加されない**。Org Admin が後から個別に追加する必要がある。また、オーグレベルでインストールされてもワークスペースレベルのアプリと比べて**追加の権限はない**。

#### org-ready が必須となるケース

- **Workflow Builder のカスタムステップ**を含むアプリ → opt-in が必要
- **Deno ベースのアプリ** → 自動的に org-ready（Slack ホスト型）

#### インストール方法（3種類）

| 方法 | トークン生成 |
|------|------------|
| app settings (UI) | 自動生成 |
| OAuth フロー | ハンドシェイク成功で生成 |
| Slack CLI | - |

どのインストール方法でも org-wide トークンの動作は同じ。

#### ワークスペースへの追加手順（管理者向け）

1. 管理者として admin ダッシュボード（`app.slack.com/manage/<enterprise-id>`）に移動
2. 左サイドバーの **Integrations** → **Installed apps** をクリック
3. 追加したいアプリの「…」→ **Add to more workspaces** を選択
4. ワークスペースを選択 → **Next** → 権限を確認 → **Add App**

---

### 2. `docs/enterprise/developing-for-enterprise-orgs.md` — 開発者向け対応ガイド

#### org-ready 化の手順（開発者）

1. **OAuth & Permissions** で Bot スコープ追加（例: `team:read`）— Bot スコープがないと次ステップが表示されない
2. **Org Level Apps** セクションで **Opt-In** → **Yes, Opt-in** を確認
3. manifest.json への反映:
   ```json
   "settings": {
       "org_deploy_enabled": true,
       ...
   }
   ```
4. コラボレーターに Org Admin ユーザーを追加
5. インストールリクエストが Org Admin に Slackbot DM で届く → Admin が承認・インストール後にワークスペースに追加

#### OAuth フロー時の判別方法

`oauth.v2.access` レスポンスの `is_enterprise_install` フィールドで org インストールを判別：

```json
{
    "ok": true,
    "access_token": "xoxb-XXXX",
    "token_type": "bot",
    "is_enterprise_install": true,
    "team": null,
    "enterprise": {
        "id": "E123ABC456",
        "name": "Jesse Slacksalot"
    }
}
```

- `team` が `null` で `enterprise` オブジェクトが存在 → org インストール
- OAuth 完了後、まだどのワークスペースにも追加されていないため、Admin をワークスペース追加モーダルにリダイレクトすることを推奨:
  ```
  https://app.slack.com/manage/ENTERPRISE_ID/integrations/profile/APP_ID/workspaces/add
  ```

#### API 利用時の注意（`team_id` パラメータ）

org トークンは複数ワークスペースを表すため、一部の API メソッドは `team_id` が必須となる:

- `conversations.create`, `conversations.list`
- `users.list`, `users.conversations`
- `search.all`, `search.files`, `search.messages`
- `team.accessLogs`, `team.billableInfo` など（全 21 メソッド）

`team_id` を常に渡す実装が安全（単一ワークスペーストークンでは受け入れられるが無視される）。

#### ワークスペースアクセス変更の追跡

以下の Events API イベントで org-ready アプリがワークスペースへのアクセスを得た/失ったことを把握できる:
- `team_access_granted` — ワークスペースへのアクセス付与
- `team_access_revoked` — ワークスペースへのアクセス失効

`auth.teams.list` API メソッドでアプリが承認されたワークスペースの一覧を取得できる。

#### Events API での `authorizations` フィールド

イベントペイロードの `authorizations` オブジェクトに `is_enterprise_install` が含まれる:
```json
"authorizations": [
    {
        "enterprise_id": "E324567",
        "team_id": "T423567",
        "user_id": "W43567",
        "is_bot": false,
        "is_enterprise_install": true
    }
]
```

#### Enterprise org アプリのインストール形態（3種類）

1. **ワークスペースレベルのインストール** — Workflow Builder カスタムステップ非対応アプリ向け
2. **org-ready アプリのオーグレベルインストール** — Workflow Builder カスタムステップ対応の唯一の選択肢
3. **オーグレベルインストール（admin 型）** — 管理系・DLP 型アプリ向け

---

### 3. `docs/enterprise/migrating-to-organization-wide-deployment.md` — 移行ガイド

#### 既存アプリを org-ready に移行する手順

1. app settings の **Org Level Apps** セクションで **Opt-in** → 完了

#### Bolt フレームワークの必要バージョン

| Bolt フレームワーク | 必要バージョン |
|--------------------|--------------|
| Bolt for JavaScript | 3.0.0+ |
| Bolt for Python | 1.1.0+ |
| Bolt for Java | 1.4.0+ |

#### トークン管理の変更点

- org インストール後は**単一の org-wide ボットトークン**で複数ワークスペースを操作
- 既存のワークスペーストークンも継続して動作
- org-wide ボットトークンは既存インストール済みワークスペースにも有効
- DB スキーマ変更の選択肢:
  1. トークンとインストールを1対多にする（org-wide トークン1つに複数インストール）
  2. 既存の1対1のまま `enterprise_id` をソートキーとして使用

#### スコープの継承

org インストール時に設定されたスコープが個別ワークスペースのインストールに引き継がれる。個別ワークスペースの OAuth リダイレクト時に異なるスコープを渡しても、org インストール時のスコープのみ受け取る。

---

### 4. `docs/enterprise-search/index.md` — Enterprise Search と org-ready の関連

```
Your app must opt in to org-ready apps

Your app must be installed on your org and granted access to one or more workspaces to enable support for Enterprise Search. Refer to managing organization-ready apps for more details.
```

Enterprise Search アプリは必ず org-ready である必要がある。`org_deploy_enabled: true` が manifest.json に設定されていることが確認できた（`developing-apps-with-search-features.md` より）:

```json
"settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
        "bot_events": [
            "function_executed",
            "entity_details_requested"
        ]
    },
    "app_type": "remote",
    "function_runtime": "remote"
}
```

---

## Enterprise Search 文脈での重要ポイント

1. **必須要件**: Enterprise Search アプリは `org_deploy_enabled: true` で org-ready でなければならない
2. **インストール手順**: Org Admin がオーグレベルでインストール → 対象ワークスペースに個別追加が必要
3. **Bolt バージョン**: Python の場合 1.1.0+ が必要
4. **API 呼び出し時**: org トークンを使う場合は `team_id` パラメータが必要なメソッドに注意
5. **ワークスペース管理**: `team_access_granted` / `team_access_revoked` イベントと `auth.teams.list` でワークスペースアクセスを管理

---

## 問題・疑問点

- Enterprise Search アプリの場合、OAuth フローを使うことはあるか？（通常は Internal App として Opt-In のみで完結すると想定）
- `team_access_granted` イベントは Enterprise Search アプリでも使えるか？（関数ベースのルーティングとの兼ね合い）
