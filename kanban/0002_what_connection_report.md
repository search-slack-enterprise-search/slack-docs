# コネクションレポートって何？
## 知りたいこと

Enterprise SearchのConnection Reportとは何か知りたい。

## 目的
何を目的とした機能なのかがよくわからない。
エンドポイントとの接続状況を見るだけなら、ユーザーのPermissionを求める理由がわからない。

## プラン

### 調査結果の要約

Connection Report は「エンドポイント（サーバー）の死活監視」ではなく、**個々のユーザーが外部データソースに認証（ログイン）済みかどうかを Slack UI で管理する機能**。

- Slack が「接続/切断」の UI を一元管理し、アプリ開発者の負担軽減と一貫した UX を提供
- フロー: ユーザーが Slack で「Connect」→ アプリがモーダルで認証 → `apps.user.connection.update` で状態報告 → Slack UI 更新
- `users:write` が必要な理由: ユーザー個人の接続状態を「書き換える」操作であり、アプリが勝手に変更できないようにする設計

### 調査対象ドキュメント
- `docs/enterprise-search/connection-reporting.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/enterprise-search-access-control.md`
- `docs/reference/events/user_connection.md`
- `docs/reference/methods/apps.user.connection.update.md`

### 成果物
- ログファイル (`logs/0002_what_connection_report.md`) に調査結果の詳細を記録
- kanban ファイルに完了サマリーを追記

---

## 完了サマリー

- **完了日時**: 2026-04-16T13:52:25+09:00
- **ログファイル**: `logs/0002_what_connection_report.md`

### Connection Report とは

Enterprise Search アプリが**ユーザーの認証ステータス（外部データソースへのログイン状態）**を Slack に報告する機能。Slack が「Connect / Disconnect」の UI を一元管理し、一貫した UX を提供する。

**「エンドポイントとの接続状況を見る」機能ではない。** "Connection" は「サーバーへの TCP/HTTP 接続」ではなく、「ユーザーが外部サービスに認証済みかどうか」を指す。

### フロー

1. ユーザーが Slack UI で「Connect」をクリック
2. Slack が `user_connection` イベント（subtype: connect, `trigger_id` 付き）をアプリに送信
3. アプリが `trigger_id` でモーダルを開き、外部システムの認証フローを案内
4. 認証完了後、アプリが `apps.user.connection.update` API で `status: connected` を報告
5. Slack UI が更新される（切断時は `status: disconnected`）

### Permission（`users:write`）が必要な理由

- Connection Report は「読み取り」ではなく「**書き込み**」操作（`apps.user.connection.update` = ユーザーの接続状態の更新）
- アプリがユーザー個人の接続状態を書き換えるため、明示的な Permission が必要
- Slack のセキュリティモデルとして、アプリが無断でユーザー情報を変更できないようにする設計
- なお Connection Reporting はオプション機能であり、Enterprise Search のコア機能（検索結果の返却）には `users:write` は不要

### 参照ドキュメント

- `docs/enterprise-search/connection-reporting.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/enterprise-search-access-control.md`
- `docs/enterprise-search/index.md`
- `docs/reference/events/user_connection.md`
- `docs/reference/methods/apps.user.connection.update.md`
