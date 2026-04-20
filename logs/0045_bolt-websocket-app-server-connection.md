# Bolt フレームワークを WebSocket で Slack App に接続する方法 - 調査ログ

## 調査日時
2026-04-20

## タスク概要

**知りたいこと**: WebSocketで繋ぐ場合、Boltフレームワークで実装したアプリケーションサーバーをどうやって繋げば良いのか

**目的**: サンプルのページではSlack CLIを使っての管理がなされている。どうやってSlack Appとアプリケーションサーバーを紐付ければ良いのかがわからない。

---

## 調査ファイル一覧

- `/docs/apis/events-api/using-socket-mode.md`
- `/docs/apis/events-api/comparing-http-socket-mode.md`
- `/docs/tools/bolt-js/concepts/socket-mode.md`
- `/docs/tools/bolt-js/getting-started.md`
- `/docs/tools/bolt-js/creating-an-app.md`
- `/docs/tools/bolt-js/ja-jp/concepts/socket-mode.md`
- `/docs/tools/bolt-python/concepts/socket-mode.md`
- `/docs/tools/bolt-python/getting-started.md`
- `/docs/tools/bolt-python/creating-an-app.md`
- `/docs/tools/bolt-python/ja-jp/concepts/socket-mode.md`
- `/docs/tools/java-slack-sdk/guides/socket-mode.md`
- `/docs/tools/java-slack-sdk/guides/getting-started-with-bolt.md`
- `/docs/tools/java-slack-sdk/ja-jp/guides/socket-mode.md`
- `/docs/tools/java-slack-sdk/ja-jp/guides/getting-started-with-bolt-socket-mode.md`
- `/docs/tools/node-slack-sdk/socket-mode.md`
- `/docs/tools/python-slack-sdk/socket-mode.md`
- `/docs/tools/node-slack-sdk/reference/socket-mode/classes/SocketModeClient.md`
- `/docs/reference/app-manifest.md`

---

## 調査アプローチ

Socket Mode / WebSocket に関連するキーワードでドキュメント全体を横断的に調査した。
- キーワード: "socket mode", "websocket", "appToken", "app_token", "SocketModeReceiver", "App-Level Token"
- 対象言語: JavaScript (Bolt JS), Python (Bolt Python), Java (Bolt Java)
- 約88ファイルでSocket Modeへの言及を確認

---

## 調査結果

### 1. Socket Mode（WebSocket）の概要

Socket Mode は HTTP の代わりに WebSocket でイベントを受信するモード。

**特性比較:**

| 特性 | HTTP | Socket Mode (WebSocket) |
|-----|------|------------------------|
| 接続パターン | Request-Response | 双方向 |
| プロトコル | ステートレス | ステートフル |
| スケーラビリティ | 水平スケーリング可能 | 制限あり（最大10接続/app） |
| 推奨用途 | 本番環境 | 開発環境、ファイアウォール内 |
| 市場配布 | Slack Marketplace対応 | 非対応 |
| セットアップ | 複雑（Request URL等必要） | シンプル（WebSocket URL自動生成） |

ドキュメント引用:
> "For convenience, ease of setup, and ability to work behind a firewall, we recommend using Socket Mode when developing your app and using it locally. Once deployed and published for use in a team setting, we recommend using HTTP request URLs."

---

### 2. 結論: Slack CLI は不要

**Socket Mode は Slack CLI 不要で実装可能。**

必要なものは3つだけ:
1. **App-Level Token** (`xapp-` で始まる) - Socket Mode接続用
2. **Bot Token** (`xoxb-` で始まる) - API呼び出し用
3. **Bolt フレームワーク** (Python / JS / Java)

Slack CLI はローカル開発の補助ツールに過ぎず、Socket Mode の必須要件ではない。

---

### 3. Slack App 側の設定手順（api.slack.com）

#### Step 1: App-Level Token の作成
1. [Slack API Dashboard](https://api.slack.com/apps) でアプリを選択
2. **Settings > Basic Information** にアクセス
3. **App-Level Tokens** セクションで「Generate Token and Scopes」をクリック
4. トークン名を入力（例: "Development"）
5. スコープに **`connections:write`** を追加（必須）
6. 「Generate」をクリック → `xapp-` で始まるトークンが生成される

#### Step 2: Socket Mode の有効化
1. **Settings > Socket Mode** にアクセス
2. 「Enable Socket Mode」トグルを ON にする

#### Step 3: イベント購読の設定
1. **Features > Event Subscriptions** にアクセス
2. 「Enable Events」トグルを ON にする
3. **Request URL は設定不要**（Socket Mode 時はURLは使われない）
4. 必要なイベント（例: `app_mention`, `message.channels`）をサブスクライブ

#### Step 4: Bot Token の取得
1. **OAuth & Permissions** で Bot Token Scopes を必要分追加
2. 「Install to Workspace」でアプリをインストール
3. `xoxb-` で始まる Bot Token を取得

---

### 4. Bolt フレームワークでの Socket Mode 実装

#### JavaScript (Bolt JS)

**最も簡単な方法（socketMode: true）:**
```javascript
const { App } = require('@slack/bolt');

const app = new App({
  token: process.env.BOT_TOKEN,       // xoxb-token
  socketMode: true,                   // Socket Mode 有効化
  appToken: process.env.APP_TOKEN,    // xapp-token
});

(async () => {
  await app.start();
  app.logger.info('⚡️ Bolt app started');
})();
```

**SocketModeReceiver を使う方法（カスタマイズ時）:**
```javascript
const { App, SocketModeReceiver } = require('@slack/bolt');

const socketModeReceiver = new SocketModeReceiver({
  appToken: process.env.APP_TOKEN,
  // OAuth対応の場合
  // clientId: process.env.CLIENT_ID,
  // clientSecret: process.env.CLIENT_SECRET,
  // stateSecret: process.env.STATE_SECRET,
  // scopes: ['channels:read', 'chat:write', ...],
});

const app = new App({
  receiver: socketModeReceiver,
  token: process.env.BOT_TOKEN
});

(async () => {
  await app.start();
  app.logger.info('⚡️ Bolt app started');
})();
```

**起動方法（Slack CLI 不要）:**
```bash
export SLACK_BOT_TOKEN=xoxb-...
export SLACK_APP_TOKEN=xapp-...
node app.js
```

---

#### Python (Bolt Python)

**基本的な使用方法:**
```python
import os
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

app = App(token=os.environ["SLACK_BOT_TOKEN"])

@app.message("hello")
def message_hello(message, say):
    say(f"Hey <@{message['user']}>!")

if __name__ == "__main__":
    handler = SocketModeHandler(app, os.environ["SLACK_APP_TOKEN"])
    handler.start()
```

**Async 版（aiohttp）:**
```python
from slack_bolt.app.async_app import AsyncApp
from slack_bolt.adapter.socket_mode.async_handler import AsyncSocketModeHandler
import asyncio, os

app = AsyncApp(token=os.environ["SLACK_BOT_TOKEN"])

async def main():
    handler = AsyncSocketModeHandler(app, os.environ["SLACK_APP_TOKEN"])
    await handler.start_async()

if __name__ == "__main__":
    asyncio.run(main())
```

**利用可能なアダプター:**
- `slack_bolt.adapter.socket_mode` - デフォルト（slack_sdk ベース）
- `slack_bolt.adapter.socket_mode.websocket_client` - websocket_client ライブラリ使用
- `slack_bolt.adapter.socket_mode.aiohttp` - aiohttp 使用（async）
- `slack_bolt.adapter.socket_mode.websockets` - websockets 使用（async）

**起動方法（Slack CLI 不要）:**
```bash
export SLACK_BOT_TOKEN=xoxb-...
export SLACK_APP_TOKEN=xapp-...
python3 app.py
```

---

#### Java (Bolt Java)

**Maven 依存関係:**
```xml
<dependency>
  <groupId>com.slack.api</groupId>
  <artifactId>bolt-socket-mode</artifactId>
  <version>1.48.0</version>
</dependency>
<dependency>
  <groupId>javax.websocket</groupId>
  <artifactId>javax.websocket-api</artifactId>
  <version>1.1</version>
</dependency>
<dependency>
  <groupId>org.glassfish.tyrus.bundles</groupId>
  <artifactId>tyrus-standalone-client</artifactId>
  <version>1.20</version>
</dependency>
```

**基本コード:**
```java
import com.slack.api.bolt.App;
import com.slack.api.bolt.socket_mode.SocketModeApp;

String botToken = System.getenv("SLACK_BOT_TOKEN");
App app = new App(AppConfig.builder().singleTeamBotToken(botToken).build());

app.event(AppMentionEvent.class, (req, ctx) -> {
    ctx.say("Hi there!");
    return ctx.ack();
});

String appToken = System.getenv("SLACK_APP_TOKEN");
SocketModeApp socketModeApp = new SocketModeApp(appToken, app);
socketModeApp.start();  // ブロッキング（または startAsync() でノンブロッキング）
```

---

### 5. App-Level Token の内部動作

アプリ起動時、appToken を使用して以下が自動実行される:
```
POST https://slack.com/api/apps.connections.open
  Authorization: Bearer xapp-1-A...
```

レスポンス例:
```json
{
  "ok": true,
  "url": "wss://wss.slack.com/link/?ticket=1234-5678"
}
```

この WebSocket URL に自動接続し、以後のイベント受信は WebSocket 経由で行われる。

**Hello メッセージ受信（接続確立後）:**
```json
{
  "type": "hello",
  "connection_info": {
    "app_id": "A1234"
  },
  "num_connections": 1,
  "debug_info": {
    "host": "applink-….",
    "started": "2020-10-11 12:12:12.120",
    "build_number": 54,
    "approximate_connection_time": 3600
  }
}
```

- 接続は数時間後に自動更新される
- 最大10接続/アプリまで同時接続可能

---

### 6. イベント受信の流れ

Socket Mode での Events API ペイロード構造:
```json
{
  "payload": {
    "type": "event_callback",
    "event": {
      "type": "app_mention",
      "user": "U123ABC456",
      ...
    }
  },
  "envelope_id": "dbdd0ef3-1543-4f94-bfb4-133d0e6c1545",
  "type": "events_api",
  "accepts_response_payload": false
}
```

**アプリ側での確認応答（必須）:**
```json
{
  "envelope_id": "dbdd0ef3-1543-4f94-bfb4-133d0e6c1545"
}
```

---

### 7. App Manifest での Socket Mode 設定

```yaml
settings:
  socket_mode_enabled: true
  event_subscriptions:
    bot_events:
      - app_mention
      - message.im
    # Request URL は不要
  interactivity:
    is_enabled: true
    # request_url は不要
```

---

## まとめ

Socket Mode（WebSocket）での Bolt アプリと Slack App の接続は以下で実現できる:

1. **Slack App 設定（api.slack.com）**:
   - App-Level Token を作成（`connections:write` スコープ付き）
   - Socket Mode を有効化
   - Event Subscriptions を有効化（Request URL は不要）

2. **コード側**:
   - `xapp-` トークン（App-Level Token）と `xoxb-` トークン（Bot Token）の2つをセット
   - Bolt JS: `{ socketMode: true, appToken: process.env.APP_TOKEN }`
   - Bolt Python: `SocketModeHandler(app, os.environ["SLACK_APP_TOKEN"])`
   - Bolt Java: `new SocketModeApp(appToken, app)`

**Slack CLI は一切不要。** Slack CLI はあくまでローカル開発の補助ツールであり、Socket Mode の仕組み自体とは独立している。
