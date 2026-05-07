# 0069: Link Unfurl 詳細調査

## 調査日時

2026-05-07

## 調査概要

link unfurl の仕組みを詳細に調査した。Work Objects との関係、manifest.json に必要な設定の分岐を整理した。

---

## 調査ファイル一覧

| ファイル | 内容 |
|---|---|
| `docs/messaging/unfurling-links-in-messages.md` | link unfurl の全体像・実装詳細 |
| `docs/messaging/work-objects-overview.md` | Work Objects 概要（link unfurl との関係説明あり） |
| `docs/messaging/work-objects-implementation.md` | Work Objects 実装詳細（unfurl implementation セクション） |
| `docs/reference/app-manifest.md` | manifest リファレンス（`unfurl_domains` キー） |
| `kanban/0068_reconcile-0065-0067-findings.md` | 前回調査（0065/0067統合）のサマリー |
| `logs/0067_work-objects-manifest-config.md` | Work Objects manifest 設定調査ログ |

---

## 調査結果

### 1. link unfurl の3種類

`docs/messaging/unfurling-links-in-messages.md` line 3–13 に明記されている:

| 種類 | 説明 |
|---|---|
| **Classic link unfurling** | Slack のデフォルト動作。URLをクロールして OpenGraph / Twitter Card メタデータからプレビュー生成。アプリ不要 |
| **Slack app unfurling** | アプリが登録ドメインのURLを検知し、独自プレビューを提供できる |
| **Work Objects** | Slack app unfurling のさらなる拡張。リッチなプレビュー＋フレックスペインによるインタラクションが可能 |

---

### 2. Slack app unfurling の仕組み（フロー）

`docs/messaging/unfurling-links-in-messages.md` line 30–34 に記載:

1. ユーザーが **登録ドメイン** の完全修飾 URL を含むメッセージを投稿
2. アプリが **`link_shared`** イベントを受信（URL情報・channel・message_ts を含む）
3. アプリが **`chat.unfurl`** API を呼び出してカスタム unfurl 内容を添付

#### `link_shared` イベントの構造（抜粋）

```json
{
  "event": {
    "type": "link_shared",
    "channel": "Cxxxxxx",
    "user": "Uxxxxxxx",
    "message_ts": "123452389.9875",
    "unfurl_id": "C123456.123456789.987501...",
    "source": "conversations_history",
    "links": [
      {
        "domain": "example.com",
        "url": "https://example.com/12345"
      }
    ]
  }
}
```

- `source` は `"composer"` または `"conversations_history"` の2種類
- `link_shared` イベントは **メッセージ全体は含まない**（`links` 配列のURL情報のみ）
- アプリ自身の投稿では `link_shared` は発火しない

#### `chat.unfurl` API 呼び出し例

```json
{
  "channel": "C12345",
  "ts": "156762948.24601",
  "unfurls": {
    "https://example.com/document/123": {
      "blocks": [...]
    }
  }
}
```

または `unfurl_id` と `source` を使う方法も可。

---

### 3. Slack app unfurling に必要な manifest 設定

`docs/messaging/unfurling-links-in-messages.md` の「Configuring your app」セクション（line 37–71）より:

#### (A) スコープ（`oauth_config.scopes.bot`）

| スコープ | 役割 |
|---|---|
| `links:read` | チャットに貼られたリンクを読む（`link_shared` イベント受信に必要） |
| `links:write` | リンクを unfurl する（`chat.unfurl` API 呼び出しに必要） |

#### (B) イベント購読（`settings.event_subscriptions.bot_events`）

- `link_shared` を追加

#### (C) ドメイン登録（`features.unfurl_domains`）

```json
"features": {
  "unfurl_domains": [
    "example.com"
  ]
}
```

- 最大 5 ドメイン
- ドメイン追加/削除には **アプリの再インストール** が必要
- プロトコル（`http://`/`https://`）なしで登録
- サブドメイン・パスは全て対象になる（`example.com` を登録 → `sub.example.com/path` も対象）
- IPアドレスは不可
- ドメイン単体（TLDなし）は不可（`example.com` は可、`example` は不可）

---

### 4. Work Objects と link unfurl の関係

#### 位置付け

`docs/messaging/work-objects-overview.md` line 1–8 より：

> "One of the primary ways to share external content within Slack is by posting URL links in conversations. (...) That's why we originally introduced link unfurling (...). With Work Objects, apps can take the unfurling experience even further."

`docs/messaging/work-objects-implementation.md` line 17–20 より：

> "Work Object unfurls are an extension of the existing link unfurl feature for Slack apps. If your app has not been configured with it yet, please follow the setup instructions to do so."

**Work Objects の unfurl は link unfurl の拡張であり、link unfurl のセットアップが前提。**

#### 実装の違い

| 方式 | トリガー | アプリが呼ぶAPI |
|---|---|---|
| Slack app unfurling（通常） | `link_shared` | `chat.unfurl`（`blocks` のみ） |
| Work Objects の unfurl | `link_shared` | `chat.unfurl`（`metadata` パラメータに entity data を追加） |
| Work Objects のフレックスペイン | `entity_details_requested` | `entity.presentDetails` |

`chat.unfurl` API の `metadata` パラメータ（Work Objects 用）:

```json
{
  "metadata": {
    "entities": [
      {
        "app_unfurl_url": "https://example.com/document/123?eid=123456",
        "url": "https://example.com/document/123",
        "external_ref": {
          "id": "123",
          "type": "document"
        },
        "entity_type": "slack#/entities/file",
        "entity_payload": {}
      }
    ]
  }
}
```

#### Bolt for JavaScript のサンプルコード（`docs/messaging/work-objects-overview.md` line 37–44）

```javascript
// link_shared イベントで chat.unfurl を呼ぶ
await client.chat.unfurl({
  channel: event.channel,
  ts: event.message_ts,
  metadata: { entities: [entity_metadata] }
});

// entity_details_requested イベントでフレックスペインを開く
client.entity.presentDetails({
  trigger_id: event.trigger_id,
  metadata: entity_metadata
});
```

---

### 5. Enterprise Search ベースの Work Objects と link unfurl の違い

`docs/messaging/work-objects-overview.md` line 87–93 の「Support for Enterprise Search」セクション:

> "To support Work Objects for your app's Enterprise Search results, traditional search results, and AI answers citations, your app must subscribe to the `entity_details_requested` event."
> "Once your app is subscribed to the `entity_details_requested` event, it can respond to the event and call the `entity.presentDetails` API method with Work Object metadata to launch the flexpane experience."

**Enterprise Search 経由の Work Objects では `link_shared` は発生しない。**

| 項目 | link unfurl ベースの Work Objects | Enterprise Search ベースの Work Objects |
|---|---|---|
| 起動トリガー | ユーザーがチャットにURLを貼る → `link_shared` | ユーザーが Enterprise Search 検索結果をクリック → `entity_details_requested` |
| unfurl 表示 | チャットの `chat.unfurl` で表示 | Enterprise Search 結果カードとして表示 |
| フレックスペイン | `entity_details_requested` → `entity.presentDetails` | 同左 |
| 必要スコープ | `links:read`, `links:write` | 不要（`team:read` のみ） |
| 必要イベント | `link_shared`, `entity_details_requested` | `entity_details_requested` のみ |
| 必要 manifest キー | `features.unfurl_domains`, `features.rich_previews` | `features.rich_previews` のみ（`unfurl_domains` 不要） |

---

### 6. manifest.json への影響まとめ（link unfurl が必要かどうか）

#### Enterprise Search のみ（link unfurl なし）

```json
{
  "settings": {
    "event_subscriptions": {
      "bot_events": ["function_executed", "entity_details_requested"]
    }
  },
  "features": {
    "search": { "search_function_callback_id": "search_function" },
    "rich_previews": {
      "is_active": true,
      "entity_types": ["slack#/entities/task"]
    }
  },
  "oauth_config": {
    "scopes": { "bot": ["team:read"] }
  }
}
```

- `link_shared` イベント → **不要**
- `unfurl_domains` → **不要**
- `links:read`, `links:write` → **不要**

#### link unfurl ベースの Work Objects あり（チャットへのURL貼り付けにも対応）

```json
{
  "settings": {
    "event_subscriptions": {
      "bot_events": ["function_executed", "link_shared", "entity_details_requested"]
    }
  },
  "features": {
    "search": { "search_function_callback_id": "search_function" },
    "unfurl_domains": ["your-domain.example.com"],
    "rich_previews": {
      "is_active": true,
      "entity_types": ["slack#/entities/task"]
    }
  },
  "oauth_config": {
    "scopes": { "bot": ["team:read", "links:read", "links:write"] }
  }
}
```

---

### 7. その他の注意点

`docs/messaging/unfurling-links-in-messages.md` Tips セクション（line 265–281）より:

- 同じドメインで2つのアプリが `link_shared` を購読している場合、**先にインストールされたアプリのみ**がイベントを受け取る
- `link_shared` はアプリ・インテグレーションが投稿したメッセージには発火しない
- `chat.unfurl` では `rich text section element` が現在サポートされていない
- LLMからのメッセージには link unfurl を無効化することを推奨（プロンプトインジェクション対策）

---

## 調査アプローチ

1. `docs/messaging/unfurling-links-in-messages.md` を全読みして link unfurl の仕組みを理解
2. `docs/messaging/work-objects-overview.md` の「Support for Enterprise Search」セクションで Enterprise Search との関係を確認
3. `docs/messaging/work-objects-implementation.md` の「Unfurl implementation」セクションで Work Objects が link unfurl の拡張であることを確認
4. `docs/reference/app-manifest.md` で `unfurl_domains` の記述を確認
5. 既存 kanban 0067 / 0068 の調査結果を照合して整合性を確認

---

## 問題・疑問点

特になし。0068 の統合結果（Enterprise Search のみなら `link_shared`/`unfurl_domains`/`links:read`/`links:write` は不要）が今回の詳細調査でも裏付けられた。
