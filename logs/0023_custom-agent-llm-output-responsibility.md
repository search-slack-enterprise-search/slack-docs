# 0023: カスタムエージェントで出力内容（Block等）は自前で組み立てる必要があるか — 調査ログ

## 調査アプローチ

### 前提・背景

タスク 0021 の調査で「Slack 自体は LLM を提供しない、開発者が LLM を用意する必要がある」という結論が得られた。本タスクは、その更問いとして以下を調査する：

- カスタムエージェントでの出力（レスポンステキスト・Block Kit等）は全て開発者が組み立てる必要があるのか？
- MCP のように「Slack AI に回答を作成させるためのコンテキストを渡す」形はないのか？

### 調査手順

1. Bolt Python / JavaScript の Assistant class ドキュメントを精読
2. Bolt Python / JavaScript の adding-agent-features ドキュメントを精読
3. Markdown Block の仕様を確認
4. メッセージ送信のドキュメント（message-sending.md）を確認
5. Slack MCP サーバーの実装例（developing.md）と比較

---

## 調査ファイル一覧

- `docs/tools/bolt-python/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-js/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-python/concepts/adding-agent-features.md`
- `docs/tools/bolt-python/concepts/message-sending.md`
- `docs/reference/block-kit/blocks/markdown-block.md`
- `docs/ai/developing-agents.md`（前タスクで調査済み・参照）
- `docs/ai/slack-mcp-server/developing.md`（前タスクで調査済み・参照）

---

## 調査結果

### 1. Slack は LLM を提供しない — 開発者が LLM を選ぶ

ソース: `docs/tools/bolt-js/concepts/using-the-assistant-class.md` 90行目

```
The following example uses OpenAI but you can substitute it with the LLM provider of your choice.
```

Bolt の公式ドキュメントでも「OpenAI を使っているが、お好みの LLM プロバイダに置き換え可能」と明記されている。

タスク 0021 で確認した `developing-agents.md` のフル実装例も `gpt-4.1-mini`（OpenAI）を使用。Slack が LLM を提供するのではなく、開発者が Claude / OpenAI / Hugging Face / Pydantic AI 等の LLM プロバイダを自由に選択する。

---

### 2. レスポンステキストは LLM が生成する（開発者はテキストを組み立てない）

ソース: `docs/tools/bolt-js/concepts/using-the-assistant-class.md`

JS の基本的な実装例：

```javascript
// Send message history and newest question to LLM
const llmResponse = await openai.responses.create({
    model: 'gpt-4o-mini',
    input: `System: ${DEFAULT_SYSTEM_CONTENT}\n\n${parsedThreadHistory}\nUser: ${message.text}`
});
// Provide a response to the user
await say({ markdown_text: llmResponse.choices[0].message.content });
```

**ポイント**:
- 開発者はユーザーメッセージとスレッド履歴を LLM に渡す
- LLM がテキスト回答を生成する
- 開発者はその出力を `say()` に渡すだけ

ソース: `docs/tools/bolt-python/concepts/using-the-assistant-class.md`

Python の基本的な実装例（擬似コード）：
```python
returned_message = call_llm(messages_in_thread)  # LLMがテキストを生成
say(text=returned_message)  # Slackに送信
```

`call_llm()` は開発者が実装するカスタム関数。LLM API を呼び出してテキストレスポンスを取得する。

---

### 3. Markdown Block — LLM の markdown 出力をそのまま送れる仕組み

ソース: `docs/reference/block-kit/blocks/markdown-block.md`

**Usage info セクション（194行目）**の記述：
> "This block can be used with apps that use platform AI features when you expect a markdown response from an LLM that can get lost in translation rendering in Slack. Providing it in a markdown block leaves the translating to Slack to ensure your message appears as intended. Note that passing a single block may result in multiple blocks after translation."

**Markdown Block の仕様**:
```json
{
  "blocks": [
    {
      "type": "markdown",
      "text": "**Lots of information here!!**"
    }
  ]
}
```

`text` フィールドに**標準的な CommonMark の markdown**を渡すと、Slack が自動的に Slack の表示形式に変換してくれる。

**対応している markdown 形式**（ドキュメントより）:
- `**bold**`, `*italic*`
- `# Header`, `## Header 2`
- コードブロック（`` ``` ``）・インラインコード（`` ` ``）
- リスト（`-` や `1.`）
- テーブル（`| Col | Col |`）
- 引用（`>`）
- 水平線（`---`）
- タスクリスト（`- [ ]`）
- リンク（`[text](url)`）

---

### 4. `markdown_text` パラメータ — say_stream() との組み合わせ

ソース: `docs/tools/bolt-python/concepts/message-sending.md`

`say_stream()` の `append()` と `stop()` に `markdown_text` パラメータがある：

```python
stream = say_stream()
stream.append(markdown_text="Let me consult my *vast knowledge database*...")
stream.stop()
```

これにより、LLM がストリーム出力するテキスト（標準 markdown）を Slack に直接送信できる。

ソース: `docs/tools/bolt-python/concepts/adding-agent-features.md`（実際のエージェント実装）

```python
# Stream response in thread with feedback buttons
streamer = say_stream()
streamer.append(markdown_text=result.output)  # LLMの出力をそのまま
feedback_blocks = build_feedback_blocks()
streamer.stop(blocks=feedback_blocks)  # フィードバックボタンのみ Block Kit で組み立て
```

ここで `result.output` は LLM が生成したテキスト（markdown）。
`feedback_blocks` だけが開発者が Block Kit で組み立てる部分。

---

### 5. Block Kit の使い方 — 必須ではなく、インタラクティブ要素に限定

ソース: `docs/tools/bolt-python/concepts/using-the-assistant-class.md`（「Sending Block Kit alongside messages」セクション）

> "For **advanced use cases**, Block Kit buttons may be used instead of suggested prompts, as well as the sending of messages with structured metadata to trigger subsequent interactions with the user."

ドキュメントでは Block Kit の使用を「**高度なユースケース**」として位置づけており、必須ではない。

Block Kit が必要なシーン（ドキュメントの例）:
- インタラクティブなボタン（「チャンネルを要約する」ボタンなど）
- モーダルを開くトリガーボタン
- フィードバックボタン（サムズアップ/ダウン）
- 承認・拒否ボタン
- ドロップダウンや選択肢

**シンプルなテキスト回答には Block Kit 不要**:
- LLM の出力 → `say(text=...)` または `say({ markdown_text: ... })`

---

### 6. MCP との比較 — LLM が回答を作る点は同じ

ソース: `docs/ai/slack-mcp-server/developing.md`

Slack MCP Server を使った OpenAI 呼び出し例：

```javascript
const llmResponse = await openai.responses.create({
    model: 'gpt-4o-mini',
    input: `System: ${DEFAULT_SYSTEM_CONTENT}\n\n${parsedThreadHistory}\nUser: ${message.text}`,
    tools: [
        {
            type: 'mcp',
            server_label: 'slack',
            server_url: 'https://mcp.slack.com/mcp',
            headers: { Authorization: `Bearer ${context.userToken}` },
            require_approval: 'never',
        },
    ],
    stream: true,
});
```

MCP の場合でも：
1. 開発者が LLM API を呼び出す
2. LLM がツール（Slack MCP Server）を呼び出して Slack データを取得
3. LLM がテキスト回答を生成
4. 開発者がその回答を Slack に送信

**MCP ≠ 「Slack AI に回答を作らせる」**。MCP はあくまでも「LLM が使えるツール（データソース）」であり、回答を生成するのは開発者が選んだ LLM（OpenAI / Claude 等）。

---

### 7. developing-agents.md の Full example で確認した出力組み立て

ソース: `docs/ai/developing-agents.md`（Full example）

複雑な例（JSON 構造化出力 → Block Kit マッピング）：

```javascript
// LLM に構造化出力を要求
const completion = await llm.responses.create({
    model: 'gpt-4.1-mini',
    input: `Goal: ${state.goal}\n\nRelevant context:\n${contextBlock}\n\nRespond with JSON only: { "summary": "...", "findings": [...], "decisions": [...], "next_actions": [...] }`
});
const parsed = JSON.parse(completion.output_text);

// LLMの出力を Block Kit にマッピング
const listSection = (label, items) => ({
    type: 'section',
    text: { type: 'mrkdwn', text: `*${label}*\n${items.map((i) => `• ${i}`).join('\n')}` }
});
const blocks = [{ type: 'header', text: { type: 'plain_text', text: parsed.summary } }];
if (parsed.findings?.length > 0) blocks.push(listSection('Findings', parsed.findings));
if (parsed.decisions?.length > 0) blocks.push(listSection('Decisions', parsed.decisions));
// ...
await client.chat.stopStream({ channel, ts: stream.ts, text: parsed.summary, blocks });
```

この「複雑な例」では：
- LLM に JSON 形式で出力させる
- 開発者がその JSON を Block Kit にマッピングする

ただし、これは「高度なケース」。シンプルなテキスト応答では不要。

---

## 結論

### Q: カスタムツールを使用する場合は出力内容を自前で組み立てる必要があるのか？

**テキスト部分（回答の本文）: LLM が生成するので開発者の組み立ては不要**

| 役割 | 担当 |
|------|------|
| 回答テキストの生成 | LLM（Claude / OpenAI / 選んだ LLM プロバイダ） |
| テキストの Slack 送信 | 開発者（`say(markdown_text=...)` に LLM 出力を渡す） |
| markdown の Slack 変換 | Slack（Markdown Block / `markdown_text` パラメータを使えば Slack が変換） |
| インタラクティブ要素（ボタン等） | 開発者（Block Kit で組み立て） — オプション |

### ポイントのまとめ

1. **Slack は LLM を提供しない** → 開発者が Claude / OpenAI 等を選ぶ
2. **LLM が回答テキストを生成する** → 開発者はテキストを「組み立て」る必要はない
3. **`markdown_text` / Markdown Block でそのまま送れる** → LLM の markdown 出力を Slack が自動変換
4. **Block Kit は必須ではない** → フィードバックボタン・承認ボタン等のインタラクティブ要素に使う場合のみ

### MCP との比較

ユーザーが「MCP のように Slack AI に回答を作らせる」と表現していた点について：

**MCP も「Slack AI が回答を作る」のではなく「開発者が選んだ LLM（OpenAI/Claude）が回答を作る」**。  
MCP Server はツールの一種（Slack データへのアクセス手段）であり、回答生成は LLM が担う。  
カスタムツールと MCP の違いは「何のデータにアクセスするか」だけで、LLM が回答を生成するという点は同じ。

**「Slack AI（ネイティブの AI 機能）に回答を作らせる API」はドキュメントに存在しない。**

---

## 問題・疑問点

1. Slack のネイティブ AI（Enterprise Grid の「Slack AI」機能）が持つ LLM を外部の Slack アプリから呼び出せるような公式 API は、調査したドキュメントには見当たらない
2. Enterprise Search の「AI answers」（検索結果ページの AI 回答）は Slack の AI が生成するが、この機能を外部アプリから呼び出す手段はドキュメントに記述がない
3. `admin.conversations.bulkSetExcludeFromSlackAi` 等の「Slack AI」関連 API は管理機能であり、AI 生成の呼び出しとは別物
