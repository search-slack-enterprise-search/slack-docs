# 0026: カスタムエージェントとカスタムボットの実装方法とタイムアウト上限 — 調査ログ

## 調査アプローチ

### 問いの整理

タスク 0025 までの調査で「LLMで回答を生成するのがエージェント、プログラムで生成するのがボット」という概念的区分が判明した。本タスクはその上で：

1. **カスタムエージェントの実装方法** — 具体的にどのように実装するか（Slackアプリ設定・イベント・API）
2. **カスタムボット（非エージェント）の実装方法** — エージェントと比べて何が違うか
3. **タイムアウトの上限** — エージェント・ボット共通の制約値

を調査する。

### 調査手順

1. `docs/ai/developing-agents.md` でエージェントの実装詳細を確認
2. `docs/ai/agents.md` でエージェントの定義・ボットとの区分を確認
3. `docs/ai/agent-quickstart.md` でクイックスタートガイドを確認
4. `docs/apis/events-api/index.md` でイベントAPIのタイムアウト仕様を確認
5. `docs/interactivity/handling-user-interaction.md` でインタラクションのタイムアウトを確認
6. Explore エージェントでlegacy bot usersの情報を含む網羅的な調査を実施

---

## 調査ファイル一覧

- `docs/ai/agents.md`（エージェントの定義・ボットとの区分）
- `docs/ai/developing-agents.md`（エージェント実装の詳細）
- `docs/ai/agent-quickstart.md`（クイックスタート）
- `docs/ai/agent-context-management.md`（コンテキスト管理）
- `docs/apis/events-api/index.md`（タイムアウト・リトライ仕様）
- `docs/interactivity/handling-user-interaction.md`（インタラクションのタイムアウト・response_url）
- `docs/legacy/legacy-bot-users.md`（レガシーボット実装 ※廃止予定）

---

## 調査結果

### 1. エージェントとボットの概念的区分（ドキュメントによる定義）

ソース: `docs/ai/agents.md` 37-41行目（「Agents are not just」セクション）

```
Bots: Bots respond to specific inputs with predetermined outputs with no reasoning, memory, or 
adaptation. They can only do what they were explicitly programmed to do.
```

Slack ドキュメントの明示的な定義：
- **Bot（ボット）**: 特定の入力に対して事前定義された出力を返す。推論・記憶・適応がない
- **Agent（エージェント）**: 自律的に動作、ゴール指向、ツール使用、記憶を持つ
- **Assistant（アシスタント）**: 会話的・反応的なツール。質問への応答はできるが、自律的なアクションを起こせない

---

### 2. カスタムエージェントの実装方法

#### 2-1. 前提条件

ソース: `docs/ai/developing-agents.md` 5-7行目

```
Developing and using some AI features require a paid plan, despite being visible in the app 
settings on any plan.
```

有料プランが必要（ただし Developer Program に参加すれば無料のサンドボックスを取得可能）。

#### 2-2. Slackアプリの設定

ソース: `docs/ai/developing-agents.md` 11-15行目

```
To allow your agent to live in the top bar and be available for interaction in the split plane, 
you'll need to create an app, then find the Agents & AI Apps feature in the sidebar, and enable it.

The assistant:write scope is needed for this, and thus is automatically added to your app. 
It also allows your agent to take advantage of suggested prompts and thread title customization.
```

手順:
1. [api.slack.com/apps](https://api.slack.com/apps) でアプリを作成
2. サイドバーの「**Agents & AI Apps**」機能を有効化
3. `assistant:write` スコープが自動的に追加される

#### 2-3. サブスクライブするイベント

ソース: `docs/ai/developing-agents.md` 17行目

```
You will also want to subscribe to the assistant_thread_started, 
assistant_thread_context_changed, and message.im events.
```

必須イベント:
- `assistant_thread_started`: ユーザーがエージェントコンテナを開いたとき
- `assistant_thread_context_changed`: ユーザーがコンテナを開いたまま別チャンネルに移動したとき
- `message.im`: ユーザーがメッセージを送信したとき（プロンプトのクリックを含む）

#### 2-4. イベント処理の実装フロー

ソース: `docs/ai/developing-agents.md` 23-93行目

**assistant_thread_started イベントの処理**:
```python
# Bolt for Python の例
assistant = Assistant()

@assistant.thread_started
def start_assistant_thread(say, set_suggested_prompts, ...):
    say("How can I help you?")
    prompts = [
        {
            "title": "Suggest names for my Slack app",
            "message": "Can you suggest a few names...",
        },
    ]
    set_suggested_prompts(prompts=prompts)
```

推奨プロンプト設定API（生のAPI呼び出し例）:
```json
{
  "channel_id": "D123ABC456",
  "thread_ts": "1724264405.531769",
  "title": "Welcome. What can I do for you?",
  "prompts": [
    {"title": "Generate ideas", "message": "Pretend you are..."},
    {"title": "Explain what Slack stands for", "message": "What does Slack stand for?"}
  ]
}
```

**message.im イベントの処理**:
```python
@assistant.user_message
def respond_in_assistant_thread(say, set_status, payload, ...):
    # 1. ローディング状態を表示（すぐに）
    set_status(
        status="thinking...",
        loading_messages=["Loading...", "Processing..."],
    )
    # 2. LLM処理または独自ロジック
    # 3. 回答を送信
    say(text="Response here")
```

#### 2-5. ローディング状態の表示

ソース: `docs/ai/developing-agents.md` 107-108行目

```json
{
  "status": "is working on your request...",
  "channel_id": "D324567865",
  "thread_ts": "1724264405.531769"
}
```

APIメソッド: `assistant.threads.setStatus`
ステータスをクリアするには空文字列を送信: `"status": ""`

#### 2-6. テキストストリーミング（推奨応答方法）

ソース: `docs/ai/developing-agents.md` 129-170行目

```
Text streaming is handled by three different API methods: chat.startStream, chat.appendStream, 
and chat.stopStream. These allow the user to see the response from the LLM as a text stream, 
rather than a single block of text sent all at once.
```

3つのAPIメソッド:
1. `chat.startStream` — ストリーム開始（`task_display_mode` で表示モード指定）
2. `chat.appendStream` — チャンクを追加（テキストやタスク更新）
3. `chat.stopStream` — ストリーム終了（最終ブロックを含むことができる）

注意点: Blocks は `chat.stopStream` でのみ使用可能（`chat.startStream` や `chat.appendStream` では不可）。ストリーミングメッセージではunfurlが無効。

Bolt for Python の簡易ストリーミング例:
```python
from slack_bolt import SayStream

def handle_message(say_stream: SayStream):
    streamer = say_stream()
    streamer.append(markdown_text="Here's my response...")
    streamer.append(markdown_text="And here's more...")
    streamer.stop()
```

#### 2-7. スレッドタイトルの設定

ソース: `docs/ai/developing-agents.md` 238-248行目

```
By enabling the Agents & AI Apps feature in the app settings, Slack will automatically group 
your app conversations into threads. You can set the title of these threads using the 
assistant.threads.setTitle API method.
```

APIメソッド: `assistant.threads.setTitle`

```json
{
  "title": "Holidays this year",
  "channel_id": "D123ABC456",
  "thread_ts": "1786543.345678"
}
```

#### 2-8. フィードバック機能

ソース: `docs/ai/developing-agents.md` 185-210行目

`context_actions` ブロック + `feedback_buttons` エレメントでサムズアップ/ダウンを実装できる:

```json
{
  "blocks": [
    {
      "type": "context_actions",
      "elements": [
        {
          "type": "feedback_buttons",
          "action_id": "feedback_buttons_1",
          "positive_button": {
            "text": {"type": "plain_text", "text": "👍"},
            "value": "positive_feedback"
          },
          "negative_button": {
            "text": {"type": "plain_text", "text": "👎"},
            "value": "negative_feedback"
          }
        }
      ]
    }
  ]
}
```

#### 2-9. クイックスタート

ソース: `docs/ai/agent-quickstart.md`

Slack CLI を使ったクイックスタート:
```bash
# 1. Slack CLIのインストール
curl -fsSL https://downloads.slack-edge.com/slack-cli/install.sh | bash

# 2. ワークスペースに接続
slack login

# 3. サポートエージェントのサンプルを作成
slack create agent
```

サポートされる AI エージェントフレームワーク（Bolt for Python）:
- Claude Agent SDK (`claude-agent-sdk/` フォルダ)
- OpenAI Agents SDK (`openai-agents-sdk/` フォルダ)
- Pydantic AI (`pydantic-ai/` フォルダ)

#### 2-10. アクセス制限

ソース: `docs/ai/developing-agents.md` 371-373行目

```
Members only: Workspace guests are not permitted to access apps with the Agents & AI Apps 
feature enabled.
```

ワークスペースゲストはアクセス不可。

---

### 3. カスタムボット（通常のbot user）の実装方法

#### 3-1. ボットの位置づけ

Slack ドキュメントにおいて「カスタムボット」という用語は主に以下を指す：

1. **レガシーカスタムボット**（`docs/legacy/legacy-bot-users.md`）: **2025年3月31日に廃止予定**
2. **通常のSlackアプリのbot user**: 現在の標準実装方法

Explore エージェントの調査によると、ボットの実装は通常の Slack アプリ作成 + bot user の有効化で行う。

#### 3-2. ボットの作成手順

App Management > Bot Users:
- **Display name**: ボットの表示名
- **Default username**: メンション時のユーザー名（@username）
- **Always Show My Bot as Online**: デフォルトでオンライン表示（推奨: 有効）

#### 3-3. Events APIの設定

App Management > Event Subscriptions で:
1. Enable Events を ON
2. Request URL を設定（HTTPS推奨、3秒以内の応答必須）
3. Bot User Events でサブスクリプション追加:
   - `app_mention`: ボットが @メンションされた場合
   - `message.channels`: チャンネルメッセージ

#### 3-4. レスポンスの送信

ボットは `chat.postMessage` APIでメッセージを送信:

```javascript
// Express.js + Node.js の例
router.post("/", function(req, res, next) {
    let payload = req.body;
    
    // すぐにHTTP 200で応答
    res.sendStatus(200);
    
    // イベントタイプを判定して処理
    if (payload.event.type === "app_mention") {
        client.chat.postMessage({
            token: BOT_TOKEN,
            channel: payload.event.channel,
            text: "Bot response"
        });
    }
});
```

#### 3-5. エージェントとボットの実装上の主な違い

| 項目 | カスタムエージェント | カスタムボット |
|------|------------------|--------------|
| Slack UIの位置 | トップバー（スプリットビュー） | チャンネル内メッセージ |
| 必要な機能設定 | 「Agents & AI Apps」を有効化 | Bot User を追加 |
| 自動追加スコープ | `assistant:write` | `bot`（基本） |
| 主要イベント | `assistant_thread_started`, `message.im` | `app_mention`, `message.channels` |
| 応答方法（推奨） | `chat.startStream` / `chat.appendStream` / `chat.stopStream` | `chat.postMessage` |
| ローディング表示 | `assistant.threads.setStatus`（ネイティブ） | 手動でメッセージ更新 |
| 提案プロンプト | `assistant.threads.setSuggestedPrompts` | なし |
| スレッドタイトル | `assistant.threads.setTitle` | なし |
| ゲストアクセス | 不可 | 可（通常は） |

---

### 4. タイムアウト上限

#### 4-1. Events API — イベントへの応答タイムアウト

ソース: `docs/apis/events-api/index.md` 238-243行目

```
Your app should respond to the event request with an HTTP 2xx within three seconds. If it does 
not, we'll consider the event delivery attempt failed. After a failure, we'll retry three times, 
backing off exponentially.
```

**イベント受信 → HTTP 200応答: 3秒以内（必須）**

リトライ仕様:
1. 1回目リトライ: ほぼ即座（immediately）
2. 2回目リトライ: 1分後
3. 3回目リトライ: 5分後

リトライヘッダー:
- `x-slack-retry-num`: リトライ番号（1, 2, 3）
- `x-slack-retry-reason`: 理由（`http_timeout`, `http_error`, `connection_failed`, `ssl_error`, `too_many_redirects`, `unknown_error`）

3秒を超えた場合のリトライ理由: `http_timeout`

#### 4-2. インタラクティブコンポーネント — acknowledgment タイムアウト

ソース: `docs/interactivity/handling-user-interaction.md` 80-84行目

```
All apps must, as a minimum, acknowledge the receipt of a valid interaction payload.

To do that, your app must reply to the HTTP POST request with an HTTP 200 OK response. This 
must be sent within 3 seconds of receiving the payload. If your app doesn't do that, the Slack 
user who interacted with the app will see an error message.
```

**インタラクション（ボタン・ショートカット・モーダルなど）への acknowledgment: 3秒以内**

#### 4-3. response_url の使用制限

ソース: `docs/interactivity/handling-user-interaction.md` 87-93行目

```
These responses can be sent up to 5 times within 30 minutes of receiving the payload.
```

**response_url: 30分以内に最大5回まで使用可能**

#### 4-4. chat.update のレートリミット

ソース: `docs/ai/developing-agents.md` 268行目

```
When updating longer messages sent to a user, only call the chat.update method once every 
3 seconds with new content, otherwise your calls may hit the rate limit.
```

**`chat.update` 呼び出し間隔: 3秒に1回**（レートリミット回避のため）

#### 4-5. Events API の失敗許容限界

ソース: `docs/apis/events-api/index.md` 346-355行目

```
When your application enters any combination of these failure conditions for more than 95% of 
delivery attempts within 60 minutes, your application's event subscriptions will be temporarily 
disabled.
```

60分以内に95%以上の配信失敗が続くとイベントサブスクリプションが一時無効化される。
ただし、1時間に1,000件以下のイベントを受信するアプリは自動無効化されない。

#### 4-6. タイムアウト一覧まとめ

| 項目 | 上限 | 備考 |
|------|------|------|
| Events API イベントへの HTTP 200応答 | **3秒** | 超えると `http_timeout` でリトライ |
| インタラクション（ボタン等）の acknowledgment | **3秒** | 超えるとユーザーにエラー表示 |
| Slash command の ack | **3秒** | Events API共通 |
| response_url の有効期間 | **30分** | 最大5回まで使用可能 |
| response_url の使用回数 | **5回** | 30分以内 |
| Events API リトライ回数 | **3回** | 即座→1分後→5分後 |
| `chat.update` 呼び出し間隔 | **3秒に1回** | レートリミット |
| Events API レートリミット | **30,000件/60分** | ワークスペース×アプリ単位 |

---

## 結論

### カスタムエージェントの実装方法

1. `api.slack.com/apps` でSlackアプリを作成
2. 「Agents & AI Apps」機能を有効化（`assistant:write` が自動付与）
3. `assistant_thread_started`, `assistant_thread_context_changed`, `message.im` イベントをサブスクライブ
4. Bolt for Python/JavaScript の `Assistant` クラスを使って実装（推奨）
5. `assistant.threads.setSuggestedPrompts` でプロンプト提案
6. `assistant.threads.setStatus` でロード状態表示
7. LLMまたは独自ロジックで応答を生成し、`say()` / `chat.startStream` 等で送信

### カスタムボットの実装方法

1. SlackアプリにBot Userを追加（App Management > Bot Users）
2. Events API を有効化し、Request URL を設定
3. `app_mention`, `message.channels` 等のイベントをサブスクライブ
4. イベント受信時に3秒以内に HTTP 200を返し、別途 `chat.postMessage` で応答
5. 注意: レガシーカスタムボット（2025年3月31日廃止）は使わない

### タイムアウトの上限

- **最重要**: Events API、インタラクション、Slash command すべてで **3秒以内** に HTTP 200 を返す必要がある
- 実際の処理は非同期で行い、即座に acknowledgment を返してから処理するのがベストプラクティス
- response_url は **30分以内・最大5回** まで使用可能

---

## 問題・疑問点

1. タスクタイトルで「カスタムボット」と「カスタムエージェント」を区別しているが、Slackドキュメントでは「カスタムボット」という用語は主にレガシーカスタムボット（廃止予定）を指す。現在の「ボット」は通常のSlackアプリのbot user機能として実装される。
2. エージェントと非エージェントのボットはUIの露出点（トップバー vs チャンネル）が異なり、用途に応じて選択する必要がある。
3. タイムアウトはエージェントもボットも同じ3秒だが、エージェントは非同期処理（ストリーミング）が推奨されているため、ユーザー体験の観点でより柔軟な実装が可能。
