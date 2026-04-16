# 0029: カスタムエージェントの非同期実装方法 — 調査ログ

## 調査アプローチ

### 問いの整理

ユーザーが抱えている懸念は以下の2点：

1. **回答先の問題**: 非同期処理では、イベント受信時のHTTPリクエスト/レスポンスのスコープを外れるため、後から回答を送るときに「どこに返せばよいか」がわからなくなる
2. **UXの問題**: LLM処理中、ユーザーには何も進捗が見えないため「フリーズしているのか？」と思われる

### 調査手順

1. `docs/tools/bolt-python/concepts/acknowledge.md` でackパターンを確認
2. `docs/tools/bolt-python/concepts/lazy-listeners.md` でFaaS向け非同期パターンを確認
3. `docs/tools/bolt-python/concepts/using-the-assistant-class.md` でAssistantクラスの実装フローを確認
4. `docs/tools/bolt-python/concepts/async.md` でasyncioサポートを確認
5. `docs/tools/bolt-python/concepts/adding-agent-features.md` でサポートエージェント（Casey）の完全な実装例を確認
6. `docs/tools/bolt-js/concepts/adding-agent-features.md` でJavaScript版の実装例を確認
7. `docs/apis/events-api/using-http-request-urls.md` でHTTP接続とイベントデカップリングの推奨事項を確認

---

## 調査ファイル一覧

- `docs/tools/bolt-python/concepts/acknowledge.md`
- `docs/tools/bolt-python/concepts/lazy-listeners.md`
- `docs/tools/bolt-python/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-python/concepts/async.md`
- `docs/tools/bolt-python/concepts/adding-agent-features.md`
- `docs/tools/bolt-js/concepts/adding-agent-features.md`
- `docs/apis/events-api/using-http-request-urls.md`

---

## 調査結果

### 1. 問題の核心: 非同期実装で「どこに返すか」

ソース: `docs/tools/bolt-python/concepts/adding-agent-features.md`（完全実装例）

**回答**: `channel_id` と `thread_ts` はイベントペイロードから取得でき、これをクロージャや変数として保持することで、非同期処理完了後も正しいスレッドに返答できる。

Boltの `say()` / `say_stream()` ユーティリティはイベントペイロードから `channel_id` と `thread_ts` を**自動的に**参照するため、リスナー関数のスコープ内であれば明示的に指定する必要がない。

スコープ外（別スレッド等）で返答する場合は `client.chat_postMessage(channel=channel_id, thread_ts=thread_ts, ...)` を使う。

---

### 2. UXの問題: ローディング状態の表示

ソース: `docs/tools/bolt-python/concepts/adding-agent-features.md` 95-101行目、`docs/tools/bolt-python/concepts/using-the-assistant-class.md` 76-92行目

**回答**: `set_status()` を非同期処理の開始前に呼び出すことで、ユーザーに「処理中」の表示が出る。

Bolt for Python の実装例（Casseyサポートエージェントより）：

```python
def handle_app_mentioned(
    client: WebClient,
    context: BoltContext,
    event: dict,
    logger: Logger,
    say: Say,
    say_stream: SayStream,
    set_status: SetStatus,
):
    """Handle @Casey mentions in channels."""
    try:
        channel_id = context.channel_id
        text = event.get("text", "")
        thread_ts = event.get("thread_ts") or event["ts"]
        user_id = context.user_id

        # 即座にローディング状態を表示（ユーザーには「考え中」が見える）
        set_status(
            status="Thinking...",
            loading_messages=[
                "Teaching the hamsters to type faster…",
                "Untangling the internet cables…",
                "Consulting the office goldfish…",
                "Polishing up the response just for you…",
                "Convincing the AI to stop overthinking…",
            ],
        )

        # 会話履歴を取得
        history = conversation_store.get_history(channel_id, thread_ts)

        # エージェントを実行（時間がかかる処理）
        deps = CaseyDeps(client=client, user_id=user_id, channel_id=channel_id, thread_ts=thread_ts, ...)
        result = casey_agent.run_sync(cleaned_text, deps=deps, message_history=history)

        # ストリーミングで回答を送信（channel_id, thread_ts は say_stream が自動参照）
        streamer = say_stream()
        streamer.append(markdown_text=result.output)
        streamer.stop()

    except Exception as e:
        logger.exception(f"Failed to handle app mention: {e}")
        say(text=f":warning: Something went wrong! ({e})", thread_ts=thread_ts)
```

**重要なポイント**:
- `set_status()` を先に呼ぶことでローディングアニメーションが表示される
- その後は時間のかかるLLM処理を同じ関数内で実行
- Boltは**関数が完了するまでHTTP 200を返さない（または自動的に返す）**
- `say_stream()` はイベントペイロードから `channel_id` と `thread_ts` を自動的に取得

---

### 3. Boltの動作原理: 「同期的に見える非同期」

ソース: `docs/tools/bolt-python/concepts/acknowledge.md`、`docs/apis/events-api/using-http-request-urls.md`

Bolt for Python / JavaScript のリスナー関数では、**HTTP 200の送信とビジネスロジックの実行を分離する必要がない**（通常環境の場合）。

Events APIドキュメント (`using-http-request-urls.md`) の推奨：
```
Your request URL might receive many events and requests. Consider decoupling your ingestion of 
events from the processing and reaction to them.
```

ただしBoltを使う場合、Boltフレームワークがこの「デカップリング」を内部で処理してくれる。具体的には：
1. Slackからイベントが届く → BoltがHTTP 200を返す
2. 同時にリスナー関数を実行する（別スレッドまたは非同期）
3. リスナー関数内で `say()` / `client.chat_postMessage()` を呼ぶと、そのタイミングでSlackに返答される

`acknowledge.md` より：
```
We recommend calling ack() right away before initiating any time-consuming processes such as 
fetching information from your database or sending a new message, since you only have 3 seconds 
to respond before Slack registers a timeout error.
```

---

### 4. 別スレッドで処理する実装パターン（非Boltの場合）

標準的なWebフレームワーク（Flask, FastAPIなど）で直接実装する場合、以下のパターンが使われる：

```python
import threading
from slack_sdk import WebClient

client = WebClient(token="BOT_TOKEN")

@app.route("/slack/events", methods=["POST"])
def handle_event():
    payload = request.json
    event = payload.get("event", {})
    
    channel_id = event["channel"]
    thread_ts = event.get("thread_ts") or event["ts"]
    user_message = event.get("text", "")
    
    # 1. 即座にHTTP 200を返す
    # 同時に、ローディング状態を表示（非同期で呼び出し）
    threading.Thread(target=process_async, args=(client, channel_id, thread_ts, user_message)).start()
    
    return "", 200

def process_async(client, channel_id, thread_ts, user_message):
    # ローディング状態の表示（処理開始を通知）
    client.assistant.threads.setStatus(
        channel_id=channel_id,
        thread_ts=thread_ts,
        status="thinking..."
    )
    
    # 時間のかかるLLM処理
    result = call_llm(user_message)
    
    # 回答を送信（channel_id と thread_ts を使って正しいスレッドへ）
    client.chat_postMessage(
        channel=channel_id,
        thread_ts=thread_ts,
        text=result
    )
    
    # ローディング状態をクリア
    client.assistant.threads.setStatus(
        channel_id=channel_id,
        thread_ts=thread_ts,
        status=""  # 空文字でクリア
    )
```

---

### 5. FaaS環境（Lambda等）での「Lazy Listeners」パターン

ソース: `docs/tools/bolt-python/concepts/lazy-listeners.md`

FaaS（Function as a Service）環境では、HTTPレスポンスを返した後にスレッドを維持できないため、特別なパターンが必要。

`lazy-listeners.md` より：
```
Lazy Listeners are a feature which make it easier to deploy Slack apps to FaaS environments.

Typically when handling actions, commands, shortcuts, options and view submissions, you must 
acknowledge the request from Slack by calling ack() within 3 seconds. However, when running 
your app on FaaS or similar runtimes which do not allow you to run threads or processes after 
returning an HTTP response, we cannot follow the typical pattern of acknowledgement first, 
processing later.
```

Bolt for Python の Lazy Listeners:

```python
app = App(process_before_response=True)  # FaaSモード

def respond_to_slack_within_3_seconds(body, ack):
    # 3秒以内にackを呼ぶ（HTTP 200を返す）
    ack(f"Accepted! (task: {body['text']})")

def run_long_process(respond, body):
    # この関数はHTTP 200返却後に実行される
    # 時間のかかる処理をここに書く
    time.sleep(5)  # longer than 3 seconds
    respond(f"Completed! (task: {body['text']})")

app.command("/start-process")(
    ack=respond_to_slack_within_3_seconds,  # 3秒以内にackを呼ぶ
    lazy=[run_long_process]                  # 時間のかかる処理
)
```

**AWS Lambda での注意点**：Lambda での Lazy Listeners には `lambda:InvokeFunction` と `lambda:GetFunction` の IAM 権限が必要（Boltが内部でLambdaを再起動して非同期処理を継続するため）。

---

### 6. Bolt for Python の asyncio サポート

ソース: `docs/tools/bolt-python/concepts/async.md`

完全非同期（asyncio）で実装したい場合：

```python
# AsyncApp を使う
from slack_bolt.async_app import AsyncApp

app = AsyncApp()

@app.event("app_mention")
async def handle_mentions(event, client, say):  # async function
    api_response = await client.reactions_add(
        channel=event["channel"],
        timestamp=event["ts"],
        name="eyes",
    )
    
    # 時間のかかる処理
    result = await call_llm_async(event["text"])
    
    await say("What's up?")
```

`AsyncApp` は AIOHTTP を使ってAPIリクエストを行う。

---

### 7. say_stream ユーティリティの channel_id / thread_ts 自動参照

ソース: `docs/tools/bolt-python/concepts/adding-agent-features.md` 106-134行目、`docs/tools/bolt-js/concepts/adding-agent-features.md` 101-131行目

`say_stream` / `sayStream` ユーティリティが参照する値：

| パラメータ | 参照元 |
|-----------|-------|
| `channel_id` | イベントペイロードから自動取得 |
| `thread_ts` | イベントペイロードから自動取得（`ts` にフォールバック） |
| `recipient_team_id` | イベントの `team_id`（org インストールの場合は `enterprise_id`） |
| `recipient_user_id` | イベントの `user_id` |

`channel_id` または `thread_ts` が取得できない場合、ユーティリティは `None` になる。

---

### 8. Bolt での推奨実装フロー（まとめ）

タスク 0026 の調査で確認した通り、ドキュメント（Events API）はイベントの取り込みと処理の「デカップリング」を推奨している。Boltはこれを内部で実装している。

エージェントの推奨フロー：

```
Slack → HTTP POST（イベント）
           ↓
         Bolt受信
           ↓（Boltが内部でHTTP 200を自動返却）
         リスナー関数実行
           ↓
         1. set_status("thinking...")  ← ユーザーがローディング表示を見る
           ↓
         2. LLM/外部API 呼び出し（時間がかかる）
           ↓
         3. say() / say_stream() で回答送信 ← channel_id/thread_ts は自動参照
```

**回答先の情報（channel_id, thread_ts）はどこから来るか**:
- `context.channel_id` / `context.thread_ts`（Bolt の BoltContext）
- `event["channel"]` / `event.get("thread_ts") or event["ts"]`（イベントペイロード直接）
- これらをリスナー関数の先頭でローカル変数に保存しておけば、関数全体を通じて使用できる

---

## 結論

### Q1: 非同期処理で「どこに返すか」はどうやってわかるのか？

**`channel_id` と `thread_ts` をイベントペイロードの先頭で取得し、保持する。**

Bolt を使えば `say()` / `say_stream()` がこれを自動参照するため、明示的に指定する必要がない。Bolt を使わない場合（Flask等）は、`client.chat_postMessage(channel=channel_id, thread_ts=thread_ts, ...)` で送信先を指定する。

### Q2: ユーザーが「何も動いていない」に見える問題はどう解決するか？

**処理開始直後に `set_status("thinking...")` を呼ぶ。**

これにより Slack UI にローディングアニメーションが表示される。`loading_messages` に複数の文字列を渡すと、ローテーションしながら表示されるためよりリッチな表現が可能。

処理完了後は `say()` / `say_stream()` を呼ぶと自動的にローディング状態がクリアされる。明示的にクリアする場合は `set_status("")` を呼ぶ。

### Q3: 実装環境によって何が変わるか？

| 環境 | 推奨パターン | タイムアウト制約 |
|------|------------|----------------|
| 通常サーバー（Bolt） | リスナー関数内で同期的に処理（Boltが内部でデカップリング） | なし（BoltがHTTP 200を先に返す） |
| FaaS（Lambda等）+ Bolt | Lazy Listeners パターン | 3秒以内に `ack()` 必須 |
| 通常サーバー（非Bolt） | 別スレッドで処理、`client.chat_postMessage` で返答 | HTTP 200を3秒以内に返す |
| 完全非同期（asyncio） | `AsyncApp` + `async/await` | なし（asyncioが管理） |

### まとめ図

```
【Boltを使った通常サーバーの場合】

message.im イベント
      ↓
Bolt受信 → HTTP 200 自動返却（3秒以内）
      ↓
リスナー関数実行（Boltが別スレッドで実行）
      ↓
set_status("thinking...")  ← ユーザーに「考え中」表示
      ↓
LLM処理（数秒〜数十秒）
      ↓
say_stream() で回答送信（channel_id/thread_ts は自動参照）
      ↓
ローディング状態が自動クリア

【非Boltの場合（Flask等）】

HTTP POST受信
      ↓
threading.Thread(target=process_async, ...).start()
HTTP 200 を即座に返す（3秒以内）
      ↓（別スレッドで実行）
client.assistant.threads.setStatus(status="thinking...")
      ↓
LLM処理
      ↓
client.chat_postMessage(channel=channel_id, thread_ts=thread_ts, ...)
```

---

## 問題・疑問点

1. Bolt がHTTP 200を「自動返却」するタイミングの詳細は、ドキュメントに明示されていない。実際はリスナー関数の実行開始と同時に返却するのか、関数完了後に返却するのかはフレームワークの実装依存。
2. FaaS環境でエージェント（assistant_thread_startedなど）を実装する場合のLazy Listenersの対応状況はドキュメントに明記がない（スラッシュコマンドの例しかない）。
3. 長時間処理（例: 数分）が必要な場合、Slack側でのタイムアウトはないが、LLMのAPIタイムアウトや自社インフラのタイムアウト設定に注意が必要。
