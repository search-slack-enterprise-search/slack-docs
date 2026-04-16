# user_report が動かす方法がないのだがどうしたらいいのか 調査ログ

## タスク概要

- **kanban ファイル**: `kanban/0014_user_report_not_work.md`
- **知りたいこと**: 0012番の調査結果を踏まえると user_report を動かすための OAuth トークンがない。これはどうやって解消するか？
- **目的**: 回答の内容が矛盾をはらんだままになっている。どうしていいかわからない。
- **調査日**: 2026-04-16

---

## 調査ファイル一覧

| ファイルパス | 内容 |
|---|---|
| `kanban/0014_user_report_not_work.md` | タスクファイル |
| `logs/0012_token-management-contradiction-0005-vs-0010.md` | 0012番 調査ログ（Deno SDK vs Bolt の矛盾解消） |
| `logs/0009_enterprise-search-external-auth-integration.md` | 0009番 調査ログ（Enterprise Search + 外部認証の組み合わせ実装） |
| `logs/0010_oauth-token-refresh-in-own-db.md` | 0010番 調査ログ（自社 DB の OAuth トークン更新方法） |
| `logs/0002_what_connection_report.md` | 0002番 調査ログ（Connection Report とは何か） |
| `logs/0003_connection_report_auth.md` | 0003番 調査ログ（Connection Report の認証状態） |
| `docs/enterprise-search/connection-reporting.md` | Connection Reporting 公式ドキュメント |
| `docs/enterprise-search/developing-apps-with-search-features.md` | Enterprise Search 開発ガイド |
| `docs/reference/methods/apps.user.connection.update.md` | apps.user.connection.update API リファレンス |
| `docs/reference/scopes/users.write.md` | users:write スコープドキュメント |
| `docs/reference/events/user_connection.md` | user_connection イベントリファレンス |
| `docs/reference/methods/users.setActive.md` | users.setActive API（比較用） |
| `docs/reference/methods/users.setPresence.md` | users.setPresence API（比較用） |

---

## 調査アプローチ

1. 0012番の調査ログを読み込み、「user_report」と言っている対象を特定する
2. Connection Reporting 関連のドキュメント（0002, 0003, 0009, 0010 のログ）を読み込み、文脈を把握する
3. `apps.user.connection.update` の API ドキュメントを精読し、必要なトークンを確認する
4. `users:write` スコープのドキュメントを確認し、Bot/User token の違いを調査する
5. advisor に確認し、矛盾の解消方法を整理する

---

## 調査結果

### 1. 「user_report」とは何を指しているか

kanban ファイル（`kanban/0014_user_report_not_work.md`）には `user_report` という用語が登場するが、Slack 公式ドキュメントにこの用語は存在しない。

**`user_report` は「Connection Reporting」機能、特に `apps.user.connection.update` API の呼び出しを指していると解釈される。**

0012番の調査結果では「Deno SDK External Auth（ROSI）は Enterprise Search では使えない」と確認されており、ユーザーはこれを受けて「Connection Reporting（user_report）を動かすための OAuth トークンがない」と感じている。

---

### 2. ユーザーが感じている矛盾の正確な把握

ユーザーの感じている矛盾は、以下の2通りの解釈が可能：

| 解釈 | 内容 |
|---|---|
| **(A) Slack API トークン不足** | `apps.user.connection.update` を呼ぶためのトークン（Slack User token `xoxp-`）がない |
| **(B) 外部 OAuth トークンの取得手段がない** | Deno SDK External Auth が使えないため、外部サービスへの per-user OAuth トークンを Slack 管理で取得できない |

0012番の文脈と 0014番のタスク内容から、**解釈 (B) が正しい**。

つまりユーザーは「Deno SDK External Auth のように Slack がトークンを管理してくれる仕組みがなくなり、Connection Reporting（user_report）を機能させるための外部 OAuth トークンをどこから持ってくるのか分からない」と感じている。

---

### 3. Connection Reporting の本質的な役割の再確認

**ファイル**: `docs/enterprise-search/connection-reporting.md`

> "Slack's connection reporting feature allows your app to **communicate** a user's authentication status, or connection status, directly to Slack. By offloading the UI management for 'connect/disconnect' states to Slack, you can ensure a consistent user experience while reducing development overhead."

重要なポイント：
- Connection Reporting は **UI 管理を Slack に委譲**する機能
- 「接続/切断」ボタンの表示状態を Slack が管理する
- **OAuth トークンの取得・管理は Connection Reporting の責務ではない**

#### Connection Reporting の役割と限界

| 役割 | Slack が管理するもの | アプリが管理するもの |
|---|---|---|
| UI | 「Connect」/「Connected」ボタン表示 | — |
| イベント通知 | `user_connection` イベント発火 | イベントハンドラの実装 |
| OAuth フロー | **担当しない** | OAuth フロー全体（認可 URL 生成・リダイレクト・コールバック処理） |
| トークン管理 | **担当しない** | トークンの保存・取得・リフレッシュ・失効処理 |
| 接続状態 | UI の表示更新のみ | アプリ独自データストアでの状態管理 |

---

### 4. 矛盾の解消：外部 OAuth トークンの取得手段は「アプリの独自 OAuth フロー」

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`（行 303）

> "For example: _Authentication Required: Please visit https://getauthhere.slack.dev to authenticate your account._"

Slack は公式ドキュメントで「ユーザーが外部サービスに未接続の場合、`functions.completeError` で認証要求メッセージ（外部サービスへのリンク付き）を返す」パターンを**明示的に想定**している。

これは Connection Reporting ≠ Slack が外部 OAuth トークンを管理するということを示している。

#### 0009番の調査で確認済みの完全なアーキテクチャ（ファイル: `logs/0009_enterprise-search-external-auth-integration.md`）

```
フェーズ1: 接続フロー（user_connection: connect）
  ユーザー → Slack 検索UI:「Connect」クリック
      ↓
  Slack → アプリ: user_connection イベント (subtype: connect)
    - event.user = Slack user_id
    - event.trigger_id = モーダル開始用 trigger_id
      ↓
  アプリ → Slack: views.open (trigger_id 使用)
    - モーダルに外部サービスへの OAuth 認可 URL を表示
      ↓
  ユーザー → 外部サービス: OAuth フロー完了（ブラウザ）
      ↓
  外部サービス → アプリ: OAuth callback (認可コード)
      ↓
  アプリ → 外部サービス: トークン交換（認可コード → アクセストークン）
      ↓
  アプリ: アクセストークンを自社データストアに保存
    - キー: Slack user_id (event.user)
    - バリュー: アクセストークン（+ リフレッシュトークン + 有効期限）
      ↓
  アプリ → Slack: apps.user.connection.update (user_id, status: "connected")
      ↓
  Slack → ユーザー: 検索UI が「Connected」表示に更新
```

**ポイント**: Slack が提供する `user_connection` イベントの `trigger_id` を使ってモーダルを開き、そのモーダルの中でアプリが**独自の外部 OAuth フロー**を案内する。Slack はこの OAuth フローの**起動点（trigger_id）を提供するだけ**で、トークンの取得・管理はすべてアプリの責任。

#### 矛盾が解消される理由

```
[誤解] Deno SDK External Auth が使えない
        → Connection Reporting（user_report）を動かすための OAuth トークンがない

[正解] Deno SDK External Auth が使えない
        → Slack が外部 OAuth トークンを管理してくれる仕組みがない（これは正しい）
        → しかし、Connection Reporting はそもそも Slack に外部 OAuth トークン管理を求めていない
        → Connection Reporting は「Connect ボタンのクリック → アプリへのイベント通知」を提供するだけ
        → 外部 OAuth フローとトークン管理はアプリが独自に実装する
        → アプリは自社データストアに外部 OAuth トークンを保存し、検索時に取得して使用する
```

---

### 5. `apps.user.connection.update` のトークン要件（副次的な調査結果）

調査中に `apps.user.connection.update` のスコープ記載が他の API と異なることを発見した。

**ファイル**: `docs/reference/methods/apps.user.connection.update.md`（行 41-44）

```
Scopes
User token:
users:write
```

**ファイル**: `docs/reference/methods/users.setActive.md`（行 41-48）

```
Scopes
Bot token: users:write
User token: users:write
```

他の `users:write` を使う API（`users.setActive`, `users.setPresence`）は **Bot token と User token の両方**が記載されているのに対し、`apps.user.connection.update` は **User token のみ**の記載。

**ファイル**: `docs/reference/scopes/users.write.md`

```
Supported token types: Bot, User, Legacy Bot
```

`users:write` スコープ自体は Bot token でも使用可能。

#### この矛盾の解釈

- もし `apps.user.connection.update` が本当に User token のみで動作するなら、Enterprise Search（Bot token で動作する Bolt アプリ）では Connection Reporting が使えなくなる
- Connection Reporting は Enterprise Search の唯一のドキュメント化されたユースケース
- Bolt SDK の `app.client.apps_user_connection_update`（デフォルトは Bot token を使用）が SDK として提供されている
- 0009番の Bolt Python サンプルコードは `App(token=SLACK_BOT_TOKEN)` で初期化して呼び出している

**最も蓋然性の高い解釈**: `apps.user.connection.update` の API ドキュメントは**不完全**であり、実際には Bot token でも `users:write` スコープがあれば動作する。決定的な証拠はドキュメントスナップショット外の公式サンプルアプリ（`bolt-python-search-template`, `bolt-ts-search-template`）にある。

---

### 6. Enterprise Search + Connection Reporting の実装に必要なものの整理

| 必要なもの | 取得方法 | Slack が管理するか |
|---|---|---|
| Bot token (`xoxb-`) | アプリのインストール時に自動取得 | Slack が発行（Bolt が管理） |
| `users:write` スコープ | Manifest の `oauth_config.scopes.bot` に追加 | — |
| `user_connection` イベントの受信 | `users:write` スコープが必要（上記で対応） | — |
| 外部サービスへの per-user OAuth トークン | アプリ独自の OAuth フロー（コールバックエンドポイント実装）で取得 | **Slack は管理しない**（アプリの責任） |
| 接続状態の更新 | `apps.user.connection.update` を Bot token で呼ぶ | Slack が UI 表示を管理 |

**重要**: 「外部サービスへの per-user OAuth トークン」を Slack が管理してくれないことは問題ではない。Deno SDK External Auth が使えないことは、この OAuth トークン管理をアプリが自前で実装する必要があることを意味しており、それが Connection Reporting の設計思想そのものである。

---

## 判断・意思決定

### 「user_report を動かすための OAuth トークンがない」= Connection Reporting の誤解から来る矛盾

矛盾の根源は「Connection Reporting = Slack が外部 OAuth トークンを管理してくれる仕組み」という誤解。

実際には：
- **Connection Reporting は UI scaffolding のみ**（「Connect」/「Connected」ボタンの状態管理を Slack に委譲するだけ）
- **外部 OAuth トークンの管理はアプリの責任**（Connection Reporting とは独立した問題）
- Deno SDK External Auth が使えないことは「Slack が外部 OAuth トークンを管理する仕組みが使えない」という意味であり、これは Connection Reporting の設計前提とは無関係

### 0009番の調査が矛盾の解消に直接答えている

0009番の調査（`logs/0009_enterprise-search-external-auth-integration.md`）が既に完全なアーキテクチャを示している：
1. `user_connection` イベント（subtype: connect）受信
2. `trigger_id` で `views.open` → モーダルに外部サービスの認証 URL を表示
3. ユーザーがブラウザで外部サービスへ OAuth 認証
4. アプリの OAuth callback エンドポイントでトークンを受け取り自社 DB に保存
5. `apps.user.connection.update` で Slack に接続状態を報告

これは「Slack が管理する OAuth トークン」を一切使わない完全な実装。

### Bot-vs-User-token の矛盾はドキュメントの不完全性

`apps.user.connection.update` の Scopes に "Bot token" が記載されていない点は気になるが、以下の理由から Bot token でも動作すると推定される：
- Connection Reporting の唯一のユースケースが Enterprise Search（Bot アプリのみ）
- Bolt SDK の `app.client.apps_user_connection_update` がデフォルトで Bot token を使う
- 決定的な証拠は公式サンプルアプリ（ドキュメントスナップショット外）

---

## 問題・疑問点

1. **`apps.user.connection.update` の Bot token 対応**: ドキュメントには User token のみ記載されているが、実際に Bot token で動作するかどうかはドキュメントスナップショットの範囲では確認できない。公式サンプルアプリ（`bolt-python-search-template` / `bolt-ts-search-template`）のコードで確認可能と推定。

2. **モーダルから OAuth フロー完了後のモーダル自動クローズ**: `views.open` でモーダルを開いた後、ユーザーが外部ブラウザで OAuth 認証を完了した際にモーダルを自動的に閉じる方法（`views.update` + WebSocket など）は本調査の範囲外。
