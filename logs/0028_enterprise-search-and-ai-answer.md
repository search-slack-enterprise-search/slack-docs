# 調査ログ: Enterprise Search と AI回答・Slackbot統合

## タスク概要

- **タスクファイル**: kanban/0028_enterprise-search-and-ai-answer.md
- **知りたいこと**: Enterprise SearchにおいてAIによる回答も使えるように見える。本当にSlackbotの回答として使えないのか
- **目的**: Slackbotの回答としてEnterprise Searchを使えないのか知りたい

---

## 調査ファイル一覧

### Enterprise Search関連
- `docs/enterprise-search/index.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/connection-reporting.md`
- `docs/enterprise-search/enterprise-search-access-control.md`

### AI/Agent関連
- `docs/ai/index.md`
- `docs/ai/agents.md`
- `docs/ai/developing-agents.md`
- `docs/ai/agent-entry-and-interaction.md`
- `docs/ai/agent-context-management.md`
- `docs/ai/agent-design.md`
- `docs/ai/agent-governance.md`
- `docs/ai/slack-mcp-server.md`
- `docs/ai/workflow-ai-integration.md`
- `docs/other-ai-integrations.md`

### API Reference関連
- `docs/reference/methods/assistant.search.context.md`
- `docs/reference/methods/assistant.search.info.md`
- `docs/reference/methods/search.all.md`
- `docs/reference/methods/search.messages.md`

### Web API関連
- `docs/apis/web-api/real-time-search-api.md`

### Messaging/Work Objects関連
- `docs/messaging/work-objects-overview.md`

---

## 調査結果

### 1. Enterprise Search の AI Answer 機能

#### description と content フィールドが AI Answer に使われる

`docs/enterprise-search/developing-apps-with-search-features.md` (行119-124):
```
`description`

Description of the search results. A cropped version of this description is used to help users 
identify the search results. In the case of AI answers, the entire description will be fed to the 
LLM to provide helpful information in natural language.
```

`docs/enterprise-search/developing-apps-with-search-features.md` (行143-149):
```
`content`

Detailed content of search results. If provided, AI answers will use alongside `title` and 
`description` to generate more comprehensive search answers.

string

Optional
```

**ポイント**:
- `description` フィールドが LLM に直接入力され、AI Answer が生成される
- `content` フィールドはオプションで、より包括的な回答生成に使われる
- アプリ開発者は `description` と `content` を渡すだけで、Slackが自動的にAI Answerを生成する

#### AI Answer のキャッシング

`docs/enterprise-search/developing-apps-with-search-features.md` (行177-181):
```
The search function specified by the `search_function_callback_id` is triggered when users 
perform searches or modify search filters.

Slack caches successful search results for each user and query, for up to three minutes. Since 
search AI answers are generated from the search results, AI answers are also cached for those 
three minutes.
```

---

### 2. Slack AI Search（セマンティックサーチ）

#### assistant.search.context.md より

`docs/reference/methods/assistant.search.context.md` (行287-291):
```
Slack AI Search

Semantic search is available only on workspaces within plans that include Slack AI Search. To 
request a sandbox with this feature, please join the Slack Developer Program and reach out to the 
Slack partnerships team.

To verify if a customer workspace has the Slack AI Search feature enabled, you can use the 
assistant.search.info method.
```

`docs/reference/methods/assistant.search.context.md` (行293-300):
```
Semantic search is triggered when the `query` provided is structured as a natural language 
question. This includes queries that:

* Begin with a question word such as what, where, how, etc.
* End with a question mark (?).

When semantic search is triggered, the API retrieves results that are topically related to the 
question, even if the exact keywords aren't present.

Note: Semantic search may introduce higher response latency compared to keyword search.
```

#### assistant.search.info メソッド

`docs/reference/methods/assistant.search.info.md` (行66-68):
```
Retrieve search capabilities on a given team. When `is_ai_search_enabled` returns true, semantic 
search is possible.
```

---

### 3. Real-time Search API（Slackデータをエージェントに提供）

`docs/apis/web-api/real-time-search-api.md` (行1-10):
```
The Real-time Search (RTS) API allows apps to access Slack data through a secure search interface. 
This approach enables third-party applications to retrieve relevant Slack data without storing 
customer information on external servers. Supplying this data as context to a large language model 
(LLM) helps ensure more relevant and accurate responses to user queries. Read on to discover how 
to employ this API exclusively in your app using AI features.
```

**ポイント**: RTS API（`assistant.search.context` が中核）は、カスタムエージェントがSlackデータをコンテキストとしてLLMに渡すために設計されている。

---

### 4. Agent Context Management での assistant.search.context の使い方

`docs/ai/agent-context-management.md` (行21-26):
```
Use the assistant.search.context API method for cross-workspace context gathering across messages, 
files, channels, and canvases. Phrasing the query as a natural language question will trigger Slack 
to use semantic search. This method requires an `action_token` from the triggering event payload 
when using a bot token. Do not use the legacy search.messages endpoint. Reference the Real-time 
Search API docs for more information.
```

**ポイント**:
- カスタムエージェントが Slack データを検索する場合、`assistant.search.context` を使う
- 自然言語の質問形式にするとセマンティックサーチが発動する
- bot token を使う場合は `action_token`（イベントペイロード内）が必要
- レガシーの `search.messages` は使わないこと

---

### 5. Work Objects と Enterprise Search の AI Answers の連携

`docs/messaging/work-objects-overview.md` (行87-92):
```
To support Work Objects for your app's Enterprise Search results, traditional search results, and 
AI answers citations, your app must subscribe to the `entity_details_requested` event. You can 
define the type of Work Objects for your search results, such as an item, within the Work Object 
Previews view within app settings.

Once your app is subscribed to the `entity_details_requested` event, it can respond to the event 
and call the `entity.presentDetails` API method with Work Object metadata to launch the flexpane 
experience.
```

**ポイント**: AI Answers の引用元（citations）として Work Objects が使われる。ユーザーがAI Answerの引用をクリックするとflexpaneでWork Objectの詳細が表示される。

---

### 6. Slack MCP Server 経由での外部AI連携

`docs/ai/slack-mcp-server.md` (行1-50の要旨):
- Slack MCP Server を経由すると、Claude.ai・Claude Code・Perplexity・Cursor などの外部AIエージェントが `assistant.search.context` を呼び出せる
- MCP（Model Context Protocol）標準に基づく
- 外部のAIからSlackデータにアクセスして回答生成する方法

---

## Enterprise Search + AI回答の仕組み全体像

```
[Enterprise Search の AI Answers フロー]
ユーザーが Slack で検索クエリを入力
         ↓
Enterprise Search が実行
（search_function_callback_id に紐付いたカスタムステップが実行）
         ↓
アプリが search_results オブジェクトを返却
（title, description, content フィールドを含む）
         ↓
Slack がキャッシュ（3分間）
         ↓
Slack AI Search 機能が有効な場合、
LLM が description と content を使用して
自動的にAI Answerを生成
         ↓
ユーザーに AI-generated answer を表示

[Custom Agent + assistant.search.context フロー]
ユーザーがエージェントにメッセージ送信
         ↓
エージェントが assistant.search.context API を呼び出し
（クエリを自然言語の質問形式にするとセマンティックサーチ発動）
         ↓
Slackデータ（messages, files, channels, canvases）を取得
         ↓
取得したデータをコンテキストとしてLLMに渡す
         ↓
LLMが回答生成 → ユーザーに返答
```

---

## Slackbotの回答としてEnterprise Searchを使う方法まとめ

### 方法1: Enterprise Search のネイティブ AI Answers（最も簡単）

**実装**: アプリの search_results で `description` と `content` フィールドを充実させるだけ

**動作**: ユーザーが Enterprise Search で検索すると、Slack が自動的に AI Answer を生成して表示する

**条件**: Slack AI Search（Business+ または Enterprise+ の有料機能）が有効なワークスペースが必要

**ポイント**: Slackbotが「返答する」わけではなく、Slackがネイティブに Enterprise Search の UI 上で AI Answer を表示する仕組み

---

### 方法2: Custom Agent + assistant.search.context API（カスタム実装）

**実装**: カスタムエージェントが `assistant.search.context` で Slack データを検索し、自前の LLM で回答を生成してユーザーに返す

```python
@assistant.user_message
async def respond_to_message(message, client, say, set_status):
    set_status("Slackを検索中...")
    
    # Slackデータを検索
    results = await client.assistant_search_context(
        query=message['text'],  # 自然言語の質問形式にするとセマンティックサーチ
        action_token=message['metadata']['event_payload']['action_token']
    )
    
    # LLMで回答生成
    response = call_llm(context=results, query=message['text'])
    
    say(response)
```

**ポイント**: Slack内チャンネルの過去メッセージやファイルを検索して回答できる。Enterprise Searchの外部データソース結果は含まれないことに注意。

---

### 方法3: Slack MCP Server 経由（外部AIとの連携）

**実装**: Claude.ai 等の外部AIが Slack MCP Server を通じて assistant.search.context を呼び出す

**ポイント**: 外部AIプラットフォームからSlackデータにアクセスする場合に使う

---

## 問題・疑問点

### 1. Enterprise Search の AI Answers は Slackbot ではない

ユーザーが懸念していた「SlackbotとしてEnterprise Searchを使えないか」について:

- Enterprise Search の AI Answers はSlackの検索UI内でネイティブに表示される機能であり、Slackbotが返答するわけではない
- ただし、「検索結果に基づいてAIが回答を生成して表示する」という目的において、Enterprise SearchのAI Answersは**まさにその目的を果たしている**

### 2. 「Slackbotの回答としてEnterprise Searchを使う」は表現の問題

カスタムbot/agentがEnterprise Searchで構築した外部データソースの結果を取得して回答するAPIは直接存在しない。ただし:

- 方法1: Enterprise Search UI内でSlackがネイティブにAI Answerを表示（bot返答ではないがAI回答は実現）
- 方法2: Custom AgentがSlackデータ（`assistant.search.context`）を検索して回答生成（Enterprise Search外部データソースではなくSlack内データ）

### 3. 外部データソース（Enterprise Search）をAgentが直接検索するAPIは未確認

Enterprise Searchに登録した外部データソース（WikiなどのカスタムConnector）の検索結果を、カスタムAgentが直接取得するためのAPIについては明示的なドキュメントが見つかなかった。Enterprise SearchはSlack検索UI向けの機能として設計されている。

---

## 調査アプローチ

- Explorer エージェントに Enterprise Search + AI回答のテーマで調査依頼
- 調査対象: `docs/enterprise-search/`, `docs/ai/`, `docs/apis/web-api/`, `docs/reference/methods/`, `docs/messaging/`
- キーワード: AI answer, description, content, assistant.search.context, semantic search, Slack AI Search, MCP Server
