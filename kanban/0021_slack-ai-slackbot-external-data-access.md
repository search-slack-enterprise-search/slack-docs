# Slack AI の Slackbot で外部情報にアクセスさせる方法

## 知りたいこと

Slack AIのSlackbotで外部の情報にアクセスさせる方法

## 目的

Enterprise Searchを使ってもSlackbotで外部の情報にアクセスできないことがわかった。ただ、別の方法を使えばできるとの回答を前回得たのでその方法を知りたい。

## 調査サマリー

### 結論

**Slack の Slackbot（AI assistant）は、カスタムエージェントとして実装し「カスタムツール」を定義することで、外部情報に自由にアクセスできる。**

Slackbot（AI assistant panel）は Slack が中央集権的に提供する Black Box な AI ではなく、開発者がロジックを自由に実装するカスタム Slack アプリとして構築される。`@tool` デコレータで外部 API 呼び出し関数を定義し、LLM フレームワーク（Claude / OpenAI 等）に渡すことで、LLM が外部データを取得・回答を生成できる。

### 主要な方法

1. **カスタムエージェント + カスタムツール（メインアプローチ）**
   - Bolt for Python / JavaScript でアプリを作成
   - `Agents & AI Apps` 機能を有効化（`assistant:write` スコープ）
   - `message.im` イベント（ユーザーメッセージ）を受信
   - `@tool` デコレータで外部 API を呼び出すカスタムツールを定義
   - Claude Agent SDK / OpenAI Agents SDK / Pydantic AI のいずれかと組み合わせて LLM を呼び出す
   - LLM がツールを判断・実行し、外部データを取得して回答を生成
   - `say_stream` でストリーミングレスポンスを返す

2. **ワークフロー AI カスタムステップ**
   - Workflow Builder に AI + 外部 API 呼び出しを含むカスタムステップを組み込む
   - リアルタイム対話ではなくワークフロートリガーベースの統合

3. **Agentforce（Salesforce）**
   - Salesforce プラットフォーム上の AI エージェントを Slack に展開
   - Salesforce プラットフォームが前提

### Enterprise Search との関係

Enterprise Search（検索UI 経由）とカスタムエージェントは完全に独立した仕組み。Slackbot が外部データにアクセスするには Enterprise Search を経由する必要はなく、カスタムエージェントのカスタムツールとして外部 API を直接呼び出す方が標準的な実装方法。

### 関連ドキュメント
- `docs/ai/developing-agents.md` - エージェントの実装詳細（ツール呼び出しの全体フロー）
- `docs/ai/agents.md` - エージェントの概念（ツール使用の説明）
- `docs/ai/agent-quickstart.md` - Casey サンプルアプリ（Claude/OpenAI/Pydantic AI の3フレームワーク対応）
- `docs/tools/bolt-python/concepts/adding-agent-features.md` - カスタムツールの定義方法（`@tool` デコレータの例）
- `docs/ai/workflow-ai-integration.md` - ワークフロー AI 統合

## 完了サマリー

**調査完了日**: 2026-04-16

Slack の Slackbot（AI assistant panel）は、Bolt + LLM フレームワーク（Claude Agent SDK / OpenAI / Pydantic AI）を使ってカスタムエージェントとして構築し、`@tool` デコレータで外部 API 呼び出しのカスタムツールを定義することで、外部情報に自由にアクセスできる。Enterprise Search は不要であり、カスタムツールが LLM によって必要に応じて呼び出され、外部データが取得されてレスポンスに組み込まれる。ただし、Slack の有料プランと、LLM API キー・ホスティングの自前用意が必要。
