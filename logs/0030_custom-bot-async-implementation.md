# 調査ログ: カスタムボット非同期実装方法

## タスク概要

- **タスクファイル**: kanban/0030_custom-bot-async-implementation.md
- **知りたいこと**: カスタムボットの非同期での実装方法
- **目的**: ボットを非同期で動かす場合、ボット側はイベント受信と分けると回答を返すべき先がわからず、回答があるまでユーザーは何も動いていないように見えると思われる。どうやって実装したらいいかしりたい。またボットは非推奨になるって聞いたけど、Agentしか使えなくなるってこと？

---

## 調査ファイル一覧

### テーマ1: カスタムボットの非同期実装に関連するファイル

- `docs/interactivity/handling-user-interaction.md` - ユーザーインタラクション全般の処理（response_url・trigger_id）
- `docs/messaging/creating-interactive-messages.md` - インタラクティブメッセージの作成
- `docs/messaging/sending-and-scheduling-messages.md` - メッセージ送信API
- `docs/apis/events-api/using-http-request-urls.md` - HTTPリクエストURL設定
- `docs/apis/events-api/index.md` - イベントAPI概要
- `docs/tools/bolt-python/concepts/async.md` - Pythonでの非同期実装
- `docs/tools/bolt-python/concepts/actions.md` - アクション処理・respond()
- `docs/tools/bolt-python/concepts/acknowledge.md` - リクエスト確認応答（ack）
- `docs/tools/bolt-python/concepts/message-sending.md` - メッセージ送信・SayStream
- `docs/tools/bolt-js/concepts/actions.md` - JavaScriptでのアクション処理
- `docs/tools/bolt-js/tutorials/ai-assistant.md` - Typing Indicator（setStatus）

### テーマ2: ボット非推奨・Agent移行に関連するファイル

- `docs/ai/agents.md` - Agent概要（ボットとの比較含む）
- `docs/ai/developing-agents.md` - Agent開発ガイド（setStatus・agent container）
- `docs/ai/agent-entry-and-interaction.md` - Agentの相互作用サーフェス
- `docs/ai/index.md` - AI/Agent概要
- `docs/ai/agent-context-management.md` - Agent文脈管理
- `docs/legacy/legacy-rtm-api.md` - RTM API（レガシー）でのボット実装
- `docs/legacy/legacy-bot-users.md` - ボットユーザーの説明

---

## 調査結果

### テーマ1: カスタムボット非同期実装

#### 基本原則: 確認応答（Acknowledgment）は3秒以内必須

`docs/interactivity/handling-user-interaction.md` (行79-84):
```
All apps must, as a minimum, acknowledge the receipt of a valid interaction payload.
To do that, your app must reply to the HTTP POST request with an HTTP 200 OK response. 
This must be sent within 3 seconds of receiving the payload.
```

`docs/tools/bolt-python/concepts/acknowledge.md` (行9):
```
We recommend calling ack() right away before initiating any time-consuming processes 
such as fetching information from your database or sending a new message, 
since you only have 3 seconds to respond before Slack registers a timeout error.
```

**結論**: イベント受信・インタラクション受信後、まず即座に `ack()` / HTTP 200 を返す。その後に非同期で実際の処理を行う。

---

#### response_url: 遅延レスポンスの主要メカニズム

`docs/interactivity/handling-user-interaction.md` (行85-108):
```
Depending on the source, the interaction payload your app receives may contain a 
`response_url`. This `response_url` is unique to each payload, and can be used to 
publish messages back to where the interaction happened.

These responses can be sent up to 5 times within 30 minutes of receiving the payload.
```

**制約**:
- 30分以内
- 最大5回まで送信可能
- 30分を超える処理が必要な場合は `chat.postMessage` を直接呼び出す（行107）

**レスポンスタイプ** (行113-137):
- `ephemeral`（初期値）: ユーザーのみに表示される一時的メッセージ
- `in_channel`: チャンネル全体に表示
- `thread_ts`パラメータで特定スレッドにレスポンス可能
- `replace_original: true` で元のメッセージを上書き更新可能

---

#### trigger_id: モーダルを経由した遅延レスポンス

`docs/interactivity/handling-user-interaction.md` (行171-184):
```
When certain events and interactions occur between users and your app, you'll receive 
a `trigger_id` as part of the interaction payload. If you have a `trigger_id`, 
you can use the value of that field to open a modal.

Triggers expire in three seconds. Use them before you lose them.
Triggers may only be used once.
```

モーダル経由で `response_url` を取得できる（行181-183）:
```
When you're composing your modal, you can use special parameters to generate a 
`response_url` when the modal is submitted. You can then use this newly-generated 
`response_url` to publish a message.
```

---

#### Typing Indicator / ステータス表示

**Bolt JS (ai-assistant.md 行163)**:
```
The `setStatus` method calls the `assistant.threads.setStatus` method. 
This status shows like a typing indicator underneath the message composer. 
This status automatically clears when the app sends a reply.
```

**Agent開発 (developing-agents.md 行91-109)**:
```
Your app should then call the `assistant.threads.setStatus` method to display 
the status indicator in the container. We recommend doing so immediately for the 
user's benefit.

Loading states indicate to your user that the app is working on a response.
```

**注意**: `assistant.threads.setStatus` はAgentコンテナ（Agents & AI Appsを有効化したApp）向けのAPIであり、通常のbot userが直接使えるかは非明示。Bolt のAssistantクラス経由の `set_status()` が対応ラッパー。

---

#### Bolt フレームワークでの非同期処理

`docs/tools/bolt-python/concepts/async.md`:
```python
from slack_bolt.async_app import AsyncApp
app = AsyncApp()

@app.event("app_mention")
async def handle_mentions(event, client, say):
    api_response = await client.reactions_add(
        channel=event["channel"],
        timestamp=event["ts"],
        name="eyes",
    )
    await say("What's up?")
```

**ポイント**: `AsyncApp` を使うことで、Python の `async/await` パターンで非同期処理ができる。

---

#### Message Streaming（テキストの段階的送信）

`docs/tools/bolt-python/concepts/message-sending.md` (行25-71):
```python
@app.message("")
def handle_message(client: WebClient, say_stream: SayStream):
    stream = say_stream()
    stream.append(markdown_text="Let me consult my knowledge...")
    stream.stop()
```

**ポイント**: `SayStream` を使うと、LLMの生成結果などを段階的にユーザーに送信できる。

---

#### respond() メソッド: response_url のBoltラッパー

`docs/tools/bolt-python/concepts/actions.md` (行39-45):
```python
@app.action("user_select")
def handle_action(ack, action, respond):
    ack()
    respond(f"You selected <@{action['selected_user']}>")
```

`respond()` は `response_url` への POST を抽象化したBoltのユーティリティ。

---

#### チャンネルID・タイムスタンプの取得方法

イベントペイロードから取得:
```python
# Block Action / Slash Command
channel_id = body['channel']['id']  # または command['channel_id']

# Event (app_mention など)
channel_id = event['channel']
thread_ts = event['thread_ts'] or event['ts']  # スレッドTSまたはメッセージTS

# Block Action の場合（メッセージのTS）
message_ts = body['container']['message_ts']
```

`chat.postMessage` のレスポンスから新規メッセージのTSを取得:
```python
result = client.chat_postMessage(channel=channel, text="Hello")
new_message_ts = result['ts']  # 後でchat.updateに使用
```

---

#### chat.postMessage / chat.update / chat.postEphemeral

`docs/messaging/sending-and-scheduling-messages.md` (行94-119):
- `chat.postMessage`: チャンネルやDMに新規メッセージを投稿。非同期処理後にレスポンスする場合の標準手段
- `chat.update`: 既存メッセージを編集。`channel` と `ts` が必要
- `chat.postEphemeral`: 特定ユーザーのみに見える一時的メッセージ（`user` パラメータ必須）

---

### 非同期実装パターン（実装ガイド）

#### パターン1: Event受信 → ack → chat.postMessage（最も基本的）

イベントを受信したら即座にackし、実際の処理完了後に `chat.postMessage` で返答する:

```python
@app.event("app_mention")
async def handle_mention(event, client, say):
    channel = event['channel']
    thread_ts = event.get('thread_ts') or event['ts']
    
    # 処理中表示（Agentコンテナ使用時）
    # await client.assistant.threads.setStatus(
    #     channel_id=channel, thread_ts=thread_ts, status="考え中..."
    # )
    
    # 非同期で外部処理
    result = await expensive_async_operation()
    
    # 結果を返答（スレッドに）
    await client.chat_postMessage(
        channel=channel,
        thread_ts=thread_ts,
        text=f"結果: {result}"
    )
```

**ポイント**: `event['channel']` と `event['ts']`（または `event['thread_ts']`）がイベントペイロードに含まれるため、どのチャンネルのどのスレッドに返信するかはわかる。

#### パターン2: Slash Command + response_url（30分以内の遅延レスポンス）

```python
@app.command("/process")
def handle_command(ack, command, respond):
    ack()  # 即座に確認応答
    
    # バックグラウンド処理
    result = expensive_operation()
    
    # response_url経由で返答
    respond(f"結果: {result}", response_type="in_channel")
```

#### パターン3: Block Action + respond (replace_original)

```python
@app.action("approve_button")
def handle_action(ack, action, respond):
    ack()  # 確認応答（3秒以内必須）
    
    # 外部API呼び出し
    approval_status = call_external_api(action['value'])
    
    # 元のメッセージを更新
    respond(
        text=f"申請: {approval_status}",
        replace_original=True
    )
```

#### パターン4: Agent Container（新しいUI・Agents & AI Apps有効時）

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

assistant = Assistant()

@assistant.thread_started
def start_thread(say, set_suggested_prompts):
    say("何かお手伝いできますか？")
    set_suggested_prompts(prompts=["データを検索する", "レポートを作成する"])

@assistant.user_message
def respond_to_message(message, say, set_status):
    # ステータス表示（Typing Indicator的な役割）
    set_status(
        status="回答を考え中...",
        loading_messages=["処理中...", "もう少しお待ちください..."]
    )
    
    # LLMに問い合わせ
    response = call_llm(message['text'])
    
    # 返答（set_statusは自動クリア）
    say(response)
```

---

### テーマ2: ボット非推奨・Agent移行

#### Agent vs Bot の定義の違い

`docs/ai/agents.md` (行37-42):
```
### Agents are not just

* **Bots**: Bots respond to specific inputs with predetermined outputs with no 
  reasoning, memory, or adaptation. They can only do what they were explicitly 
  programmed to do.
* **Workflows**: Workflows (that is, non-AI powered workflows) are automations 
  that execute a sequence of steps reliably and repeatably when triggered.
* **Assistants**: An assistant is a conversational and reactive tool...
```

**Agentの特徴**:
- 自律的（autonomous within defined boundaries）
- 目標指向的（goal-oriented）
- 複数ツールを使用可能（able to use tools）
- メモリを持つ（able to have memory）

#### 「ボットを置き換える」という記述

`docs/ai/agents.md`:
```
Service agent replaces traditional chatbots with AI that can handle a wide range 
of service issues without preprogrammed scenarios.
```

`docs/ai/index.md`:
```
They go beyond simple Q&A bots by planning actions, calling external systems, and 
iterating on results.
```

#### ボット非推奨の明示的な記述は見つからない

**重要な発見**: 調査対象のドキュメント内で「ボットユーザーが非推奨（deprecated）」という明示的なアナウンスは**見つかりませんでした**。

- RTM APIは `docs/legacy/` カテゴリーに移動している（レガシー扱い）
- ボットユーザー自体の廃止スケジュールは記載なし
- 新規開発では Agents & AI Apps の利用が推奨される方向感は読み取れる

#### Agents & AI Apps は有料プランが必要

`docs/ai/developing-agents.md`:
```
Developing and using some AI features require a paid plan, despite being visible 
in the app settings on any plan.
```

つまり、従来のボット実装（bot user + Events API）は引き続き利用可能であり、Agent機能（Agents & AI Apps）は有料プランが必要な新しいオプション。

#### 実装での移行パス

| 旧（Bot user パターン） | 新（Agent パターン） |
|---|---|
| Bot user token + Events API | `assistant_write` scope + Agents & AI Apps |
| `@app.event("app_mention")` | `Assistant` クラス |
| `chat.postMessage` 直接呼出 | `say()` / `set_status()` / `SayStream` |
| Typing indicator なし | `assistant.threads.setStatus` |
| RTM API（現在はレガシー） | HTTP Events API（現在の標準） |

---

## 問題・疑問点

### 1. ボットユーザーの正式な非推奨宣言

**状況**: ドキュメント内で明示的な「廃止予定」アナウンスは見つからなかった。ユーザーが「ボットは非推奨になるって聞いた」という情報源は不明（公式のロードマップ・ブログ・SlackConnectコミュニティの情報などの可能性）。

**結論**: 現時点では廃止ではなく、Agent/AI Apps が新しい推奨パターンとして追加されている状況。

### 2. setStatus が通常のbot userでも使えるか

`assistant.threads.setStatus` のAPIは Agents & AI Apps を有効化したAppのAssistant threadで使うAPIとして説明されている。通常のbot userがメンションで呼ばれた場合に使えるかは文書化が不明確。

### 3. response_url の30分・5回制限を超える場合

30分を超える場合は `chat.postMessage` を直接使う必要がある（ドキュメントに明記）。5回制限を超える場合も同様と推測。

---

## 調査アプローチ

- Explorerエージェントに2テーマを並列調査依頼
- 調査対象: `docs/interactivity/`, `docs/messaging/`, `docs/tools/bolt-python/`, `docs/tools/bolt-js/`, `docs/ai/`, `docs/legacy/`
- キーワード: response_url, trigger_id, ack, acknowledge, async, setStatus, typing indicator, deprecated, agent, assistant
