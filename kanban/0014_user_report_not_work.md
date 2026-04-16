# user_reportが動かす方法がないのだがどうしたらいいのか
## 知りたいこと
0012番の調査結果を踏まえると、user_reportを動かすためのOAuthトークンがないことになる。
つまり、user_reportという機能はあるものの、それを動かすための認証を通す手段が存在しないことになる。
この矛盾はどうやって解消する？

## 目的
回答の内容が矛盾をはらんだままになっている。
どうしていいかが全くわからない。

## 調査サマリー

**「user_report を動かすための OAuth トークンがない」という矛盾は、Connection Reporting に対する誤解から来ている。矛盾は存在しない。**

### 矛盾が生じた原因

0012番の調査で「Deno SDK External Auth（ROSI）は Enterprise Search では使えない」と確認された。ユーザーはこれを受けて「Connection Reporting（user_report）を動かすための外部 OAuth トークンを Slack が管理してくれる仕組みがない」と感じた。

しかし、**Connection Reporting はそもそも外部 OAuth トークンを管理する機能ではない**。

### Connection Reporting の本質

Connection Reporting は「UI scaffolding」のみを提供する機能：
- **Slack が担当すること**: 「Connect」/「Connected」/「Disconnect」ボタンの表示状態管理
- **アプリが担当すること**: 外部サービスへの OAuth フロー全体、トークンの取得・保存・リフレッシュ

Connection Reporting が提供するのは「Connect ボタンのクリック → `user_connection` イベントの通知（`trigger_id` 付き）」だけ。このイベントをきっかけにアプリが独自の OAuth フローを起動する。

### 矛盾の解消

```
[誤解] Deno SDK External Auth が使えない
        → Connection Reporting を動かす OAuth トークンがない

[正解] Deno SDK External Auth が使えない
        → Slack が外部 OAuth トークンを管理してくれる仕組みがない（これは正しい）
        → しかし Connection Reporting はそもそも Slack に外部 OAuth トークン管理を求めていない
        → アプリが独自の OAuth フロー（callback エンドポイント + 自社 DB）を実装する
        → これが Connection Reporting の設計思想そのもの
```

### 実装フロー（0009番で確認済み）

1. ユーザーが「Connect」クリック → `user_connection` イベント（`trigger_id` 付き）
2. アプリが `views.open` でモーダルを開く → 外部サービスの認証 URL を表示
3. ユーザーがブラウザで外部 OAuth 認証を完了
4. アプリの OAuth callback エンドポイントでトークンを受け取り自社 DB に保存（キー: Slack user_id）
5. アプリが `apps.user.connection.update(status: "connected")` で Slack に報告

### 副次的な発見

`apps.user.connection.update` の API ドキュメントは "User token: `users:write`" のみ記載（Bot token の記載なし）。しかし Connection Reporting の唯一のユースケースは Enterprise Search（Bolt = Bot token）であり、Bolt SDK でもデフォルト Bot token で同メソッドを呼ぶため、ドキュメントが不完全な可能性が高い。決定的な証拠は公式サンプルアプリ（`bolt-python-search-template` / `bolt-ts-search-template`）にある。

## 完了サマリー

- **調査日**: 2026-04-16
- **ログファイル**: `logs/0014_user_report_not_work.md`
- **結論**: 矛盾は存在しない。Connection Reporting は外部 OAuth トークンを管理する機能ではなく、UI scaffolding のみを提供する。外部 OAuth フローとトークン管理はアプリが独自に実装する（これは 0009番で確認済みのアーキテクチャ）。