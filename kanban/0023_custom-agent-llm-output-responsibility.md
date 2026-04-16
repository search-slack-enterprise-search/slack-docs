# カスタムエージェントで出力内容（Block等）は自前で組み立てる必要があるか

## 知りたいこと

0021番の更問い。Slack自体はLLMを提供しないということは、カスタムツールを使用する場合は出力内容を自前で組み立てる必要があるということか？

## 目的

MCPのようにSlack AIに回答を作成させるためのコンテキストを渡すのではなく、Blockなどもすべて自分で組み立てる必要があるのかを知りたい。

## 調査サマリー

### 結論

**テキスト本文は LLM が生成するので開発者の組み立ては不要。Block Kit もシンプルな応答には不要。**

Slack はネイティブの LLM を提供しないが、開発者が Claude / OpenAI 等の LLM プロバイダを自由に選択して呼び出せる。LLM が生成した markdown テキストは `say(markdown_text=...)` または Markdown Block で Slack に直接渡せば、Slack 側が自動変換してレンダリングする。

### 役割分担

| 役割 | 担当 |
|------|------|
| 回答テキストの生成 | LLM（Claude / OpenAI / 選んだプロバイダ） |
| テキストの Slack 送信 | 開発者（`say(markdown_text=...)` に LLM 出力を渡す） |
| markdown の Slack 変換 | Slack（Markdown Block / `markdown_text` パラメータを使えば Slack が自動変換） |
| インタラクティブ要素（ボタン等） | 開発者（Block Kit）— オプション |

### 主な発見

1. **`markdown_text` パラメータ / Markdown Block**: `say_stream().append(markdown_text=...)` に LLM の出力を渡すだけで、Slack が標準 markdown を自動的に Slack の表示形式に変換する（太字・コードブロック・リスト・テーブル等対応）
2. **Block Kit は必須ではない**: フィードバックボタン・承認ボタン等のインタラクティブ要素を追加したい場合のみ使用。シンプルなテキスト応答には不要
3. **MCP との比較**: MCP も「Slack AI が回答を作る」のではなく「開発者が選んだ LLM が回答を作る」。MCP は LLM が使うツール（Slack データへのアクセス手段）に過ぎない。カスタムツールと構造的に同じ
4. **「Slack AI に回答を作らせる API」はない**: Slack のネイティブ AI 機能（Enterprise Grid の Slack AI）を外部アプリから呼び出す公式 API はドキュメントに存在しない

### 実装例（Python）

```python
# ユーザーメッセージを LLM に渡す（外部ツールの結果も context に含める）
returned_message = call_llm(messages_in_thread)

# LLM の markdown 出力をそのまま Slack に送信（Slack が変換）
streamer = say_stream()
streamer.append(markdown_text=returned_message)  # LLM のテキスト
streamer.stop(blocks=feedback_blocks)  # フィードバックボタン（オプション）
```

### 関連ドキュメント
- `docs/tools/bolt-js/concepts/using-the-assistant-class.md` - `say({ markdown_text: ... })` の使用例
- `docs/tools/bolt-python/concepts/message-sending.md` - `say_stream()` の `markdown_text` パラメータ
- `docs/reference/block-kit/blocks/markdown-block.md` - Markdown Block の仕様（Slack が変換してくれる旨の説明）
- `docs/tools/bolt-python/concepts/adding-agent-features.md` - `say_stream().append(markdown_text=result.output)` のエージェント実装例

## 完了サマリー

**調査完了日**: 2026-04-16

カスタムエージェントでの出力について：テキスト本文は開発者が選んだ LLM（Claude/OpenAI等）が生成するため、開発者がテキストを組み立てる必要はない。LLM の markdown 出力を `say(markdown_text=...)` または Markdown Block で Slack に渡せばよく、Slack が自動変換してレンダリングする。Block Kit はフィードバックボタン等のインタラクティブ要素を追加する場合のみ使用するオプション機能。MCP も「Slack AI が回答を作る」のではなく「開発者が選んだ LLM が回答を作る」という点は同じで、MCP はあくまでも LLM のツール（データ取得手段）に過ぎない。Slack のネイティブ AI を外部から呼び出す公式 API はドキュメントに存在しない。
