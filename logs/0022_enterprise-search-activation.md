# Enterprise Search 有効化方法 — 調査ログ

## 調査ファイル一覧

- `docs/enterprise-search/index.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/enterprise-search-access-control.md`
- `docs/enterprise/organization-ready-apps.md`
- `docs/apis/web-api/real-time-search-api.md`

## 調査アプローチ

1. `docs/enterprise-search/` 以下のドキュメントを全件読み込み
2. `docs/enterprise/organization-ready-apps.md` を参照（index.md からリンクされていたため）
3. Grep で "enable.*search"、"admin.*enable" 等のキーワードで横断検索
4. `docs/admins/` 以下に Enterprise Search 関連の記述がないか確認（なし）

---

## 調査結果

### 1. `docs/enterprise-search/index.md` — Enterprise Search 概要

```
Source: https://docs.slack.dev/enterprise-search

Your app must opt in to org-ready apps

Your app must be installed on your org and granted access to one or more workspaces
to enable support for Enterprise Search.
Refer to managing organization-ready apps for more details.
```

- Enterprise Search を有効にするには、App が **org-ready（オーグ対応）** である必要がある
- さらに App を **オーグにインストール**し、**1つ以上のワークスペースにアクセス許可を付与**する必要がある
- Enterprise Search を含む App は Slack Marketplace への公開・配布不可

---

### 2. `docs/enterprise-search/developing-apps-with-search-features.md` — 開発者向け設定

#### App マニフェストへの `search` オブジェクト追加

```json
..."features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```

| フィールド | 説明 | 必須 |
|---|---|---|
| `search_function_callback_id` | 検索結果を返すカスタムステップ関数の `callback_id` | 必須 |
| `search_filters_function_callback_id` | 検索フィルターを返す関数の `callback_id` | 任意 |

#### App マニフェストの settings 設定

```json
...  "settings": {
      "org_deploy_enabled": true,
      "event_subscriptions": {
          "bot_events": [
              ...
              "function_executed",
              "entity_details_requested"
          ]
      },
      "app_type": "remote",
      "function_runtime": "remote"
  }
```

- `org_deploy_enabled: true` が必須（オーグ対応宣言）
- `function_executed` イベントの購読が必須
- `app_type: "remote"` と `function_runtime: "remote"` も必要

#### 既存カスタムステップがある場合のショートカット

> If you already have a custom step for returning search results in your Slack app, you can use the **Search Apps** view within app settings to configure your app as a search app.

App の設定画面内の「Search Apps」ビューから、既存のカスタムステップを検索 App として設定することもできる（マニフェスト手書き不要）。

---

### 3. `docs/enterprise-search/enterprise-search-access-control.md` — エンドユーザーアクセス制御

```
Even after apps that use Enterprise Search features are installed and configured at the org level,
they will not be available to end users by default.
Instead, your org admin will need to enable them for end users.
Refer to this article for more details.
```

参照リンク: https://slack.com/help/articles/39044407124755-Set-up-and-manage-Slack-enterprise-search

**重要**: オーグレベルへのインストール・設定後も、エンドユーザーにはデフォルトで **利用不可**。  
Org Admin が別途エンドユーザー向けに有効化する操作が必要。

有効化後、エンドユーザーは以下の方法で個別に無効化もできる：
- サイドバーのアプリを右クリック → **Disable** を選択
- **Manage** を選択 → アプリを無効化

---

### 4. `docs/enterprise/organization-ready-apps.md` — オーグ対応 App の管理

#### App のオーグレベルインストール方法

```
Organization-ready apps can be installed in the following ways:
- via the UI from app settings (https://api.slack.com/apps)
- via the OAuth flow
- via the CLI
```

#### ワークスペースへの App 追加手順（管理ダッシュボードから）

1. 管理ダッシュボードにアクセス（`app.slack.com/manage/<your-enterprise-id-here>`）
2. 左サイドバーの **Integrations** → **Installed apps** をクリック
3. 対象 App の3点メニュー → **Add to more workspaces** を選択
4. 追加するワークスペースを選択 → **Next**
5. 権限を確認 → **Next** → **I'm ready to add this app** → **Add App**

**注意**:
> Organization-ready apps are installed once at the organization level,
> but an organization-ready app isn't automatically added to the workspaces in an organization

オーグレベルでインストールしても **ワークスペースには自動追加されない**。  
Org Admin が手動で各ワークスペースに追加する必要がある。

---

## まとめ：Enterprise Search の有効化ステップ

「App を入れただけでは使えない」理由が複数段階にわたる：

### ステップ 1：開発者による App の設定

- App マニフェストに `features.search` オブジェクトを追加
- `org_deploy_enabled: true` を設定（オーグ対応宣言）
- `function_executed` イベントを購読
- 検索結果を返すカスタムステップ関数を実装

### ステップ 2：App のオーグレベルインストール（Org Admin の作業）

- api.slack.com/apps の UI、OAuth フロー、または Slack CLI で App をオーグにインストール
- **この時点ではまだどのワークスペースでも使えない**

### ステップ 3：ワークスペースへの App 追加（Org Admin の作業）

- 管理ダッシュボードから対象ワークスペースに App を追加
- 複数ワークスペースに一括追加可能

### ステップ 4：エンドユーザーへの有効化（Org Admin の作業）

- ワークスペースへの追加後も **デフォルトでエンドユーザーには非表示**
- Slack ヘルプ記事に従って Org Admin が有効化操作を行う
  - URL: https://slack.com/help/articles/39044407124755-Set-up-and-manage-Slack-enterprise-search

### 補足：エンドユーザー側の状態

- Org Admin の有効化後、エンドユーザーはアプリがインストールされているワークスペースのメンバーであれば検索結果を受け取れる
- エンドユーザーは個別に無効化することも可能

---

## 問題・疑問点

- ステップ 4（エンドユーザー有効化）の具体的な操作手順は Slack の別ヘルプ記事（https://slack.com/help/articles/39044407124755）にあるが、そのページはドキュメントスナップショットに含まれていないため詳細は不明
- 「App を入れただけでは使えない」という話が、ステップ2・3・4のどの段階を指していたかによって、対処法が異なる
