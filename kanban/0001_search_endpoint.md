# search_endpoint
## 知りたいこと
Enterprise Searchを実行させるときに必要なエンドポイント

## 目的
Enterprise Searchのドキュメントを見ると、別途アプリケーションサーバーを動かしているように見える。
しかし、ぱっとドキュメントを見た限り、アプリケーションサーバーのエンドポイントを設定する項目が見つからない。
どうやってエンドポイントを設定している？

## プラン

1. Explore エージェントで Enterprise Search ドキュメント・マニフェストリファレンス・Events API ドキュメントを並列調査
2. 調査結果をログファイルに記録
3. kanban ファイルへ完了サマリー追記

## 完了サマリー

- 完了日時: 2026-04-16T13:42:00+09:00
- ログ: `logs/0001_search_endpoint.md`

### 結論

Enterprise Search には**専用のエンドポイント設定項目がない**。Enterprise Search ドキュメントのマニフェスト例がトランスポート設定を省略しているため「設定項目が見つからない」と感じるが、これは Enterprise Search 固有ではなく Slack アプリ全般に共通する標準設定であるため省略されているだけ。

アプリケーションサーバーのエンドポイント設定は以下の2方式のいずれかで行う:

#### 方式1: HTTP Request URL（本番環境推奨）

マニフェストの `settings.event_subscriptions.request_url` にサーバーの HTTPS URL を指定する。

```json
"settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
        "request_url": "https://your-server.example.com/slack/events",
        "bot_events": ["function_executed", "entity_details_requested"]
    },
    "function_runtime": "remote"
}
```

- Slack がこの URL に HTTP POST でイベントを送信する
- 初回設定時に `url_verification` ハンドシェイクが必要
- HTTPS 必須・イベント受信後3秒以内に HTTP 2xx を返す必要がある

#### 方式2: Socket Mode（開発時・ファイアウォール内推奨）

マニフェストの `settings.socket_mode_enabled` を `true` にする（公開 URL 不要）。

```json
"settings": {
    "org_deploy_enabled": true,
    "socket_mode_enabled": true,
    "event_subscriptions": {
        "bot_events": ["function_executed", "entity_details_requested"]
    },
    "function_runtime": "remote"
}
```

- 公開 HTTP エンドポイント不要（ファイアウォール内でも動作）
- アプリ側から `apps.connections.open` API で動的 WebSocket URL を取得
- App-level token (`xapp-***`) が必要
- Enterprise Search ドキュメント 347 行目でも言及あり

#### いずれかが必須である根拠

`docs/app-manifests/configuring-apps-with-app-manifests.md`（107行目）のバリデーションエラー:
```
"Event Subscription requires either Request URL or Socket Mode Enabled"
```
