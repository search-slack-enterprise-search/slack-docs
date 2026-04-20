# User Report 表示時の接続状態管理イベント

## 知りたいこと

0046の更問い。user_reportを表示するときに何を実装してコレクションの状態を管理するのか？

## 目的

接続と切断のフローはわかった。ただ、これは接続と切断のためのものであり、User Reportを呼び出した時に状態を問うイベントがあると予想されるが、そのイベントを知りたい。

## 調査サマリー

**User Report（Connection Reporting）が表示される際に「状態を問うイベント」は存在しない。Slack は最後にアプリが `apps.user.connection.update` で報告した状態を保持し、そのまま表示する（純粋な Push モデル）。**

### 確認内容

1. **全イベント一覧（`docs/reference/events.md`）を確認**: Connection Reporting に関するイベントは `user_connection`（subtype: connect / disconnect）のみ。User Report 表示時に発火するイベントは存在しない。

2. **全 API メソッド一覧（`docs/reference/methods.md`）を確認**: `apps.user.connection.*` 系のメソッドは `apps.user.connection.update` の1つのみ。接続状態を「取得（GET）」するメソッドは存在しない。

3. **`connection-reporting.md` の核心記述**: "Otherwise, Slack will assume the status for this user has not changed." → Slack はアプリが明示的に更新しない限り、保持している状態を表示し続ける。

### 実際の仕組み

```
アプリ → Slack: apps.user.connection.update(status: "connected") ← 随時 Push
    ↓
Slack: 受け取った状態を保持
    ↓
User Report が表示される
    ↓
Slack → ユーザー: 保持している最後の値をそのまま表示（アプリへの問い合わせなし）
```

### 接続状態の乖離と対処

外部トークンが期限切れになっても Slack 側は `connected` のまま表示し続ける。検索実行時（`function_executed`）にトークンの有効性を確認し、無効であれば `apps.user.connection.update(disconnected)` を呼んで状態を同期させるのがベストプラクティス。

## 完了サマリー

- **調査日**: 2026-04-20
- **ログファイル**: `logs/0043_user-report-connection-status-event.md`
- **結論**: User Report 表示時に Slack からアプリへの「状態問い合わせイベント」は存在しない。Slack が最後に報告された状態を保持・表示するだけ（Push モデル）。状態の正確性はアプリ側が責任を持ち、特にトークン失効時は検索関数内で能動的に `apps.user.connection.update(disconnected)` を呼ぶ必要がある。
