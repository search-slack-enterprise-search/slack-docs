# search_permission
## 知りたいこと
Enterprise Searchを実行するする上で設定すべきPermissionについて調べてください。
BotとUserにどのようなPermissionが必要かを教えてください。


## 目的
Slack Appの画面で有効にしてみようとしたのですが、最低一つPermissionを設定しないと有効化できないと表示されていました。
Enterprise Searchで必要となる最小限のPermissionが知りたいです。

## プラン

### 調査対象ドキュメント
1. `docs/enterprise-search/` 以下の全ドキュメント
2. `docs/enterprise/developing-for-enterprise-orgs.md`（org-ready アプリの前提条件）
3. `docs/reference/methods/` 以下の関連 API メソッド（functions.completeSuccess, entity.presentDetails 等）
4. `docs/reference/events/` 以下の関連イベント（function_executed, entity_details_requested 等）
5. `docs/reference/scopes/` 以下の関連スコープ定義
6. `docs/reference/app-manifest.md`（マニフェスト設定）
7. `docs/apis/web-api/real-time-search-api.md`（RTS API - 参考。Enterprise Search for Apps とは別体系）

### 調査の焦点
- Enterprise Search のコア機能に必要な OAuth Scope の特定
- Bot Token / User Token それぞれに必要な Scope の整理
- アプリ有効化に最低限必要な Permission の特定
- オプション機能（Connection Reporting, Work Objects）で追加となる Scope の整理
- マニフェスト設定（Scope 以外の必須設定）の確認

### 成果物
- ログファイル (`logs/0000_search_permission.md`) に調査結果の詳細を記録
- kanban ファイルに完了サマリーを追記

## 完了サマリー

- **完了日時:** 2026-04-16T13:01:19+09:00
- **ログファイル:** `logs/0000_search_permission.md`

### 調査結果

#### 最低限必要な Permission（有効化できる最小構成）

**ユーザーが「最低一つPermissionを設定しないと有効化できない」と表示された原因:**
Enterprise Search アプリは org-ready（組織対応）アプリである必要がある。org-ready アプリのオプトイン手順の中で、**最低1つの Bot Scope** が必要と公式ドキュメントに明記されている。

> Navigate to **OAuth & Permissions**, scroll down to **Scopes**, and add any bot scope to your app, such as `team:read`. A bot scope is required for the next step to be available.
> — `docs/enterprise/developing-for-enterprise-orgs.md`

**→ `team:read`（または他の任意の Bot Scope 1つ）を追加すれば有効化できる。**

---

#### 機能別の必要 Permission 一覧

**Bot Token スコープ:**

| スコープ | 必須/任意 | 用途 |
|---|---|---|
| `team:read`（任意の Bot Scope） | **必須**（org-ready 前提条件） | 組織レベルデプロイ有効化ステップの解放 |
| `links:read` | 任意（Work Objects unfurl 時） | `link_shared` イベント購読 |
| `links:write` | 任意（Work Objects unfurl 時） | `chat.unfurl` 呼び出し |

**User Token スコープ:**

| スコープ | 必須/任意 | 用途 |
|---|---|---|
| `users:write` | 任意（Connection Reporting 時） | `user_connection` イベント購読・`apps.user.connection.update` 呼び出し |

#### スコープ不要な機能（Enterprise Search コア）

Enterprise Search のコア機能（`function_executed` イベントで検索を受け取り → `functions.completeSuccess` で結果返却）は **OAuth Scope が一切不要**:

| API/イベント | スコープ | 用途 |
|---|---|---|
| `function_executed` イベント | なし | 検索関数の実行トリガー |
| `entity_details_requested` イベント | なし | Work Objects フレックスペーントリガー |
| `functions.completeSuccess` | なし | 検索結果の返却 |
| `functions.completeError` | なし | エラー返却 |
| `entity.presentDetails` | なし | エンティティ詳細表示 |