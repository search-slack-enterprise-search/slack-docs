# 0067: Work Objects manifest.json 設定

## 調査日時

2026-05-07

## 調査概要

Work Objects を有効にするための manifest.json の書き方を調査した。

---

## 調査ファイル一覧

| ファイル | 内容 |
|---|---|
| `docs/reference/app-manifest.md` | manifest リファレンス（全フィールド定義） |
| `docs/messaging/work-objects-implementation.md` | Work Objects 実装ガイド（UIでの設定方法含む） |
| `docs/messaging/work-objects-overview.md` | Work Objects 概要 |
| `docs/messaging/unfurling-links-in-messages.md` | link unfurl の設定方法 |
| `docs/changelog/2025/10/22/work-objects.md` | Work Objects リリースアナウンス |
| `kanban/0055_enterprise-search-manifest-sample.md` | Enterprise Search manifest サンプル（参照） |
| `kanban/0056_enterprise-search-manifest-search-only.md` | Work Objects 無効化時の差分（参照） |

---

## 調査結果

### 1. `features.rich_previews` が Work Objects の manifest 設定キー

`docs/reference/app-manifest.md`（line 365–393）に以下の記載がある:

| フィールド | 説明 |
|---|---|
| `features.rich_previews` | rich previews（Work Objects）の設定グループ |
| `features.rich_previews.is_active` | boolean。rich previews を有効にするか |
| `features.rich_previews.entity_types` | array of strings。エンティティタイプの一覧 |

これが **"Work Object Previews"** という UI 設定に対応する manifest キーである。

### 2. Work Objects 実装ガイドの UI 手順（manifest との対応）

`docs/messaging/work-objects-implementation.md` に記載されている UI 操作:

```
1. api.slack.com/apps を開き、対象アプリを選択
2. 左サイドバーの "Work Object Previews" へ移動
3. トグルを ON にする  → features.rich_previews.is_active: true
4. entity type を選択  → features.rich_previews.entity_types: ["slack#/entities/task", ...]
5. Save
```

### 3. 利用可能な entity_types の値

Work Objects の `entity_types` に指定できる文字列（`docs/messaging/work-objects-implementation.md` Supported Entity Types セクション）:

| 型 | entity_type 文字列 | 用途 |
|---|---|---|
| File | `slack#/entities/file` | ドキュメント、スプレッドシート、画像など |
| Task | `slack#/entities/task` | チケット、To-do など |
| Incident | `slack#/entities/incident` | インシデント、サービス障害など |
| Content Item | `slack#/entities/content_item` | コンテンツページ、記事など |
| Item | `slack#/entities/item` | 汎用エンティティ |

### 4. Work Objects 全体で必要な manifest 設定

Work Objects は複数の機能の組み合わせであり、manifest.json に設定が必要な箇所は複数ある。

#### (A) `features.rich_previews` — Work Object Previews（必須）

```json
"features": {
  "rich_previews": {
    "is_active": true,
    "entity_types": [
      "slack#/entities/task"
    ]
  }
}
```

- `is_active: true` で Work Object Previews を有効化
- `entity_types` には使用したいエンティティタイプを列挙

#### (B) `features.unfurl_domains` — link unfurl ドメイン登録（link unfurl を使う場合）

```json
"features": {
  "unfurl_domains": [
    "your-domain.example.com"
  ]
}
```

- リンクがチャットに貼られたとき `link_shared` イベントを受け取るために必要
- 最大 5 ドメイン
- ドメイン変更にはアプリの再インストールが必要

#### (C) `settings.event_subscriptions.bot_events` — イベント購読

```json
"settings": {
  "event_subscriptions": {
    "request_url": "https://YOUR_APP_URL/slack/events",
    "bot_events": [
      "link_shared",
      "entity_details_requested"
    ]
  }
}
```

- `link_shared`: チャットに unfurl 対象 URL が貼られたときに発火
- `entity_details_requested`: ユーザーが Work Object をクリックしてフレックスペインを開くときに発火

#### (D) `settings.interactivity` — インタラクティビティ（アクション・編集機能を使う場合）

```json
"settings": {
  "interactivity": {
    "is_enabled": true,
    "request_url": "https://YOUR_APP_URL/slack/events"
  }
}
```

- Work Object のフッターにアクションボタンを追加する場合や、フィールド編集機能を使う場合に必要
- `block_actions` や `view_submission` ペイロードの受信に使う

#### (E) `oauth_config.scopes.bot` — OAuth スコープ

```json
"oauth_config": {
  "scopes": {
    "bot": [
      "links:read",
      "links:write"
    ]
  }
}
```

- `links:read`: チャットに貼られたリンクを読む権限（`link_shared` イベントの受信に必要）
- `links:write`: リンクを unfurl する権限（`chat.unfurl` API 呼び出しに必要）

### 5. Enterprise Search との文脈での Work Objects manifest

`kanban/0056_enterprise-search-manifest-search-only.md` の調査サマリーによると、Work Objects を無効にした manifest（Search のみ）から Work Objects を有効にするには以下を追加する:

| 追加内容 | 理由 |
|---|---|
| `event_subscriptions.bot_events["entity_details_requested"]` | フレックスペインのイベント受信 |
| `settings.interactivity` | アクション・編集ボタンの受信 |
| `features.rich_previews` | Work Object Previews の有効化（manifest のキー） |

ただし、0055/0056 の既存サンプルには `features.rich_previews` が含まれていなかった。これは、Enterprise Search 用の search function の output に work object の entity metadata を含めることができる（`entity_type` + `entity_payload`）ため、`features.rich_previews` なしでも一部の Work Objects 表示が機能する可能性がある。詳細な検証は別途必要。

---

## manifest.json サンプル（Work Objects 全機能有効版）

```json
{
  "_metadata": {
    "major_version": 2,
    "minor_version": 1
  },
  "display_information": {
    "name": "My Work Objects App",
    "description": "App demonstrating Work Objects",
    "background_color": "#2c2d30"
  },
  "settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
      "request_url": "https://YOUR_APP_URL/slack/events",
      "bot_events": [
        "link_shared",
        "entity_details_requested"
      ]
    },
    "interactivity": {
      "is_enabled": true,
      "request_url": "https://YOUR_APP_URL/slack/events"
    },
    "socket_mode_enabled": false,
    "token_rotation_enabled": false
  },
  "features": {
    "bot_user": {
      "display_name": "Work Objects Bot",
      "always_online": false
    },
    "unfurl_domains": [
      "your-domain.example.com"
    ],
    "rich_previews": {
      "is_active": true,
      "entity_types": [
        "slack#/entities/task",
        "slack#/entities/file",
        "slack#/entities/incident",
        "slack#/entities/content_item",
        "slack#/entities/item"
      ]
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "links:read",
        "links:write"
      ]
    }
  }
}
```

---

## 調査アプローチ

1. `rg -l "work.object"` で Work Objects 関連ファイルを一覧
2. `docs/messaging/work-objects-implementation.md` を読み、UIでの設定手順を確認
3. `docs/reference/app-manifest.md` を読み、`features.rich_previews` がマッチする manifest キーであることを確認
4. `docs/messaging/unfurling-links-in-messages.md` で link unfurl に必要なスコープ・イベントを確認
5. 既存 kanban（0055, 0056）サンプルを参照して Enterprise Search との統合文脈を確認

---

## 問題・疑問点

- `features.rich_previews` なしで Enterprise Search 経由の Work Objects 表示が機能するかどうか未確認。0055 の manifest にはこの設定が含まれていないが、Enterprise Search の search results に entity metadata を含めることで Work Objects が表示できると仮定されているようだ。
- link unfurl ベースの Work Objects と Enterprise Search 経由の Work Objects で、`features.rich_previews` の必要性が異なる可能性がある。
