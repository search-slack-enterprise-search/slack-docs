# カスタムエージェントの非同期実装方法

## 知りたいこと

カスタムエージェントにおいて、非同期で実装する方法

## 目的

エージェントを非同期で動かす場合、Agent側はイベント受信と分けると回答を返すべき先がわからず、回答があるまでユーザーは何も動いていないように見えると思われる。どうやって実装したらいいか知りたい。

## 調査サマリー

### 問題の解決策

**2つの問題に対する答え**:

1. **「どこに返すか」**: `channel_id` と `thread_ts` をイベントペイロードの先頭で取得し保持する。Boltの `say()` / `say_stream()` はこれを自動参照する。Bolt以外では `client.chat_postMessage(channel=channel_id, thread_ts=thread_ts, ...)` で明示指定。

2. **「ユーザーに何も見えない」**: 処理開始直後に `set_status("thinking...")` を呼ぶ。Slack UI にローディングアニメーションが表示される。

### 推奨実装フロー（Bolt使用）

```python
@assistant.user_message
def respond_in_assistant_thread(say, say_stream, set_status, event, context):
    channel_id = context.channel_id        # 回答先
    thread_ts = context.thread_ts          # 回答先スレッド
    
    # 1. 即座にローディング表示（ユーザーが見る）
    set_status(
        status="thinking...",
        loading_messages=["Thinking...", "Processing..."],
    )
    
    # 2. 時間のかかる処理
    result = call_llm(event["text"])
    
    # 3. 回答送信（channel_id/thread_ts は自動参照）
    streamer = say_stream()
    streamer.append(markdown_text=result)
    streamer.stop()
    # → ローディング状態が自動クリアされる
```

### 実装環境別の対応

| 環境 | パターン | HTTP 200のタイミング |
|------|---------|-------------------|
| 通常サーバー + Bolt | リスナー関数内で処理 | Boltが内部で自動処理 |
| FaaS（Lambda）+ Bolt | Lazy Listeners | `ack()` で3秒以内に返す |
| 通常サーバー + 非Bolt | 別スレッド + `chat_postMessage` | 受信後即座に手動で返す |
| asyncio + Bolt | `AsyncApp` + `async/await` | asyncioで管理 |

### 非Bolt（Flask等）での別スレッドパターン

```python
@app.route("/slack/events", methods=["POST"])
def handle_event():
    event = request.json.get("event", {})
    channel_id = event["channel"]
    thread_ts = event.get("thread_ts") or event["ts"]
    
    # 別スレッドで長時間処理を開始
    threading.Thread(
        target=process_async,
        args=(client, channel_id, thread_ts, event["text"])
    ).start()
    
    return "", 200  # 即座にHTTP 200を返す

def process_async(client, channel_id, thread_ts, text):
    client.assistant.threads.setStatus(channel_id=channel_id, thread_ts=thread_ts, status="thinking...")
    result = call_llm(text)
    client.chat_postMessage(channel=channel_id, thread_ts=thread_ts, text=result)
    client.assistant.threads.setStatus(channel_id=channel_id, thread_ts=thread_ts, status="")
```

## 完了サマリー

- ドキュメント: `docs/tools/bolt-python/concepts/` 配下複数ファイル、`docs/tools/bolt-js/concepts/adding-agent-features.md`, `docs/apis/events-api/using-http-request-urls.md`
- ログ: `logs/0029_custom-agent-async-implementation.md`
