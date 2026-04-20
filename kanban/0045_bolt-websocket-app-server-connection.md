# Bolt フレームワークを WebSocket で Slack App に接続する方法

## 知りたいこと

WebSocketで繋ぐ場合、Boltフレームワークで実装したアプリケーションサーバーをどうやって繋げば良いのか

## 目的

サンプルのページではSlack CLIを使っての管理がなされている。どうやってSlack Appとアプリケーションサーバーを紐付ければ良いのかがわからない。

## 調査サマリー

**Slack CLI は不要。** Socket Mode（WebSocket）は以下の2トークンとBoltフレームワークだけで動作する。

### 必要なもの
1. **App-Level Token**（`xapp-`）: `connections:write` スコープ付き
2. **Bot Token**（`xoxb-`）: 通常の Bot OAuth Token

### Slack App 側の設定（api.slack.com）
1. Settings > Basic Information → App-Level Tokens で `connections:write` スコープ付きトークンを生成
2. Settings > Socket Mode → 「Enable Socket Mode」を ON
3. Features > Event Subscriptions → ON にする（Request URL は不要）
4. OAuth & Permissions → Bot Scopes 設定 → Install to Workspace → Bot Token 取得

### Bolt フレームワークでの接続

**Bolt JS:**
```javascript
const app = new App({
  token: process.env.SLACK_BOT_TOKEN,   // xoxb-
  socketMode: true,
  appToken: process.env.SLACK_APP_TOKEN, // xapp-
});
await app.start();
```

**Bolt Python:**
```python
app = App(token=os.environ["SLACK_BOT_TOKEN"])
SocketModeHandler(app, os.environ["SLACK_APP_TOKEN"]).start()
```

**Bolt Java:**
```java
App app = new App();
new SocketModeApp(System.getenv("SLACK_APP_TOKEN"), app).start();
```

### 仕組み
- 起動時に appToken で `apps.connections.open` API を呼び出し、`wss://` URL を取得
- その WebSocket URL に自動接続してイベント受信
- Slack CLI はこの仕組みとは無関係

## 完了サマリー

Socket Mode 接続に Slack CLI は不要。`xapp-` トークン（`connections:write` スコープ）と `xoxb-` トークンの2つを環境変数にセットし、Bolt の `socketMode: true`（JS）または `SocketModeHandler`（Python）を使えばよい。Slack App 側では Socket Mode を有効化するだけでよく、Request URL の設定も不要。
