# 0025: カスタムエージェントで LLM は必須か（回答を自前で組み立てても良いのか） — 調査ログ

## 調査アプローチ

### 問いの整理

タスク 0023 の調査で「LLM がテキストを生成し、markdown_text でそのまま送れる」という結論が出た。本タスクはその更問いとして、以下を明確化する：

1. **カスタムエージェントで LLM は必須か？** → プログラムで回答テキストを組み立てても良いのか？
2. **カスタムエージェントの責任範囲は？** → MCP Server と同じく「情報提供まで」でよいのか、「完全な回答の作成・送信」まで必要なのか？

ユーザーが MCP を持ち出した意図は「MCP Server はデータを提供するまでが役割であり、回答生成は LLM が担う」という構造と比較することで、カスタムエージェントにはどこまでの責任があるかを確かめたかった。

### 調査手順

1. `docs/ai/developing-agents.md` の「response loop」「app logic」「LLM prompt or your app logic」の記述を確認
2. `docs/ai/agents.md` の「Agents are not just: Bots」の区分を確認
3. `docs/ai/agent-governance.md` の「deterministic fallback」記述を確認
4. Bolt Python / JS の `using-the-assistant-class.md` の実装例を確認
5. `docs/ai/slack-mcp-server.md` の MCP Server 役割定義を確認・比較

---

## 調査ファイル一覧

- `docs/ai/developing-agents.md`（重点確認）
- `docs/ai/agents.md`
- `docs/ai/agent-governance.md`
- `docs/tools/bolt-python/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-js/concepts/using-the-assistant-class.md`
- `docs/ai/slack-mcp-server.md`（MCP の役割確認）

---

## 調査結果

### 1. 「LLM prompt or your app logic」— LLM は必須ではない

ソース: `docs/ai/developing-agents.md` 87行目

```
You can also fetch previous thread messages using the conversations.replies method and choose 
which other messages from the conversation to include in the LLM prompt or your app logic.
```

ドキュメントは「LLM プロンプト**または**アプリロジック」という二択で記述している。LLM を使わずに独自のアプリロジック（プログラムによる応答生成）も選択肢として明示的に認めている。

---

### 2. レスポンスループの定義 — アプリが「出力」を担う責任

ソース: `docs/ai/developing-agents.md` 9行目

```
This guide takes you through developing the response loop of an agent. 
The response loop is a cycle of receive input → reason → call tools → stream/render output → repeat if needed.
```

このレスポンスループの最後のステップ「**stream/render output**」はカスタムエージェント（Bolt アプリ）が実行する。Slack プラットフォームが代わりに出力を生成するわけではない。

「reason」（推論）は LLM が担うのが典型だが、deterministic なアプリロジックでも実現可能。

---

### 3. Block Kit は必須ではない — プレーンテキストでよい

ソース: `docs/ai/developing-agents.md` 266行目

```
Provide interactive Block Kit elements, such as drop-down menus and buttons, to allow your user to 
interact with the app. Block Kit is not required, however; you can forgo interactivity and message 
the user via plain text and Slack markdown.
```

Block Kit は必須ではなく、プレーンテキストや Slack markdown でも良い。

---

### 4. 「Bots vs Agents」の概念的区分

ソース: `docs/ai/agents.md` 39行目（「Agents are not just」セクション）

```
Bots: Bots respond to specific inputs with predetermined outputs with no reasoning, memory, or 
adaptation. They can only do what they were explicitly programmed to do.
```

Slack の定義では：
- **Bot**（ボット）: 特定の入力に対して事前定義された出力を返す。LLM を使わずプログラムで応答を生成するものはこれに相当
- **Agent**（エージェント）: 自律的・目標指向・ツール使用・推論能力を持つもの

**技術的制約ではなく概念的区分**：Slack のプラットフォームは LLM なしでも `Agents & AI Apps` 機能を使う Bolt アプリを動作させることができる。ただし Slack が「agent」と呼ぶのは AI/LLM を使ったものを指す。

---

### 5. Deterministic fallback の存在 — LLM なしの応答もあり得る

ソース: `docs/ai/agent-governance.md` 90行目

```
Reusable patterns and deterministic fallback handling: Use deterministic, local fallback messages 
when things go wrong. For example, have the agent respond with "I could not format that response 
safely. Try again." or "I hit a temporary processing issue. Retry in a moment.", rather than 
outputting raw model payload when validation fails.
```

LLM を使うエージェントでも、エラー時や特定条件では**固定文字列（プログラムで決定論的に生成されたテキスト）**を返すことが推奨されている。これは LLM なしの応答が技術的に可能であることの傍証。

---

### 6. Bolt Python 実装例 — `call_llm()` は置き換え可能な関数

ソース: `docs/tools/bolt-python/concepts/using-the-assistant-class.md`

```python
returned_message = call_llm(messages_in_thread)  # LLM を呼ぶカスタム関数
say(text=returned_message)                        # Slack へ返信（必須）
```

`call_llm()` は開発者が実装する関数。これを以下のように置き換えても Bolt アプリとしては動作する：

```python
# LLM を使わない例（プログラムによる応答）
returned_message = f"受け付けました: {user_message}"
say(text=returned_message)
```

**`say()` の呼び出しは必須**。これが「出力」の担当部分。

---

### 7. MCP Server との役割比較

ソース: `docs/ai/slack-mcp-server.md` 25-35行目

```
APIs: Software-to-software communication; deterministic integrations
     Client (developer) must read documentation and write code to invoke specific endpoints 
     and process the output

MCP: AI model-to-data communication and agent interactions
     Client (agent) can ask the server, "What tools can you offer?" at runtime. 
     The server responds with machine-readable tool descriptions...
```

| 役割 | MCP Server | カスタムエージェント（Bolt アプリ） |
|------|-----------|----------------------------------|
| 相手 | LLM（AI モデル） | ユーザー（人間） |
| 役割 | データ・ツールの提供 | ユーザーとの対話・**完全な回答の送信** |
| 回答生成責任 | **なし**（LLM が回答を生成） | **あり**（アプリが `say()` で回答を送信） |
| LLM の位置 | MCP Server を呼び出す主体 | カスタムエージェントが任意で利用するツール |

**カスタムエージェントと MCP Server は役割が根本的に異なる**：
- MCP Server は LLM のツール（データ提供）
- カスタムエージェントはユーザーと直接やり取りし、完全な回答を送信する責任を持つ

---

## 結論

### Q1: LLM を使わなくても良いのか？

**技術的には YES — LLM は必須ではない。**

- Slack プラットフォームは LLM の使用を強制しない
- `say(text=...)` に渡すテキストはどんな方法で生成しても良い（LLM でも、プログラムで固定テキストを返しても）
- ドキュメントも「LLM prompt **or your app logic**」と二択で記述（87行目）

ただし概念的には：
- LLM なし（プログラム固定応答）= Slack の定義では「Bot」
- LLM あり（推論・ツール使用）= Slack の定義では「Agent」

---

### Q2: カスタムエージェントは「情報提供まで」でよいのか、「回答の完全作成・送信」まで必要なのか？

**「回答の完全作成・送信」までが必須責任。**

| アーキテクチャ要素 | 担当 |
|------------------|------|
| ユーザーメッセージの受信 | Slack プラットフォーム → カスタムエージェントにイベント送信 |
| 処理・推論 | **カスタムエージェントが担当**（LLM 使用は任意） |
| 外部データ取得（ツール呼び出し） | **カスタムエージェントが担当**（任意） |
| **完全な回答テキストの生成** | **カスタムエージェントが担当（必須）** |
| **Slack への回答送信（`say()`）** | **カスタムエージェントが担当（必須）** |

MCP Server は「LLM にデータを渡すまで」が役割であり、回答生成責任はない。カスタムエージェントはそれとは異なり、**ユーザーへの完全な回答**を送信する責任を持つ。

---

### Q3: では「コンテキストを Slack AI に渡して回答を作らせる」という構造はないのか？

**ない（ドキュメント上に存在しない）。**

Enterprise Search の「AI answers」（検索結果ページ）は Slack が持つ AI が生成するが、この機能を外部の Slack アプリから呼び出す API はドキュメントに記述がない。カスタムエージェントはあくまでも自前で回答を生成・送信する必要がある。

---

### まとめ図

```
【MCP Server の位置づけ】
ユーザー → LLM（Claude/OpenAI等）→ MCP Server（データ提供）→ LLM（回答生成）→ ユーザー
                ↑ MCP Server は LLM のツールの一つ。ユーザーと直接やり取りしない。

【カスタムエージェントの位置づけ】  
ユーザー → カスタムエージェント（Bolt アプリ）→ [任意: 外部API / LLM / プログラム処理]
                                              → 完全な回答を生成 → say() → ユーザー
           ↑ カスタムエージェントはユーザーと直接やり取りし、完全な回答を送信する責任を持つ。
```

---

## 問題・疑問点

1. LLM を全く使わない場合、Slack の「Agents & AI Apps」機能を有効化する意味はあるか（スプリットビューへの登場と `assistant:write` スコープのためならあり得る）
2. 将来的に Slack が「コンテキストを受け取ってネイティブ AI が回答を生成する」API を公開する可能性は排除できない（現時点ではない）
