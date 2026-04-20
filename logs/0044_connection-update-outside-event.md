# user_connection イベント外からの接続状態更新 調査ログ

## タスク概要

- **kanban ファイル**: `kanban/0044_connection-update-outside-event.md`
- **知りたいこと**: `user_connection` イベントの外（cron実行など）で `apps.user.connection.update()` はできるのか。
- **目的**: トークンの有効期限が切れても接続済みと表示され続けるので、外部から更新できるかどうかを知りたい。
- **調査日**: 2026-04-20

---

## 調査ファイル一覧

| ファイルパス | 内容 |
|---|---|
| `docs/reference/methods/apps.user.connection.update.md` | API リファレンス（メイン） |
| `docs/enterprise-search/connection-reporting.md` | Connection Reporting 公式ドキュメント |

---

## 調査アプローチ

1. `apps.user.connection.update` の API リファレンスを精読し、引数に `trigger_id` などイベントコンテキストへの依存があるかを確認する
2. `connection-reporting.md` を精読し、呼び出し制約（「イベントハンドラ内のみ」等）の記述があるかを確認する
3. `views.open` との比較：`views.open` は `trigger_id` 必須（3秒タイムアウト）でイベント外からは呼べない典型例。`apps.user.connection.update` が同様の制約を持つかを確認する

---

## 調査結果

### 1. apps.user.connection.update API の引数

**ファイル**: `docs/reference/methods/apps.user.connection.update.md`

#### 必須引数（全て）

| パラメータ | 型 | 説明 |
|-----------|------|------|
| `token` | string | 認証トークン（`users:write` スコープが必要） |
| `user_id` | string | ステータス更新対象のユーザーID |
| `status` | string | `connected` または `disconnected` |

**重要な確認事項**:
- **`trigger_id` パラメータは存在しない**
- **イベントコンテキストに依存するパラメータは一切ない**
- **タイムアウト制約の記述はない**

`apps.user.connection.update` の必須引数は `token`・`user_id`・`status` の3つのみであり、イベントから渡される `trigger_id` や `workflow_step_edit_id` などのコンテキスト依存パラメータは存在しない。

#### エンドポイント

```
POST https://slack.com/api/apps.user.connection.update
```

標準的な HTTP POST エンドポイントであり、呼び出しタイミングに関する制約の記述はない。

#### Rate Limits

- Tier 2: 20+ per minute（通常の API と同じレートリミット）

---

### 2. Connection Reporting ドキュメントの記述

**ファイル**: `docs/enterprise-search/connection-reporting.md` 行 17

> "The app is always expected to invoke the `apps.user.connection.update` API method in its **connecting flow** to notify Slack when a user's connection status changes."

「connecting flow」という表現は「接続フロー（全体）の中で」という意味であり、「`user_connection` イベントハンドラの中のみ」という意味ではない。

イベントハンドラへの呼び出し制限を明記する文言は存在しない。

---

### 3. views.open との比較

`views.open` はイベント外から呼べない典型例：

| API | `trigger_id` 必須 | タイムアウト制約 | イベント外呼び出し |
|-----|-------------------|-----------------|------------------|
| `views.open` | ✓ 必須（3秒以内） | あり | **不可** |
| `apps.user.connection.update` | なし | **なし** | **可能** |

`apps.user.connection.update` には `trigger_id` パラメータが存在せず、タイムアウト制約の記述もない。これは「任意のタイミングで呼び出せる」ことを意味する。

---

### 4. 結論：イベント外からの呼び出しは可能

**`apps.user.connection.update` は `user_connection` イベントハンドラの外から呼び出すことができる。**

呼び出しに必要なものは：
1. 有効な Bot token（`users:write` スコープ付き）
2. 更新対象の Slack user_id
3. 設定するステータス値（`connected` / `disconnected`）

これらが揃えば、どのタイミングからでも呼び出せる：

```
✓ user_connection イベントハンドラ内（接続フロー）
✓ OAuth callback エンドポイント内
✓ cron ジョブ（定期バッチ）
✓ 外部サービスの webhook 受信時
✓ バックグラウンドタスク
✓ 検索関数（function_executed）内でトークン検証失敗時
```

---

### 5. トークン有効期限切れへの対処パターン

#### パターン1: 検索時に同期（最も単純）

`function_executed` イベント受信時、外部トークンを検証して無効なら即座に disconnected へ更新：

```
function_executed（検索リクエスト）
    ↓
外部 OAuth トークンをDBから取得
    ↓
if トークンなし or 有効期限切れ:
    apps.user.connection.update(user_id, "disconnected")  ← 即座に更新
    functions.completeError("認証が必要です。...")
else:
    外部サービスへ検索リクエスト
    functions.completeSuccess(results)
```

#### パターン2: 外部サービスの webhook で同期

外部サービスがトークン失効の webhook を提供している場合：

```
外部サービス → アプリ: トークン失効 webhook
    ↓
アプリ: Slack user_id と失効トークンの紐付けをDBで確認
    ↓
apps.user.connection.update(user_id, "disconnected")  ← 即座に更新
```

#### パターン3: cron による定期バッチ（本タスクの質問の核心）

```
定期バッチ（例: 毎時）
    ↓
DB から全ユーザーのトークン情報を取得
    ↓
for each user:
    外部サービスで token validation API 呼び出し
    if 無効:
        apps.user.connection.update(user_id, "disconnected")
```

**このパターンも技術的には可能**。ただし：
- 外部サービスが token validation API を提供している必要がある
- Rate Limit（Tier 2: 20+/min）への配慮が必要

---

## 判断・意思決定

### 「イベント外から呼び出せる」は API 設計から明らか

`apps.user.connection.update` が `trigger_id` を持たない点が最大の根拠。Slack の API 設計において：
- `trigger_id` 必須 → イベントコンテキスト内で使用する API（`views.open` など）
- `trigger_id` 不要 → 任意のタイミングで使用できる API

`apps.user.connection.update` は後者であり、cron や webhook など任意のタイミングからの呼び出しが可能。

### 実用上の推奨パターン

0043番の調査で「検索関数内でトークン検証・状態同期」を推奨したが、本調査でその方針が強化された：
- 検索時同期はリクエスト駆動でシンプル
- cron による定期バッチは外部サービスの token validation API の有無に依存する
- どちらも技術的に実現可能

---

## 問題・疑問点

1. **ユーザーが現在 Slack にログインしていない場合の挙動**: cron から `apps.user.connection.update(disconnected)` を呼んだ際、ユーザーが Slack を開いていない場合でも Slack 側の保持ステータスは更新されるか（次回 User Report 表示時に正しく表示されるか）。ドキュメントの範囲では確認できないが、Slack がサーバーサイドでステータスを保持する設計上、問題ないと推定される。
