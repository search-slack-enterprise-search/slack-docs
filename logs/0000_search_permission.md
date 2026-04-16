# 0000_search_permission 調査ログ

- **開始日時:** 2026-04-16T13:00:10+09:00
- **完了日時:** 2026-04-16T13:01:19+09:00

---

## タスク概要

**要望:**
Enterprise Searchを実行するする上で設定すべきPermissionについて調べてください。
BotとUserにどのようなPermissionが必要かを教えてください。

**目的:**
Slack Appの画面で有効にしてみようとしたのですが、最低一つPermissionを設定しないと有効化できないと表示されていました。
Enterprise Searchで必要となる最小限のPermissionが知りたいです。

---

## 調査結果

### 調査対象ファイルと発見した内容

#### 1. `docs/enterprise-search/developing-apps-with-search-features.md`

Enterprise Search アプリの開発方法を説明する中核ドキュメント。

**アプリマニフェストの必須設定 (行 9-33, 46):**
```json
"features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```
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
- `search_function_callback_id`: 検索結果を返す関数の callback_id（**必須**）
- `search_filters_function_callback_id`: 検索フィルタを返す関数の callback_id（任意）
- `org_deploy_enabled: true`: 組織レベルデプロイの有効化（**必須**）
- `function_executed`: 検索関数の実行トリガーイベント（**必須購読**）
- `entity_details_requested`: Work Objects フレックスペーン対応（Work Objects 使用時に必須）

**検索結果返却に使用する API (行 299-304):**
- `functions.completeSuccess` / `functions.completeError` を使用して検索結果を返す
- ワークフロートークンが失効した後も bot token は引き続き使用可能

**配布制限 (行 35):**
> Note that apps containing Enterprise Search cannot be distributed publicly or submitted to the Slack Marketplace.

---

#### 2. `docs/enterprise/developing-for-enterprise-orgs.md`（行 78）

org-ready アプリ化の手順が記載されており、**ここに最低1つの Bot Scope が必要と明記されている**:

> Navigate to **OAuth & Permissions**, scroll down to **Scopes**, and add any bot scope to your app, such as [`team:read`](/reference/scopes/team.read). A bot scope is required for the next step to be available.

これがユーザーが「最低一つPermissionを設定しないと有効化できない」と表示された原因。`team:read` 等のいずれか1つを追加すれば OK。

---

#### 3. `docs/reference/methods/functions.completeSuccess.md`（行 40）

Enterprise Search の検索結果返却 API:
> **Scopes** _No scopes required_

スコープ不要。

---

#### 4. `docs/reference/methods/functions.completeError.md`（行 40）

Enterprise Search のエラー返却 API:
> **Scopes** _No scopes required_

スコープ不要。

---

#### 5. `docs/reference/methods/entity.presentDetails.md`（行 40-41）

Work Objects のフレックスペーン表示 API:
> **Scopes** _No scopes required_

スコープ不要。

---

#### 6. `docs/reference/events/function_executed.md`（行 11）

検索関数の実行トリガーイベント:
> **Required Scopes** No scopes required!

スコープ不要。

---

#### 7. `docs/reference/events/entity_details_requested.md`（行 11）

Work Objects のフレックスペーントリガーイベント:
> **Required Scopes** No scopes required!

スコープ不要。

---

#### 8. `docs/enterprise-search/enterprise-search-access-control.md`（行 3-7）

アプリをインストール・設定しても、デフォルトではエンドユーザーに公開されない:
> Even after apps that use Enterprise Search features are installed and configured at the org level, they will not be available to end users by default. Instead, your org admin will need to enable them for end users.

→ 組織管理者が明示的に有効化する必要がある。

---

#### 9. `docs/enterprise-search/connection-reporting.md` 関連イベント・API

Connection Reporting 機能（ユーザー接続状態レポート）を実装する場合に必要なスコープ:

**`docs/reference/events/user_connection.md`（行 11）:**
> **Required Scopes** [`users:write`](/reference/scopes/users.write)

**`docs/reference/methods/apps.user.connection.update.md`（行 40-45）:**
> **Scopes** User token: [`users:write`](/reference/scopes/users.write)

→ `users:write` は **User Token** にのみ付与が必要で、Bot Token では不可。

---

#### 10. Work Objects / Unfurl 関連（オプション）

検索結果にリッチプレビュー（Work Objects）を付与し、リンクのアンファールを行う場合:

**`docs/reference/events/link_shared.md`（行 9-10）:**
> **Required Scopes**: `links:read`

**`docs/reference/methods/chat.unfurl.md`（行 40-49）:**
> Bot token: `links:write` / User token: `links:write`

→ `links:read`（Bot Token）と `links:write`（Bot/User Token）が必要。

**`docs/messaging/work-objects-overview.md`（行 87-91）:**
> To support Work Objects for your app's Enterprise Search results, traditional search results, and AI answers citations, your app must subscribe to the `entity_details_requested` event.

→ Work Objects の flexpane 対応には `entity_details_requested` イベント購読が必要（スコープ不要）。

---

#### 11. `docs/reference/app-manifest.md` — マニフェストでの OAuth Scope 設定方法（行 545-626）

```json
"oauth_config": {
    "scopes": {
        "bot": ["team:read"],
        "bot_optional": [],
        "user": ["users:write"],
        "user_optional": []
    }
}
```
- `oauth_config.scopes.bot`: Bot Token スコープ
- `oauth_config.scopes.user`: User Token スコープ

**注意:** `features.search` オブジェクトはこのドキュメントのリファレンステーブルには未記載（ドキュメントのギャップ）。`developing-apps-with-search-features.md` に定義されている。

---

#### 12. `docs/apis/web-api/real-time-search-api.md` — 参考（別体系）

これは Enterprise Search（外部データを Slack 検索に統合する機能）とは**異なる**機能。Slack 自身のデータ（メッセージ・ファイル等）を AI アプリや外部システムから検索するための API。参考として必要スコープを記録する:

| API メソッド | Bot Token スコープ | User Token スコープ |
|---|---|---|
| `assistant.search.context` | `search:read.files`, `search:read.public`, `search:read.users` | `search:read.files`, `search:read.im`, `search:read.mpim`, `search:read.private`, `search:read.public`, `search:read.users` |
| `assistant.search.info` | `search:read.public` | `search:read` |

- 必須最低スコープ: `search:read.public`（行 32）
- レガシーの `search:read` スコープおよび `search.messages` / `search.all` メソッドは非推奨（行 438）

---

### まとめ: Enterprise Search で必要な Permission

#### 【最低限必要なもの】（Slack App 画面で有効化できる最小構成）

**Bot Token スコープ:**
- **`team:read`（または他の任意の Bot Scope 1つ）** — org-ready アプリ化の前提条件として必須

**User Token スコープ:**
- なし（コア機能のみであれば不要）

**なぜこれで済むか:**
Enterprise Search のコア機能（`function_executed` イベント受信 → 検索結果を `functions.completeSuccess` で返却）自体は OAuth Scope を必要としない。ただし、アプリを org-ready にするステップで「最低1つの Bot Scope」が必要になるため、`team:read` 等の任意のスコープを1つ追加することで有効化できる。

---

#### 【機能別の必要 Permission 一覧】

**Bot Token スコープ:**

| スコープ | 必須/任意 | 用途 |
|---|---|---|
| `team:read`（任意の Bot Scope） | **必須**（org-ready 化の前提条件） | 組織レベルデプロイ有効化のステップを解放 |
| `links:read` | 任意 | Work Objects unfurl 時の `link_shared` イベント購読 |
| `links:write` | 任意 | Work Objects unfurl 時の `chat.unfurl` 呼び出し |

**User Token スコープ:**

| スコープ | 必須/任意 | 用途 |
|---|---|---|
| `users:write` | 任意 | Connection Reporting: `user_connection` イベント購読・`apps.user.connection.update` 呼び出し |

**スコープ不要な機能（Enterprise Search コア）:**

| API/イベント | スコープ | 用途 |
|---|---|---|
| `function_executed` イベント | なし | 検索関数の実行トリガー |
| `entity_details_requested` イベント | なし | Work Objects フレックスペーントリガー |
| `functions.completeSuccess` | なし | 検索結果の返却 |
| `functions.completeError` | なし | エラー返却 |
| `entity.presentDetails` | なし | エンティティ詳細表示 |

---

## 実装プラン

### 採用したアプローチ

調査フェーズで必要な情報はすべて取得済み。以下を実施する:

1. **ログファイル作成**（本ファイル）: 調査結果の詳細を記録
2. **kanban ファイルに `## プラン` 追記**: フェーズ1で実施済み
3. **kanban ファイルに `## 完了サマリー` 追記**: 調査完了後に記録

### プランニング経緯

- 初回提案のプランがそのまま承認された（リジェクトなし）

---

## 会話内容

### フェーズ1

- **ユーザー:** `/kanban` コマンドを実行
- **Claude:** タスクファイル `kanban/0000_search_permission.md` を読み込み、EnterPlanMode に遷移
- **Claude:** Explore エージェント2つを並行起動:
  1. Enterprise Search ドキュメント（`enterprise-search/`）を中心に Permission 調査
  2. Authentication / Web API / Scopes 定義ドキュメントから関連情報を調査
- **Claude:** 調査結果をもとにプランを策定し、kanban ファイルに `## プラン` セクションを追記
- **Claude:** ExitPlanMode でプランを提示
- **ユーザー:** プランを承認

---

## 編集したファイル

| ファイル | 内容 |
|---|---|
| `kanban/0000_search_permission.md` | `## プラン` セクションを追記 |
| `logs/0000_search_permission.md` | 本ファイル（調査ログ）を新規作成 |

---

## 実行したコマンド

| コマンド | 目的 |
|---|---|
| `TZ=Asia/Tokyo date +"%Y-%m-%dT%H:%M:%S+09:00"` | 現在時刻取得（JST） |
| `ls /Users/yuta/.../logs/` | logs ディレクトリの存在確認 |

---

## 判断・意思決定

- Enterprise Search のコア機能自体は OAuth Scope 不要だが、org-ready アプリ化の前提条件として最低1つの Bot Scope が必要な点を特定
- これがユーザーの「最低一つPermissionを設定しないと有効化できない」というエラーの原因と判断
- Connection Reporting と Work Objects は別途スコープが必要な「オプション機能」として分類

---

## エラー・問題

特になし。

---

## 完了

- **完了日時:** 2026-04-16T13:01:19+09:00
