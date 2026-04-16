# 0035: SlackbotからカスタムエージェントをSlackから起動する方法

## 調査日時
2026-04-16

## 調査ファイル一覧

- `docs/ai/agent-entry-and-interaction.md`
- `docs/ai/agents.md`
- `docs/ai/developing-agents.md`
- `docs/ai/agent-design.md`
- `docs/ai/agent-governance.md`
- `docs/ai/agent-quickstart.md`
- `docs/tools/bolt-js/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-js/concepts/adding-agent-features.md`
- `docs/tools/bolt-python/concepts/using-the-assistant-class.md`
- `kanban/0034_slackbot-custom-agent-invocation.md` および対応ログ（先行タスク参照）

## 調査アプローチ

タスク0034で「カスタムエージェントの4つのエントリーポイント」は既に確認済み。
今回の新しい問いは「**既存Slackbotから**カスタムエージェントを起動させたい」＝UIを一カ所に統一したい、という点に焦点を当てた。

具体的には以下の観点で調査:
1. 一つのSlackアプリがSlackbotとカスタムエージェントの両方の役割を担えるか？
2. 別々のSlackアプリ（BotAがAgentBを呼び出す）という構成は可能か？
3. 実際のサンプルアプリ（Casey）はどういう実装か？

---

## 調査結果

### 1. 「Slackbotからカスタムエージェントを起動」の正しい解釈

#### 1.1 Slackbotとカスタムエージェントは別概念だが、同一アプリに統合可能

`docs/ai/agents.md` に明示:

> "Bots: Bots respond to specific inputs with predetermined outputs with no reasoning, memory, or adaptation. They can only do what they were explicitly programmed to do."

カスタムエージェント（Agents & AI Apps）は従来のbotとは異なるが、**同一のSlackアプリに共存させることができる**。

#### 1.2 同一アプリに統合する方法（推奨）

`docs/tools/bolt-js/concepts/using-the-assistant-class.md` より:

```javascript
const assistant = new Assistant({
  threadStarted: async ({ say, setSuggestedPrompts }) => { ... },
  threadContextChanged: async ({ saveThreadContext }) => { ... },
  userMessage: async ({ message, say, setStatus }) => { ... },
});
app.use(assistant);  // 既存のapp.event('app_mention', ...) 等と共存する
```

**`app.use(assistant)` を追加するだけで、既存のbotハンドラー（`app_mention`等）はそのまま動作し続ける。**

設定手順（`docs/tools/bolt-js/concepts/using-the-assistant-class.md`）:

1. App Settings で **「Agents & AI Apps」** 機能を有効化
2. OAuth & Permissions に以下のスコープを追加:
   - `assistant:write`
   - `chat:write`
   - `im:history`
3. Event Subscriptions に以下を追加:
   - `assistant_thread_started`
   - `assistant_thread_context_changed`
   - `message.im`

これにより、1つのSlackアプリが以下の全てを処理できる:
- チャンネルでの `@メンション`（`app_mention` ハンドラー）
- 通常のDM（`message.im` ハンドラー）
- Assistantコンテナ（Split Pane）経由の会話（`Assistant` クラス）

#### 1.3 サンプルアプリ「Casey」の実装パターン

`docs/ai/agent-quickstart.md` および `docs/tools/bolt-js/concepts/adding-agent-features.md` より:

公式サンプルアプリ「Casey」は、1つのBoltアプリで以下の3つを同時に処理している:

1. **`app_mention` ハンドラー**: チャンネルで @Casey とメンションされた場合に処理
   ```javascript
   export async function handleAppMentioned({ client, context, event, sayStream, setStatus }) {
     // strip @mention, run agent, stream response
   }
   ```

2. **`message` ハンドラー**: DM または チャンネルスレッドでの返信を処理
   ```javascript
   export async function handleMessage({ event, say, sayStream, setStatus }) {
     const isDm = event.channel_type === 'im';
     const isThreadReply = !!event.thread_ts;
     // DMは常に処理、スレッド返信はbotが既に参加している場合のみ処理
   }
   ```

3. **`assistant_thread_started` ハンドラー**: Split Pane が開かれた場合に処理
   ```javascript
   export async function handleAssistantThreadStarted({ client, event }) {
     await client.assistant.threads.setSuggestedPrompts({
       prompts: SUGGESTED_PROMPTS,
     });
   }
   ```

これら全てが一つのアプリに統合されている。

#### 1.4 Bolt Pythonでの「bot_message」ハンドラーによる内部連携

`docs/tools/bolt-python/concepts/using-the-assistant-class.md` に、さらに高度なパターンが記載されている。

ユーザーがボタンをクリック → モーダルで詳細入力 → **ボットがボット自身のメッセージをポスト** → `@assistant.bot_message` ハンドラーが受信してエージェント処理を実行するというパターン:

```python
app = App(
    token=os.environ["SLACK_BOT_TOKEN"],
    # ボット自身のメッセージイベントを無視しないよう設定（デフォルトは無視）
    ignoring_self_assistant_message_events_enabled=False,
)

@assistant.bot_message
def respond_to_bot_messages(logger, set_status, say, payload):
    if payload.get("metadata", {}).get("event_type") == "assistant-generate-random-numbers":
        # ボット自身のメッセージに基づいてエージェント処理を実行
        set_status("is generating...")
        say(f"Here you are: {', '.join(nums)}")
```

これはApp内部でのルーティングであり、異なるアプリ間の連携ではない。
デフォルトでは「自分自身のbot_messageは無視」するため、`ignoring_self_assistant_message_events_enabled=False` の設定が必要。

---

### 2. 異なるSlackアプリ（BotA → AgentB）の連携は非対応

#### 2.1 Slack APIに「エージェント呼び出し」APIは存在しない

調査したドキュメント（`agent-entry-and-interaction.md`、`agents.md`、`developing-agents.md`）の全体を確認したが、**Bot AがBot B（異なるSlackアプリ）のエージェント機能をプログラム的に呼び出すAPIは存在しない**。

カスタムエージェントのエントリーポイント4つ（トップバー・@メンション・DM・Chat/Historyタブ）は全て**ユーザー起動**であり、別のbotからAPIで呼び出すことはできない。

#### 2.2 agent-design.md の「agent-to-agent handoffs」について

`docs/ai/agent-design.md` に以下の記載あり:

> "Some newer interaction patterns like ambient agents and agent-to-agent handoffs are still being defined and under exploration. Think of this as a living document."

エージェント間のハンドオフ（連携）は**現時点では未定義・検討中**とされている。将来的に対応される可能性はあるが、現状では非対応。

#### 2.3 技術的な迂回手段（非推奨）

理論上は以下のような迂回が考えられるが、ドキュメントに記載はなく推奨されない:

- Bot A が `chat.postMessage` でチャンネルに @AgentB をメンションするメッセージをポスト → AgentB の `app_mention` が発火
- ただし AgentB はこれを「ユーザーのメッセージ」ではなく「botのメッセージ」として受信するため、通常は無視される（Boltのデフォルト挙動）
- AgentB が `ignoring_self_assistant_message_events_enabled=False` 相当の設定をしていればハンドリング可能だが、セキュリティ上も設計上も適切ではない

---

### 3. 「UIを一カ所にまとめる」ための推奨実装パターン

目的（UIを一カ所にまとめる）を達成する最も正しいアプローチ:

#### パターン1: 既存SlackbotアプリにAgents & AI Apps機能を追加（最推奨）

```
既存Slackbotアプリ
├── app.event('app_mention', ...)      # チャンネル@メンション
├── app.message(...)                   # 通常メッセージ/DM
├── app.command('/slash', ...)         # スラッシュコマンド
└── app.use(assistant)                 # ← 追加するだけでエージェント機能が有効化
    ├── threadStarted: ...             # Split Pane起動時
    ├── threadContextChanged: ...      # コンテキスト変更時
    └── userMessage: ...              # ユーザーメッセージ受信時
```

- 一つのSlackアプリがユーザーにとって単一のUI
- ユーザーはDM・@メンション・Split Paneのいずれからでも同じbotと対話できる
- 必要に応じてエントリーポイントごとに処理を分岐させることが可能

#### パターン2: Caseyパターン（イベント別ハンドラー分割）

`docs/ai/agent-quickstart.md`・`docs/tools/bolt-js/concepts/adding-agent-features.md` で示されているCaseyの設計:

```
一つのBoltアプリ
├── handleAppMentioned()          # @メンション → エージェント処理
├── handleMessage()               # DM/スレッド → エージェント処理
└── handleAssistantThreadStarted() # Split Pane起動 → サジェストプロンプト設定
```

全てのエントリーポイントを一つのアプリが処理し、ユーザーはどこからでも同じエージェントと対話できる。

---

## 判断・意思決定

- **「SlackbotからカスタムエージェントをSlackから起動する」** という問いの正しい解釈は「**既存のSlackbotアプリにエージェント機能（Agents & AI Apps）を追加して、1つのアプリでbotとagentの両方を担う**」こと。
- 別々のアプリをAPI連携で繋ぐ方法はSlackが提供しておらず、agent-to-agent handoffsも現時点では未定義。
- 実装のキーは `app.use(assistant)` を既存のBoltアプリに追加すること。これにより既存ハンドラーへの影響なしにエージェント機能が追加される。
- Bolt Python と Bolt JS どちらも同様のパターンをサポート。

---

## 問題・疑問点

- 既存Slackbotが `message.im` のリスナーを既に持っている場合、`Assistant` クラスの `userMessage` ハンドラー（これも `message.im` を処理する）との競合をどう避けるかは要注意。Boltは最初にマッチしたリスナーが処理するため、実装順序に依存する可能性がある。
- `ignoring_self_assistant_message_events_enabled=False` の設定はBot Pythonのみ確認。Bot JSでは同等設定があるか確認できなかった。
- エージェント間のハンドオフ（agent-to-agent handoffs）は「under exploration」とされており、将来的にAPIが提供される可能性はある。

---

## まとめ

| 質問 | 回答 |
|------|------|
| Slackbotからカスタムエージェントを起動する方法 | 別々のアプリを連携する方法はない。既存SlackbotアプリにAgents & AI Apps機能を有効化して `app.use(assistant)` を追加し、一つのアプリでbot＋agent両方を担う |
| UIを一カ所にまとめる方法 | 1つのSlackアプリで `app_mention`・`message.im`・`assistant_thread_started` の全エントリーポイントを処理する（Caseyパターン） |
| 別Slackアプリのエージェントを呼び出せるか | 不可。Slackに「エージェント呼び出し」APIはなく、agent-to-agent handoffsも未定義（検討中） |
| 設定手順 | App SettingsでAgents & AI Apps有効化 → `assistant:write`・`chat:write`・`im:history`スコープ追加 → 3つのイベント登録 → `app.use(assistant)` 追加 |
