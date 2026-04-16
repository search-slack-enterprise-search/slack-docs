# カスタムエージェントでのユーザー情報取得 — 調査ログ

## 調査ファイル一覧

- `docs/ai/developing-agents.md`
- `docs/ai/agent-entry-and-interaction.md`
- `docs/ai/agents.md`
- `docs/reference/events/assistant_thread_started.md`
- `docs/reference/events/message.im.md`
- `docs/reference/events/app_mention.md`
- `docs/tools/bolt-python/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-python/concepts/context.md`
- `docs/tools/bolt-js/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-js/concepts/context.md`

---

## 調査アプローチ

「カスタムエージェントの起点ユーザー情報取得」を調査するにあたり、以下の順序で調査した。

1. エントリーポイント別のイベントペイロード構造を確認（`assistant_thread_started`, `message.im`, `app_mention`）
2. BoltフレームワークのAssistantクラスで提供されるユーティリティを確認
3. contextオブジェクトで自動付与されるフィールドを確認

---

## 調査結果

### 1. `assistant_thread_started` イベントのペイロード

ファイル: `docs/reference/events/assistant_thread_started.md`

エージェントコンテナ（スプリットペイン）でユーザーが新しいスレッドを開いたときに発火するイベント。ペイロード内の `assistant_thread` オブジェクトに **`user_id`** が含まれる。

```json
{
  "token": "XXYYZZ",
  "team_id": "T123ABC456",
  "api_app_id": "A123ABC456",
  "event": {
    "type": "assistant_thread_started",
    "assistant_thread": {
      "user_id": "U123ABC456",
      "context": {
        "channel_id": "C123ABC456",
        "team_id": "T07XY8FPJ5C",
        "enterprise_id": "E480293PS82"
      },
      "channel_id": "D123ABC456",
      "thread_ts": "1729999327.187299"
    },
    "event_ts": "1715873754.429808"
  },
  ...
}
```

- `event.assistant_thread.user_id` = アシスタントスレッドを開いたユーザーのID
- `event.assistant_thread.context.channel_id` = ユーザーが現在見ているチャンネルID
- `event.assistant_thread.context.team_id` = ワークスペース（チーム）ID
- `event.assistant_thread.context.enterprise_id` = Enterprise Grid の場合はオーグID

### 2. `message.im` イベントのペイロード

ファイル: `docs/reference/events/message.im.md`

ユーザーがエージェントにメッセージを送ったときに発火するイベント。ペイロード内の `event` オブジェクトに **`user`** フィールドでユーザーIDが含まれる。

```json
{
  "token": "one-long-verification-token",
  "team_id": "T123ABC456",
  "api_app_id": "A0PNCHHK2",
  "event": {
    "type": "message",
    "channel": "D024BE91L",
    "user": "U2147483697",
    "text": "Hello hello can you hear me?",
    "ts": "1355517523.000005",
    "event_ts": "1355517523.000005",
    "channel_type": "im"
  },
  ...
}
```

- `event.user` = メッセージを送ったユーザーのID

### 3. `app_mention` イベントのペイロード

ファイル: `docs/reference/events/app_mention.md`

チャンネルでユーザーがアプリを @メンションしたときに発火するイベント。ペイロード内の `event` に **`user`** フィールドでユーザーIDが含まれる。

```json
{
  "event": {
    "type": "app_mention",
    "user": "U061F7AUR",
    "text": "<@U0LAN0Z89> is it everything a river should be?",
    "ts": "1515449522.000016",
    "channel": "C123ABC456",
    ...
  },
  ...
}
```

- `event.user` = @メンションを送ったユーザーのID

### 4. Bolt Python での取得方法

ファイル: `docs/tools/bolt-python/concepts/using-the-assistant-class.md`, `docs/ai/developing-agents.md`

**`user_message` ハンドラー内 (`respond_in_assistant_thread`) での取得方法:**

```python
@assistant.user_message
def respond_in_assistant_thread(
    client: WebClient,
    context: BoltContext,
    get_thread_context: GetThreadContext,
    logger: logging.Logger,
    payload: dict,
    say: Say,
    set_status: SetStatus,
):
    channel_id = payload["channel"]
    team_id = payload["team"]
    thread_ts = payload["thread_ts"]
    user_id = payload["user"]   # ← ユーザーIDはここで取得
    user_message = payload["text"]
```

- **`payload["user"]`** でユーザーIDが取得できる（`message.im` イベントの `event.user` と同じ値）

**Bolt の `context` オブジェクトに自動付与される情報:**

`docs/tools/bolt-python/concepts/context.md` より:

> All listeners have access to a `context` dictionary, which can be used to enrich requests with additional information. Bolt automatically attaches information that is included in the incoming request, like **`user_id`**, **`team_id`**, **`channel_id`**, and **`enterprise_id`**.

つまり、`context["user_id"]` でも同じ値が取得可能。

### 5. Bolt JavaScript での取得方法

ファイル: `docs/tools/bolt-js/concepts/using-the-assistant-class.md`, `docs/ai/developing-agents.md`

**`userMessage` ハンドラー内での取得方法:**

```javascript
userMessage: async ({ client, context, logger, message, getThreadContext, say, setTitle, setStatus }) => {
    const { channel, thread_ts } = message;
    const { userId, teamId } = context;  // ← context.userId でユーザーIDを取得
    ...
}
```

- **`context.userId`** でユーザーIDが取得できる
- Bolt JS の `context` オブジェクトには `userId`, `teamId` が自動付与される

### 6. エントリーポイント別のユーザーID取得方法まとめ

| エントリーポイント | イベント | 取得フィールド |
|---|---|---|
| エージェントコンテナ（スプリットペイン）スレッド開始 | `assistant_thread_started` | `event.assistant_thread.user_id` |
| エージェントコンテナへのユーザーメッセージ | `message.im` | `event.user` / Bolt: `payload["user"]` or `context.user_id` (Python), `context.userId` (JS) |
| チャンネルでの @メンション | `app_mention` | `event.user` / Bolt: `event["user"]` |
| コンテナ外のDM | `message.im` | `event.user` |
| スラッシュコマンド | slash command | `command.user_id` |
| ボタン/アクション | `block_actions` | `body.user.id` |

注: `agent-entry-and-interaction.md` でも各エントリーポイントについて記載があり、以下が確認できた:
- イベントハンドラ: `event.channel` / `event.user`
- スラッシュコマンドハンドラ: `command.channel_id` / `command.user_id`
- アクション/ショートカットハンドラ: `body.channel.id` / `body.user.id`

### 7. ユーザーIDから詳細プロフィールを取得する方法

ユーザーIDが取得できれば、`users.info` APIを呼び出すことでメールアドレス・表示名・タイムゾーンなどの詳細プロフィールを取得できる。

`docs/tools/bolt-js/concepts/context.md` のサンプルコードより:

```javascript
async function addTimezoneContext({ payload, client, context, next }) {
    const user = await client.users.info({
        user: payload.user_id,
        include_locale: true
    });
    context.tz_offset = user.tz_offset;
    await next();
}
```

これを応用して、外部システムとのユーザー照合（例: SlackユーザーIDとアプリ固有のユーザーIDのマッピング）や、外部データソースへの絞り込みクエリのパラメータとして使用できる。

### 8. `thread_started` イベントでのユーザー情報注意点

Bolt Pythonの`thread_started`ハンドラーのサンプルコードでは、`user_id`が直接引数として渡されていない。しかし、`assistant_thread_started`イベントのペイロードには`user_id`が含まれているため、`event`引数から取得できる:

```python
@assistant.thread_started
def start_assistant_thread(
    event: dict,
    say: Say,
    ...
):
    user_id = event["assistant_thread"]["user_id"]
```

---

## 問題・疑問点

- `message.im` イベント（`userMessage`ハンドラー）では `thread_context`（チャンネル情報）が含まれないと公式ドキュメントに明記されているが、`user` フィールドは含まれる（実際のサンプルコードで `payload["user"]` が使用されている）。これは確認済み。
- Enterprise Search と組み合わせる場合、`assistant.search.context` を呼ぶときに `action_token` が必要。このトークンはユーザー認証済みトークンであり、`event.action_token` から取得する（ユーザー情報とは別の概念）。

---

## 調査結論

カスタムエージェントを動かすとき、**起点となったユーザーのIDは必ず取得できる**。

- エージェントコンテナ（スプリットペイン）の場合:
  - スレッド開始時: `event.assistant_thread.user_id`
  - メッセージ受信時: `payload["user"]`（Python）/ `context.userId`（JS）
- チャンネル @メンションの場合: `event.user`
- スラッシュコマンドの場合: `command.user_id`

ユーザーIDを取得した後、`users.info` APIでフルプロフィールを取得すれば、外部システムとの照合や絞り込みに使用できる。
