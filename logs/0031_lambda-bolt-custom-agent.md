# LambdaとBoltを組み合わせたカスタムエージェント作成方法 - 調査ログ

## 調査概要

- **調査日**: 2026-04-16
- **タスクファイル**: kanban/0031_lambda-bolt-custom-agent.md
- **調査テーマ**: AWS LambdaとBolt for Pythonを組み合わせてSlackカスタムエージェントを作成する方法

---

## 調査したファイル一覧

### AIエージェント関連
- `docs/ai/agents.md`
- `docs/ai/developing-agents.md`
- `docs/ai/agent-quickstart.md`
- `docs/ai/agent-entry-and-interaction.md`
- `docs/ai/agent-context-management.md`
- `docs/ai/agent-design.md`

### Bolt for Python - Socket Mode / Lambda対応
- `docs/tools/bolt-python/concepts/socket-mode.md`
- `docs/tools/bolt-python/concepts/lazy-listeners.md`
- `docs/tools/bolt-python/concepts/adapters.md`
- `docs/tools/bolt-python/concepts/async.md`

### Bolt for Python - Assistant/Agent機能
- `docs/tools/bolt-python/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-python/concepts/adding-agent-features.md`

### Bolt for JavaScript - Socket Mode / Assistant
- `docs/tools/bolt-js/concepts/socket-mode.md`
- `docs/tools/bolt-js/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-js/concepts/adding-agent-features.md`

### Bolt for Java
- `docs/tools/java-slack-sdk/guides/socket-mode.md`

### Events API / Socket Mode
- `docs/apis/events-api/using-socket-mode.md`
- `docs/apis/events-api/comparing-http-socket-mode.md`

### API Reference Methods
- `docs/reference/methods/assistant.threads.setStatus.md`
- `docs/reference/methods/assistant.threads.setSuggestedPrompts.md`
- `docs/reference/methods/assistant.threads.setTitle.md`

---

## 調査結果

### 1. Bolt for Python - Lambda対応

#### Lazy Listener（FaaS対応）

Lazy ListenerはAWS Lambdaなどのステートレス関数環境での実行に最適化されたBolt for Pythonの機能。

**重要な特性：**
- `process_before_response=True` フラグでHTTP応答を待機
- 3秒以内に `ack()` を呼び出す必要がある
- Lazy関数は `ack()` にアクセスできず、最大3秒以内に完了する必要がある（Lazy listener部分はその制限外）

**実装パターン（Lazy listener）：**

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

# process_before_response は FaaS 環境で True にする必須設定
app = App(process_before_response=True)

def respond_to_slack_within_3_seconds(body, ack):
    text = body.get("text")
    if text is None or len(text) == 0:
        ack(":x: Usage: /start-process (description here)")
    else:
        ack(f"Accepted! (task: {body['text']})")

import time
def run_long_process(respond, body):
    time.sleep(5)  # 3秒超の処理も可能
    respond(f"Completed! (task: {body['text']})")

app.command("/start-process")(
    ack=respond_to_slack_within_3_seconds,  # 3秒以内にack
    lazy=[run_long_process]                  # 長時間処理はLazyで実施
)

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

**AWS Lambda IAM権限（Lazy listenerを使う際に必須）：**

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction",
                "lambda:GetFunction"
            ],
            "Resource": "*"
        }
    ]
}
```

Lazy listenerが動作する仕組み：Bolt が Lambda を自己invoke（再呼び出し）することで長時間処理を実現する。そのため `lambda:InvokeFunction` 権限が必要。

#### Socket Mode vs HTTP 選択基準

| 特性 | HTTP | WebSocket (Socket Mode) |
|------|------|-------------------------|
| 接続形式 | リクエスト・レスポンス | 双方向ステートフル |
| スケーラビリティ | 水平スケール対応 | 最大10接続、困難 |
| 信頼性 | 短命接続で高い | 長命接続でリスクあり |
| Marketplace対応 | 対応 | 非対応 |

**推奨戦略：**
- ローカル開発・ファイアウォール内 → Socket Mode
- 本番環境（Marketplace対応含む） → HTTP
- FaaS環境（Lambda）→ HTTP推奨（より信頼性が高い）

---

### 2. カスタムエージェント（Agents & AI Apps）のBoltでの実装方法

#### 事前準備

Slack app settings で「Agents & AI Apps」機能を有効化し、以下のスコープを追加：

- `assistant:write` - Assistant API使用（必須）
- `chat:write` - メッセージ送信（必須）
- `im:history` - スレッド履歴取得（推奨）

購読するイベント：
- `assistant_thread_started` - ユーザーがDMコンテナを開いた時
- `assistant_thread_context_changed` - ユーザーが別チャネルに切り替えた時
- `message.im` - ユーザーがメッセージを送信した時

#### Assistant クラス（Bolt for Python）の実装

```python
from slack_bolt import App
from slack_bolt.context.say import Say
from slack_bolt.context.set_status import SetStatus
from slack_bolt.context.set_suggested_prompts import SetSuggestedPrompts
from slack_bolt.context.get_thread_context import GetThreadContext
import logging
from typing import List, Dict

app = App(
    token=os.environ["SLACK_BOT_TOKEN"],
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    process_before_response=True,  # Lambda では必須
)
assistant = Assistant()

# 1. スレッド開始時
@assistant.thread_started
def start_assistant_thread(
    say: Say,
    get_thread_context: GetThreadContext,
    set_suggested_prompts: SetSuggestedPrompts,
    logger: logging.Logger,
):
    try:
        say("How can I help you?")
        prompts: List[Dict[str, str]] = [
            {
                "title": "Suggest names for my Slack app",
                "message": "Can you suggest a few names for my Slack app? The app helps my teammates better organize information and plan priorities and action items.",
            },
        ]
        thread_context = get_thread_context()
        if thread_context is not None and thread_context.channel_id is not None:
            summarize_channel = {
                "title": "Summarize the referred channel",
                "message": "Can you generate a brief summary of the referred channel?",
            }
            prompts.append(summarize_channel)
        set_suggested_prompts(prompts=prompts)
    except Exception as e:
        logger.exception(f"Failed to handle an assistant_thread_started event: {e}")
        say(f":warning: Something went wrong! ({e})")

# 2. ユーザーメッセージ処理
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
    try:
        channel_id = payload["channel"]
        thread_ts = payload["thread_ts"]
        user_message = payload["text"]

        # ローディング状態を設定
        set_status(
            status="thinking...",
            loading_messages=[
                "Untangling the internet cables…",
                "Consulting the office goldfish…",
                "Convincing the AI to stop overthinking…",
            ],
        )

        # スレッド履歴を取得
        replies = client.conversations_replies(
            channel=context.channel_id,
            ts=context.thread_ts,
            oldest=context.thread_ts,
            limit=10,
        )

        messages_in_thread: List[Dict[str, str]] = []
        for message in replies["messages"]:
            role = "user" if message.get("bot_id") is None else "assistant"
            messages_in_thread.append({"role": role, "content": message["text"]})

        # LLM呼び出し（独自実装）
        returned_message = call_llm(messages_in_thread)

        # レスポンス送信（set_statusは自動クリア）
        say(text=returned_message)
    except Exception as e:
        logger.exception(f"Failed to respond to an inquiry: {e}")
        say(f":warning: Sorry, something went wrong during processing your request (error: {e})")

# Assistantミドルウェアを有効化
app.use(assistant)
```

#### Thread Context Store（コンテキスト管理）

デフォルトではメッセージメタデータとして保存される。開発用途ではファイルベース実装も提供：

```python
from slack_bolt import FileAssistantThreadContextStore

assistant = Assistant(
    thread_context_store=FileAssistantThreadContextStore()
)
```

本番環境ではDBベースのカスタム実装が推奨される。

---

### 3. Lambda環境での非同期処理・タイムアウト対策

#### 3秒制限の仕組み

Slack APIは3秒以内に `ack()` を送信しないとタイムアウトする。Lambda + Boltの組み合わせでは：

1. リクエスト受信 → 3秒以内に `ack()` を送信
2. `ack()` 後の長時間処理 → Lazy listenerで別Lambda invocationとして実行
3. 処理完了後 → `respond()` または `say()` でSlackに返信

**タイムアウト対策パターン：**

```python
# ack部分（3秒以内必須）
def ack_callback(body, ack):
    ack()  # または ack(text="処理中です...")

# 長時間処理部分（Lazy listener、3秒超可）
def lazy_callback(respond, body):
    import time
    time.sleep(10)  # 10秒かかる処理もOK
    respond("Done!")

app.command("/my-command")(
    ack=ack_callback,
    lazy=[lazy_callback]
)
```

#### 非同期処理（asyncio対応版）

```python
from slack_bolt.async_app import AsyncApp

app = AsyncApp(token=os.environ["SLACK_BOT_TOKEN"])

@app.event("app_mention")
async def handle_mentions(event, client, say):
    api_response = await client.reactions_add(
        channel=event["channel"],
        timestamp=event["ts"],
        name="eyes",
    )
    await say("What's up?")
```

---

### 4. Assistant API メソッドの詳細

#### assistant.threads.setStatus

ローディング状態を表示する。最大2分のタイムアウトで自動クリア。

- **スコープ**: `chat:write` または `assistant:write`
- **レート制限**: 600リクエスト/分（デフォルト）
- **タイムアウト**: 2分で自動クリア

```python
# API直接呼び出し
client.assistant_threads_setStatus(
    channel_id="D324567865",
    thread_ts="1724264405.531769",
    status="is working on your request...",
    loading_messages=[
        "Untangling the internet cables…",
        "Consulting the office goldfish…",
    ]
)

# Boltユーティリティ（推奨）
@assistant.user_message
def handle_message(set_status: SetStatus, say: Say):
    set_status(
        status="thinking...",
        loading_messages=[
            "Teaching the hamsters to type faster…",
        ],
    )
    # 処理後にsayを呼ぶとset_statusは自動クリア
    say("Here's the result")
```

#### assistant.threads.setSuggestedPrompts

ユーザーに提案するプロンプトを最大4個設定する。

- **スコープ**: `assistant:write`
- **レート制限**: Tier 4（100+/分）

```python
# API直接呼び出し
client.assistant_threads_setSuggestedPrompts(
    channel_id="D2345SFDG",
    thread_ts="1724264405.531769",
    title="Welcome. What can I do for you?",
    prompts=[
        {
            "title": "Generate ideas",
            "message": "Pretend you are a marketing associate and generate 10 ideas for a new feature launch.",
        },
        {
            "title": "Explain what Slack stands for",
            "message": "What does SLACK stand for?",
        },
    ]
)

# Boltユーティリティ（推奨）
@assistant.thread_started
def start_thread(set_suggested_prompts: SetSuggestedPrompts):
    set_suggested_prompts(
        prompts=[
            {
                "title": "Suggest names for my Slack app",
                "message": "Can you suggest a few names for my Slack app?",
            },
        ]
    )
```

#### assistant.threads.setTitle

スレッドのタイトルを設定する（DM履歴で表示される）。

- **スコープ**: `assistant:write`
- **レート制限**: Tier 4（100+/分）

```python
# API直接呼び出し
client.assistant_threads_setTitle(
    channel_id="D324567865",
    thread_ts="1786543.345678",
    title="Holidays this year"
)

# Boltユーティリティ（推奨）
@assistant.user_message
def handle_user_message(set_title: SetTitle, message: dict):
    set_title(message["text"])  # ユーザーの最初のメッセージをタイトルに
```

---

### 5. Lambda + Bolt for Python 完全統合パターン

#### 完全な実装例

```python
import os
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler
from slack_sdk import WebClient

# Lambda環境では process_before_response=True が必須
app = App(
    token=os.environ["SLACK_BOT_TOKEN"],
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    process_before_response=True,
)

assistant = Assistant()

@assistant.thread_started
def start_thread(say, set_suggested_prompts):
    say("こんにちは！何かお手伝いできますか？")
    set_suggested_prompts(prompts=[
        {"title": "使い方を教えて", "message": "このエージェントの使い方を教えてください"}
    ])

@assistant.user_message
def handle_user_message(client, context, payload, say, set_status, set_title):
    set_title(payload["text"])  # ユーザーのメッセージをタイトルに
    set_status("考えています...")

    # スレッド履歴を取得してLLMに渡す
    replies = client.conversations_replies(
        channel=context.channel_id,
        ts=context.thread_ts,
        oldest=context.thread_ts,
        limit=10,
    )
    messages = []
    for msg in replies["messages"]:
        role = "user" if msg.get("bot_id") is None else "assistant"
        messages.append({"role": role, "content": msg["text"]})

    # LLM呼び出し（独自実装が必要）
    response = call_llm(messages)
    say(response)

app.use(assistant)

# Lambda エントリーポイント
def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

#### serverless.yml 設定例

```yaml
service: slack-custom-agent

provider:
  name: aws
  runtime: python3.11
  region: ap-northeast-1
  iamRoleStatements:
    - Effect: Allow
      Action:
        - lambda:InvokeFunction
        - lambda:GetFunction
      Resource: "*"  # Lazy listener のための自己invoke権限

functions:
  slack-agent:
    handler: handler.handler
    environment:
      SLACK_BOT_TOKEN: ${ssm:/slack/bot-token}
      SLACK_SIGNING_SECRET: ${ssm:/slack/signing-secret}
    timeout: 30  # 十分な余裕を持たせる
    memorySize: 256
    events:
      - http:
          path: slack/events
          method: post
```

---

### 6. Slack CLI統合型Agentサンプルアプリケーション（Casey）

公式テンプレート「Casey」（Support Agent）：

```bash
# 初期化コマンド
slack create agent
```

対応フレームワーク：
- Claude Agent SDK
- OpenAI Agents SDK
- Pydantic AI

**Casey の機能：**
- `@Casey` メンション対応
- ダイレクトメッセージ対応
- Assistant side panel（Agents & AI Apps有効時）
- 動的スレッドタイトル設定
- ストリーミングレスポンス
- フィードバックボタン

---

### 7. 重要な設定・注意事項まとめ

| 項目 | 設定値・注意事項 |
|------|-----------------|
| Agents & AI Apps | App Settings で有効化必須 |
| 必須スコープ | `assistant:write`, `chat:write`, `im:history` |
| Lambda 設定 | `process_before_response=True` |
| 3秒制限対策 | Lazy listener パターンを使用 |
| Lambda IAM権限 | `lambda:InvokeFunction`, `lambda:GetFunction` |
| Socket Mode | 開発用途。本番はHTTPを推奨 |
| コンテキスト管理 | 本番ではDBベース実装推奨 |
| Lambda タイムアウト | 30秒以上に設定推奨 |

---

## 調査アプローチ

1. `docs/ai/` 以下のエージェント関連ドキュメントを調査
2. `docs/tools/bolt-python/` 以下のLambda・Lazy listener・Assistantクラス関連ドキュメントを調査
3. `docs/reference/methods/assistant.threads.*` のAPIリファレンスを調査
4. Events API と Socket Mode の比較ドキュメントを調査

---

## 問題・疑問点

- Lazy listener は Bolt が Lambda を自己invoke する仕組みのため、Assistant の `user_message` ハンドラがLazy listener と組み合わせて使えるかどうかは要確認
- LLM（call_llm部分）の実装は完全にユーザー側の責任であり、ドキュメントには含まれない
- Assistant クラス使用時、`process_before_response=True` との組み合わせの挙動は詳細確認が必要
