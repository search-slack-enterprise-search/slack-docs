# 0034: SlackbotからカスタムエージェントをSlack上で起動する方法と複数エージェントの区別

## 調査日時
2026-04-16

## 調査ファイル一覧

- `docs/ai/agent-entry-and-interaction.md`
- `docs/ai/agents.md`
- `docs/ai/developing-agents.md`
- `docs/ai/agent-governance.md`
- `docs/ai/agent-design.md`
- `docs/reference/events/assistant_thread_started.md`
- `docs/reference/events/assistant_thread_context_changed.md`
- `docs/reference/app-manifest.md`

## 調査アプローチ

Exploreエージェントを使って網羅的に調査した後、主要ドキュメントを直接読み込んで内容を検証。キーワードとして「エントリーポイント」「複数エージェント」「ルーティング」「マニフェスト」等で確認。

---

## 調査結果

### 1. SlackbotからカスタムエージェントをSlack上で起動する方法

#### 1.1 エントリーポイント（起動方法）の全体像

`docs/ai/agent-entry-and-interaction.md` に明記されている通り、Slackはカスタムエージェントを起動するための**4つのエントリーポイント**を提供している。

> "Four interaction surfaces act as entry points:
> - App mentions
> - Direct messages
> - Top bar entry point for launching the agent in a split pane
> - Chat and History tabs in the app UI"

後ろ2つ（Split Pane・Chat/Historyタブ）は、アプリ設定で **「Agents & AI Apps」機能を有効化** した場合のみ利用可能。

#### 1.2 エントリーポイント詳細

##### (A) Top bar entry point / Agent container（推奨）

> "When the Agents & AI Apps feature is enabled in your app settings, the top nav entry point and agent container are available."
> "The native AI assistant panel (split pane in the Slack client), accessible from the top bar. Use for conversational agent interactions: back-and-forth dialogue, multi-turn reasoning, and contextual responses. Interactions here are implemented using the Bolt `Assistant` class."

- Slack UI のトップバーにエージェント起動ボタンが表示される
- ユーザーがボタンをクリックするとSplit Paneが開く
- Boltの `Assistant` クラスで実装する。3つのイベントラッパーを使用:
  - `threadStarted` ← `assistant_thread_started` イベント（コンテナを開いた時）
  - `threadContextChanged` ← `assistant_thread_context_changed` イベント（チャンネル切り替え時）
  - `userMessage` ← `message.im` イベント（ユーザーがメッセージを送信した時）

実装例（JavaScript）:
```javascript
const assistant = new Assistant({
  threadStarted: async ({ say, setSuggestedPrompts }) => {
    await say({ text: 'Hi! How can I help?' });
    await setSuggestedPrompts({
      prompts: [
        { title: 'Summarize a channel', message: 'Summarize the last week of #general' },
        { title: 'Draft a message', message: 'Help me write a project update' }
      ]
    });
  },
  threadContextChanged: async ({ assistantThread }) => {
    // assistantThread.context.channel_id は現在アクティブなチャンネルID
  },
  userMessage: async ({ message, say, setStatus }) => {
    await setStatus({ status: 'Thinking...' });
    // LLMを呼び出してレスポンスを生成し:
    await say({ text: 'Here is your answer.' });
  }
});
app.use(assistant);
```

##### (B) チャンネルでの @メンション

> "The `app_mention` event fires when a user @-mentions your bot in a channel or thread. Always reply in-thread using `thread_ts ?? event.ts`. This uses the `thread_ts` if it exists; otherwise, fall back to `event.ts`."

```javascript
app.event('app_mention', async ({ event, client }) => {
  const channel = event.channel;
  const threadTs = event.thread_ts ?? event.ts;
  await client.chat.postMessage({ channel, thread_ts: threadTs, text: 'On it!' });
});
```

ユーザーがチャンネルまたはスレッドで `@エージェント名` とメンションすると `app_mention` イベントが発火する。

##### (C) ダイレクトメッセージ（DM）

> "Listen for the `message.im` event for when a user messages your agent outside of the assistant container. Filter on `channel_type: im` to distinguish from group DMs."

```javascript
app.message(async ({ message, say }) => {
  if (message.channel_type !== 'im') return;
  await say({ text: 'Got your message!' });
});
```

##### (D) Chat/History タブ（App UI）

「Agents & AI Apps」機能有効時に自動的に利用可能。ユーザーはアプリのUIでChat/Historyタブにアクセスしてエージェントと会話できる。

> "When your app has the Agents & AI Apps feature toggled on, every DM with the user is a thread."
> "When a user navigates to your app, two tabs are available. The History tab is all of the past threads (in which the user has sent a message); this is where they will see new notifications. The Chat tab is the last active thread between the user and your app."

---

### 2. 複数エージェントが設定されている場合の区別方法

#### 2.1 基本的な仕組み：各エージェントは独立したSlackアプリ

ドキュメント内を確認した結果、**Slackでは「複数のカスタムエージェントを自動でルーティング・選択する仕組み」は存在しない**。

各カスタムエージェントはそれぞれ独立したSlackアプリとして存在し、以下の識別子で区別される:

- **`api_app_id`**: アプリの一意のID（`assistant_thread_started` イベントのペイロードに含まれる）

`assistant_thread_started` イベントのペイロード例 (`docs/reference/events/assistant_thread_started.md`):
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

#### 2.2 UIでのエージェント識別方法

各エージェントはSlack UIで以下によって識別される:

- **`bot_user.display_name`**（マニフェストの `features.bot_user.display_name`）: Slack UI上での表示名
- **`assistant_view.assistant_description`**（マニフェストの `features.assistant_view.assistant_description`）: エージェントの説明文

`docs/reference/app-manifest.md` から:
```
features.assistant_view
  Settings related to assistant view for apps using AI features. (Optional)
  
features.assistant_view.assistant_description
  A string description of the app assistant.
  Required (if assistant_view subgroup is included)

features.assistant_view.suggested_prompts
  An array of hard-coded prompts for the app assistant container.
```

`docs/ai/agent-design.md` から:
> "When naming an agent, consider leading with its utility and function rather than a branded name. This allows it to be easily identified in spaces with coworkers, apps and other agents."

つまり、エージェント名はブランド名よりも機能・用途を先頭に置くことが推奨されている（例: 「Sales Assistant」「Code Reviewer」など）。

#### 2.3 ユーザーによる複数エージェントの選択方法

複数のカスタムエージェントがある場合、**ユーザーが手動で選択**する:

1. **トップバーからの選択**: Slackのトップナビゲーションに複数のエージェントが並列表示され、ユーザーがクリックして選択
2. **@メンションで明示的指定**: `@エージェントA` または `@エージェントB` と明示的にメンション
3. **DM先を選択**: 各エージェントのDMチャンネルに個別にメッセージを送信

Slackが自動的にどのエージェントを使うか判断する機能は、ドキュメント内に記載なし。

#### 2.4 マルチエージェント環境での監視と `agent_id`

`docs/ai/agent-governance.md` に複数エージェント環境でのメトリクス追跡として以下が記載:

| Key | Description |
|-----|-------------|
| `agent_id` | Which agent or handler produced this response; **critical in multi-agent setups** |
| `user_id` | User in the interaction |
| `tools_called` | Array of tool names invoked; shows agent decision path |
| `model` | Model name and version; required for cost attribution and regression tracking |

これは**アプリ内部**（開発者側のロギング）での識別であり、Slack側のプラットフォームが自動的に `agent_id` を付与するわけではない。開発者が自分でログに記録するもの。

---

## 判断・意思決定

- 「Slackbotからカスタムエージェントを動かす」という問いについて:
  - Slackbot（通常の bot）とカスタムエージェント（Agents & AI Apps）は異なる概念。カスタムエージェントは独立したSlackアプリとして設定される。
  - 「Slackbotがエージェントを呼び出す」のではなく、「ユーザーがエージェントをSlack UI上で直接起動する」のが正しい理解。
  - ただし、エージェントのアプリに `app_mention` ハンドラを実装することで、通常のbotと同様に @メンション経由で起動することも可能。

- 複数エージェントの区別については:
  - Slackプラットフォーム側での自動ルーティング機能はない
  - 各エージェントは独立したSlackアプリとして存在し、ユーザーが明示的に選択する
  - トップバーの「Agents & AI Apps」UIに複数のエージェントが並列表示される可能性がある

---

## 問題・疑問点

- トップバーに複数のエージェントが表示される場合の具体的なUI挙動（並列表示か、選択画面か）についての詳細なドキュメントは見つからなかった。実際のUIを見てみないと確認できない。
- エージェント間の連携（agent-to-agent handoffs）については `agent-design.md` に「still being defined and under exploration」と記載があり、現時点では未定義。

---

## まとめ

| 質問 | 回答 |
|------|------|
| Slackbotからカスタムエージェントを起動する方法 | カスタムエージェントはSlackアプリとして独立存在。エントリーポイントは4つ: (1) トップバーのSplit Pane（「Agents & AI Apps」有効時）、(2) チャンネルでの@メンション、(3) DM、(4) Chat/Historyタブ |
| 複数エージェントの区別方法 | 自動ルーティングなし。各エージェントは独立したSlackアプリとして `display_name`（表示名）で識別。ユーザーがトップバー・@メンション・DM先の選択で手動指定する |
| 「Agents & AI Apps」有効化の必要性 | Split Pane（トップバー）とChat/Historyタブを使う場合に必要。`assistant:write` スコープが自動追加される |
