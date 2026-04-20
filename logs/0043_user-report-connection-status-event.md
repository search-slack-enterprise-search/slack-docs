# User Report 表示時の接続状態管理イベント 調査ログ

## タスク概要

- **kanban ファイル**: `kanban/0043_user-report-connection-status-event.md`
- **知りたいこと**: user_report を表示するときに何を実装してコレクションの状態を管理するのか？User Report を呼び出した時に状態を問うイベントがあると予想されるが、そのイベントを知りたい。
- **目的**: 接続と切断のフローはわかった。User Report 表示時に接続状態を問うイベントが存在するかどうかを確認する。
- **調査日**: 2026-04-20

---

## 調査ファイル一覧

| ファイルパス | 内容 |
|---|---|
| `docs/enterprise-search/connection-reporting.md` | Connection Reporting 公式ドキュメント |
| `docs/reference/events.md` | 全イベント一覧 |
| `docs/reference/events/user_connection.md` | user_connection イベントリファレンス |
| `docs/reference/methods.md` | 全 API メソッド一覧 |
| `docs/reference/methods/apps.user.connection.update.md` | apps.user.connection.update API リファレンス |
| `docs/tools/node-slack-sdk/reference/web-api/interfaces/AppsUserConnectionUpdateArguments.md` | Node SDK の型定義 |

---

## 調査アプローチ

1. `connection-reporting.md` を再読し、状態管理の仕組みを確認する
2. `docs/reference/events.md`（全イベント一覧）を確認し、User Report 表示時に発火するイベントが存在するかどうかを確認する
3. `docs/reference/methods.md`（全 API メソッド一覧）を確認し、接続状態を「取得（GET）」するメソッドが存在するかどうかを確認する
4. 調査結果から、User Report 表示時の接続状態管理の仕組みを整理する

---

## 調査結果

### 1. Connection Reporting の状態管理の仕組み（再確認）

**ファイル**: `docs/enterprise-search/connection-reporting.md` 行 17

> "The app is always expected to invoke the `apps.user.connection.update` API method in its connecting flow to notify Slack when a user's connection status changes. **Otherwise, Slack will assume the status for this user has not changed.**"

この一文が核心を示している：

- Slack はアプリが `apps.user.connection.update` を呼ばない限り、「ステータスは変わっていない」と仮定する
- つまり **Slack は最後に報告されたステータスを保持し、そのまま表示し続ける**
- Slack がアプリに「今の状態は？」と問い合わせることはない（**Pull なし**）

---

### 2. 全イベント一覧の確認

**ファイル**: `docs/reference/events.md`

全イベント一覧を確認した結果、接続状態に関するイベントは以下のみ：

| イベント | 説明 |
|---|---|
| `user_connection` | A member's user connection status change **requested** |

**「User Report が表示されたとき」に発火するイベントは存在しない。**

全 100+ のイベントの中で、Connection Reporting / User Report の表示に関するイベントは `user_connection` のみであり、この `user_connection` イベントは：
- subtype: `connect` → ユーザーが "Connect" ボタンをクリックしたとき
- subtype: `disconnect` → ユーザーが "Disconnect" ボタンをクリックしたとき

にのみ発火する。**User Report の UI が表示されたときにイベントは発火しない。**

---

### 3. 全 API メソッド一覧の確認

**ファイル**: `docs/reference/methods.md` 行 136

```
| apps.user.connection.update | Updates the connection status between a user and an app. |
```

**`apps.user.connection.*` 系のメソッドは `apps.user.connection.update` の1つのみ。**

接続状態を「読み取る（GET）」メソッドは存在しない。全 API メソッド一覧を確認した結果：
- `apps.user.connection.get` → 存在しない
- `apps.user.connection.status` → 存在しない
- `apps.user.connection.retrieve` → 存在しない

---

### 4. 結論：User Report 表示時の接続状態管理の仕組み

**User Report が表示されるとき、Slack はアプリへのクエリを一切行わない。**

Slack は「最後にアプリから `apps.user.connection.update` で報告された状態」をそのまま表示する。

```
【ユーザーの予想】
  User Report が表示される
      ↓
  Slack → アプリ: 「現在の接続状態は？」（ステータス問い合わせイベント）
      ↓
  アプリ → Slack: 「connected / disconnected」
      ↓
  Slack → ユーザー: 状態を表示

【実際の仕組み】
  アプリ → Slack: apps.user.connection.update(status: "connected") ← 随時 Push
      ↓
  Slack: 受け取った状態を保持
      ↓
  User Report が表示される
      ↓
  Slack → ユーザー: 保持している状態（最後に報告された値）をそのまま表示
  ← アプリへの問い合わせはない
```

---

### 5. 接続状態の「ずれ」が発生するケース

Push モデルであるため、アプリが能動的に状態を更新しない限り、表示されている状態と実際の状態が乖離することがある。

| ケース | 表示される状態 | 実際の状態 | 原因 |
|---|---|---|---|
| 外部トークンが期限切れになった | connected（古い値） | disconnected（認証切れ） | アプリが `apps.user.connection.update(disconnected)` を呼んでいない |
| ユーザーが外部サービス側でアカウントを削除した | connected | disconnected | 同上 |
| ユーザーが Connect フロー完了後に `update` を呼んでいない | disconnected | connected | バグ（実装漏れ） |

#### 状態の乖離を防ぐためのベストプラクティス（ドキュメントの記述を踏まえた推奨）

1. **検索時の状態同期（推奨）**: `function_executed` イベント（検索関数）が実行された際に外部トークンの有効性を確認し、無効であれば `apps.user.connection.update(disconnected)` を呼んで状態を同期する

   ```
   function_executed（検索リクエスト受信）
       ↓
   アプリ: 自社 DB からユーザーの外部 OAuth トークンを取得
       ↓
   if トークンが存在しない or 無効:
       apps.user.connection.update(user_id, status: "disconnected")
       functions.completeError("Authentication Required: Please visit ... to authenticate.")
   else:
       外部サービスで検索実行 → functions.completeSuccess(search_results)
   ```

2. **切断時の状態同期**: 外部サービスがトークン失効の webhook を提供する場合、それを受け取って `apps.user.connection.update(disconnected)` を呼ぶ

---

### 6. Node SDK の型定義から見る API の完全性確認

**ファイル**: `docs/tools/node-slack-sdk/reference/web-api/interfaces/AppsUserConnectionUpdateArguments.md`

```typescript
interface AppsUserConnectionUpdateArguments extends TokenOverridable {
  user_id: string;   // The identifier for the user receiving the status update.
  status: string;    // The connection status value to assign to the user. `connected` or `disconnected`.
}
```

SDK レベルでも `update` の引数のみ定義されており、状態を取得するインターフェースは存在しない。

---

## 判断・意思決定

### 「状態を問うイベント」は存在しないという結論

調査の結果、User Report 表示時にアプリへの問い合わせイベントは存在しないことが確認できた。

根拠：
1. `docs/reference/events.md` の全イベント一覧に、Connection Reporting の表示に関するイベントは `user_connection`（connect/disconnect サブタイプのみ）しか存在しない
2. `docs/reference/methods.md` の全メソッド一覧に `apps.user.connection.*` 系は `update` のみ（GET/status メソッドなし）
3. `connection-reporting.md` の "Otherwise, Slack will assume the status for this user has not changed" という記述が Push モデルを明示している

### 接続状態管理はアプリの責任

Slack が状態を保持・表示するが、その状態の正確性を維持する責任はアプリにある。特に：
- 外部トークンの有効期限管理
- トークン失効時の `apps.user.connection.update(disconnected)` 呼び出し
- 検索関数（`function_executed`）でのトークン有効性チェックと状態同期

---

## 問題・疑問点

1. **Slack が保持している接続状態の永続性**: Slack が最後に報告された接続状態をどのくらいの期間保持するのか、アプリがアンインストール・再インストールされた際にリセットされるのかどうかはドキュメントの範囲外。

2. **接続状態の確認 API**: 現状では `apps.user.connection.update` のみが存在し、現在の接続状態を取得する API がない。アプリが自分の状態を確認するには、自社 DB のトークン存在を確認するしかない。
