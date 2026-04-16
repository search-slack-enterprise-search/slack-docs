# LambdaとBoltを組み合わせたカスタムエージェント作成方法

## 知りたいこと

LambdaとBoltを組み合わせてカスタムエージェントを作成する方法

## 目的

方法を知りたい。

## 調査サマリー

### Lambda + Bolt for Python でカスタムエージェントを作る基本手順

1. **Slack App 設定**
   - App Settings で「Agents & AI Apps」を有効化
   - スコープ追加: `assistant:write`, `chat:write`, `im:history`
   - イベント購読: `assistant_thread_started`, `assistant_thread_context_changed`, `message.im`

2. **Bolt App の初期化**（Lambda では `process_before_response=True` が必須）
   ```python
   app = App(
       token=os.environ["SLACK_BOT_TOKEN"],
       signing_secret=os.environ["SLACK_SIGNING_SECRET"],
       process_before_response=True,
   )
   ```

3. **Assistant クラスでハンドラを定義**
   ```python
   assistant = Assistant()

   @assistant.thread_started
   def start_thread(say, set_suggested_prompts):
       say("こんにちは！")
       set_suggested_prompts(prompts=[...])

   @assistant.user_message
   def handle_message(client, context, payload, say, set_status, set_title):
       set_title(payload["text"])
       set_status("考えています...")
       # LLM呼び出し
       say(call_llm(...))

   app.use(assistant)
   ```

4. **Lambda エントリーポイント**
   ```python
   from slack_bolt.adapter.aws_lambda import SlackRequestHandler

   def handler(event, context):
       slack_handler = SlackRequestHandler(app=app)
       return slack_handler.handle(event, context)
   ```

5. **Lambda IAM 権限**（Lazy listener 使用時）
   - `lambda:InvokeFunction`, `lambda:GetFunction` が必要（Bolt が Lambda を自己invokeするため）

### 主要 API

| API | 用途 | スコープ |
|-----|------|---------|
| `set_status()` | ローディング表示（2分で自動クリア） | `assistant:write` |
| `set_suggested_prompts()` | 提案プロンプト設定（最大4個） | `assistant:write` |
| `set_title()` | スレッドタイトル設定 | `assistant:write` |

### ポイント

- **3秒制限**: `ack()` は3秒以内に送信必須。長時間処理は Lazy listener で分離
- **Socket Mode**: 開発時に便利だが本番（特にLambda）ではHTTPを推奨
- **LLM は独自実装**: Bolt は骨格のみ提供、LLM呼び出し部分はユーザーが実装する

## 完了サマリー

AWS LambdaとBolt for Pythonを組み合わせてカスタムエージェントを作成する方法を調査した。

重要なポイントは `process_before_response=True` の設定と、長時間処理に対応するための Lazy listener パターン。Assistantクラスを使うことで `thread_started` / `user_message` のイベントを宣言的に処理でき、`set_status()`, `set_suggested_prompts()`, `set_title()` といったユーティリティが使える。Lambda の IAM ロールには `lambda:InvokeFunction` 権限が必要（Lazy listener が Lambda を自己invokeするため）。
