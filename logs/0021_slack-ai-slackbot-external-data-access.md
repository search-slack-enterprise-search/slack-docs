# 0021: Slack AI の Slackbot で外部情報にアクセスさせる方法 — 調査ログ

## 調査アプローチ

### 前提・背景

タスク 0020 の調査で「Enterprise Search を使っても Slackbot（AI assistant panel）から外部データへのアクセスはできない」ことが判明した。本タスクでは、Enterprise Search 以外の方法で Slack の Slackbot（AI assistant）に外部情報をアクセスさせる方法を調査する。

### 調査手順

1. `docs/ai/` 配下のドキュメント群（agents.md, developing-agents.md, agent-quickstart.md, agent-context-management.md, agent-entry-and-interaction.md, slack-mcp-server.md, workflow-ai-integration.md, other-ai-integrations.md）を網羅的に精読
2. Bolt フレームワークのエージェント機能ドキュメント（`docs/tools/bolt-python/concepts/adding-agent-features.md`）を精読
3. Slack MCP Server の詳細（`docs/ai/slack-mcp-server/developing.md`）を確認
4. タスク 0020 の kanban・ログファイルを参照し、調査済み内容との差分を確認

---

## 調査ファイル一覧

- `docs/ai/index.md`
- `docs/ai/agents.md`
- `docs/ai/developing-agents.md`
- `docs/ai/agent-quickstart.md`
- `docs/ai/agent-context-management.md`
- `docs/ai/agent-entry-and-interaction.md`
- `docs/ai/agent-design.md`
- `docs/ai/slack-mcp-server.md`
- `docs/ai/slack-mcp-server/developing.md`
- `docs/ai/workflow-ai-integration.md`
- `docs/other-ai-integrations.md`
- `docs/tools/bolt-python/concepts/adding-agent-features.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`（参考：前タスクの内容確認）
- `kanban/0020_enterprise-search-slackbot-integration.md`（前回調査の参照）
- `logs/0020_enterprise-search-slackbot-integration.md`（前回調査ログの参照）

---

## 調査結果

### 1. Slackbot（AI assistant）の根本的な仕組み

ソース: `docs/ai/developing-agents.md`, `docs/ai/agents.md`

Slack の Slackbot相当機能（AI assistant panel）は、Slack が提供するフレームワークを使って**開発者が自分でカスタム実装する「AI エージェント」**として構築される。重要な点は以下の通り：

- Slackbot（AI assistant）は Slack が中央集権的に提供する「Black Box な AI」ではなく、**開発者がロジックを実装するカスタム Slack アプリ**
- アプリが `Agents & AI Apps` 機能を有効にすると、スプリットビューの AI assistant panel に登場できる
- `message.im` イベントでユーザーメッセージを受信し、**任意のロジックで応答を返せる**
- つまり、外部 API を呼び出すコードを実装すれば外部情報に自由にアクセスできる

ドキュメント原文（`docs/ai/agents.md`）：
> "Agents are autonomous, goal-oriented AI apps that can reason, use tools, and maintain context across conversations in Slack."

> "Able to use tools: Agents take actions using tools; these are functions the agent can invoke to read or write to external systems."

---

### 2. カスタムエージェント（Bolt + LLM）による外部データアクセス（最主要アプローチ）

ソース: `docs/tools/bolt-python/concepts/adding-agent-features.md`

**最も直接的かつ標準的な方法**は、Bolt for Python（または JavaScript）+ LLM フレームワークを使ってカスタムエージェントを構築し、外部 API 呼び出し用のカスタムツールを定義することである。

#### 実装の流れ

1. **Bolt アプリを作成**し、`Agents & AI Apps` 機能を有効化する
   - 必要スコープ: `assistant:write`
   - イベント購読: `assistant_thread_started`, `message.im`

2. **ユーザーメッセージのリスナーを実装**する（`message.im` イベント）

3. **カスタムツールを定義**する（`@tool` デコレータ）
   - これが外部情報へのアクセスを実現するキーポイント

ドキュメントのカスタムツール定義例（`check_github_status_tool`）：

```python
from claude_agent_sdk import tool
import httpx

@tool(
    name="check_github_status",
    description="Check GitHub's current operational status",
    input_schema={},
)
async def check_github_status_tool(args):
    """Check if GitHub is operational."""
    async with httpx.AsyncClient() as client:
        response = await client.get("https://www.githubstatus.com/api/v2/status.json")
        data = response.json()
        status = data["status"]["indicator"]
        description = data["status"]["description"]
        return {
            "content": [
                {
                    "type": "text",
                    "text": f"**GitHub Status** — {status}\n{description}",
                }
            ]
        }
```

このツールを LLM エージェント（Claude / OpenAI / Pydantic AI）に渡すと、LLM が必要に応じてツールを呼び出して外部情報を取得し、回答を生成する。

#### 対応 LLM フレームワーク（複数対応）

ドキュメント（`docs/ai/agent-quickstart.md`）によると、Slack の公式サンプルアプリ「Casey」は以下の3フレームワークをサポート：

- **Claude Agent SDK**（Anthropic）
- **OpenAI Agents SDK**
- **Pydantic AI**

ユーザーが選択したフレームワークで、カスタムツールを登録してエージェントを実行する。

#### エージェントの呼び出しパターン

ドキュメントでは、以下の複数エントリーポイントから Slackbot を呼び出せる：
- **DM（Direct Message）**: `message.im` イベント
- **@mention（チャンネルでの呼び出し）**: `app_mention` イベント
- **AI assistant panel（スプリットビュー）**: `assistant_thread_started` + `message.im`

どのパターンでも、LLM + カスタムツールのロジックを使えば外部データにアクセスできる。

---

### 3. カスタムエージェント実装の具体的フロー

ソース: `docs/ai/developing-agents.md`（Full example セクション）

ドキュメントに掲載されている完全な実装例（JavaScript + OpenAI）のフロー：

```
1. setStatus で「Searching...」を表示
2. chat.startStream でストリームを開始（plan_display_mode）
3. 外部 API / ツールを呼び出してデータ取得
4. chat.appendStream でタスク状態を更新（in_progress → complete）
5. LLM（GPT-4.1-mini, Claude など）に外部データを context として渡す
6. LLM が回答を生成
7. chat.stopStream でレスポンスを送信（Block Kit も使用可能）
```

重要ポイント：外部データを LLM に渡す部分：

```javascript
const sourceContext = state.sources.map((s) => `• ${s.text} (${s.link})`).join('\n');
const completion = await llm.responses.create({
    model: 'gpt-4.1-mini',
    input: `Goal: ${state.goal}\n\nRelevant context:\n${contextBlock}\n\n...`
});
```

「外部 API を呼んで取得したデータ」→「LLM の context に追加」→「LLM が回答生成」という流れ。

---

### 4. Slack MCP Server の位置づけ（外部データアクセスではない）

ソース: `docs/ai/slack-mcp-server.md`

Slack MCP Server は **Slack 内データ**（メッセージ・チャンネル・キャンバス・ユーザー）へのアクセスを提供するものであり、**外部データへのアクセスには使えない**。

Slack MCP Server が提供する機能：
- メッセージ・ファイル検索
- チャンネル・ユーザー検索
- メッセージ送信
- キャンバスの作成・読み込み・更新

外部データ（社内 Wiki・独自システム等）へのアクセスには Slack MCP Server は使えない。

ただし、カスタムエージェントが **Slack MCP Server を通じて Slack 内データを参照しながら**、同時に**カスタムツールで外部 API を呼び出す**というハイブリッドな構成は可能。

---

### 5. ワークフロー AI 統合（オプション）

ソース: `docs/ai/workflow-ai-integration.md`

もう一つのアプローチとして、Workflow Builder の**カスタムステップ**に AI + 外部 API 呼び出しを組み込む方法がある。

```javascript
app.function("code_assist", async ({ client, inputs, logger, complete, fail }) => {
    // 外部 AI（Hugging Face, OpenAI 等）を呼び出して回答を生成
    const modelResponse = await hfClient.chatCompletion({...});
    await complete({ outputs: { message: modelResponse } });
});
```

ただしこれは、**ワークフロートリガーベース**の統合であり、ユーザーと Slackbot がリアルタイムで対話する形式ではない。  
リアルタイムな Slackbot 対話には、メソッド2（カスタムエージェント）が適している。

---

### 6. Agentforce（Salesforce）によるアプローチ（参考）

ソース: `docs/other-ai-integrations.md`

Salesforce Agentforce を使うと、Slack 内に Salesforce プラットフォームの AI エージェントを展開できる。Salesforce のデータや外部システムに接続したエージェントを Slack 上で動かすことが可能。ただし、Salesforce プラットフォームが前提となる。

---

## 結論

### Slack の Slackbot で外部情報にアクセスさせる方法

**主要アプローチ: カスタム AI エージェントをカスタムツール付きで構築する**

| 方法 | 説明 | リアルタイム対話 | 難易度 |
|------|------|-----------------|--------|
| **カスタムエージェント + カスタムツール** | Bolt + LLM + `@tool` で外部 API を呼び出す | ○ | 中 |
| **ワークフロー AI カスタムステップ** | Workflow Builder のステップに外部 API を組み込む | △（非同期） | 低〜中 |
| **Agentforce（Salesforce）** | Salesforce プラットフォーム上のエージェントを Slack 展開 | ○ | 高（Salesforce 前提） |

### 標準的な実装ステップ（カスタムエージェント）

1. Bolt for Python（または JavaScript）でアプリを作成
2. `Agents & AI Apps` 機能を有効化（`assistant:write` スコープ取得）
3. `assistant_thread_started` + `message.im` イベントを購読
4. LLM フレームワーク（Claude Agent SDK / OpenAI / Pydantic AI）を選択
5. **外部 API を呼び出すカスタムツールを定義**（`@tool` デコレータ）
6. ユーザーのメッセージを LLM + ツールに渡し、外部データを取得・回答を生成
7. `say_stream` でストリーミングレスポンスを返す

### Enterprise Search との関係

Enterprise Search（検索UI 経由）とカスタムエージェントは**完全に独立した仕組み**。  
Slackbot が外部データにアクセスするには Enterprise Search を経由する必要はなく、むしろカスタムエージェントのカスタムツールとして外部 API を直接呼び出す方が自然な実装。

---

## 問題・疑問点

1. カスタムエージェントは各組織が自前で LLM API キー・ホスティングを用意する必要がある（Slack が LLM を提供するわけではない）
2. `Agents & AI Apps` 機能は Slack の有料プランが必要（ドキュメント: "Developing and using some AI features require a paid plan"）
3. Slack MCP Server の外部 MCP サーバーへの接続（Slack の MCP サーバーではなく、自社の MCP サーバーを持つ場合）の詳細はドキュメントに記述なし
