# 0020: Enterprise Search と Slack AI (Slackbot) 連携 — 調査ログ

## 調査アプローチ

### 検索キーワード・調査経緯
1. `docs/enterprise-search/` 配下のドキュメント全体を確認
2. `docs/ai/` 配下のドキュメントを確認（agents.md, developing-agents.md, agent-context-management.md, agent-entry-and-interaction.md）
3. `assistant.search.context`、`action_token`、`user_context` のキーワードでリポジトリ全体を検索
4. `slackbot`, `slack ai`, `AI answer`, `AI search` のキーワードで検索
5. `docs/apis/web-api/real-time-search-api.md`, `docs/reference/methods/assistant.search.context.md` を詳読
6. `docs/messaging/work-objects-overview.md`, `docs/reference/events/function_executed.md` を確認
7. `docs/enterprise-search/enterprise-search-access-control.md` を確認
8. `docs/reference/audit-logs-api/methods-actions-reference.md` の "AI in Slack" セクションを確認
9. `docs/tools/deno-slack-sdk/reference/slack-types.md` の user_context セクションを確認

---

## 調査ファイル一覧

- `docs/enterprise-search/index.md`
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/enterprise-search-access-control.md`
- `docs/enterprise-search/connection-reporting.md`
- `docs/ai/index.md`
- `docs/ai/agents.md`
- `docs/ai/developing-agents.md`
- `docs/ai/agent-context-management.md`
- `docs/ai/agent-entry-and-interaction.md`
- `docs/apis/web-api/real-time-search-api.md`
- `docs/reference/methods/assistant.search.context.md`
- `docs/reference/events/function_executed.md`
- `docs/reference/events/entity_details_requested.md`
- `docs/messaging/work-objects-overview.md`
- `docs/reference/audit-logs-api/methods-actions-reference.md`（AI in Slack セクション）
- `docs/tools/deno-slack-sdk/reference/slack-types.md`（user_context セクション）
- `docs/other-ai-integrations.md`
- `docs/changelog/2026/02/17/slack-mcp.md`

---

## 調査結果

### 1. Enterprise Search の仕組み（おさらい）

ソース: `docs/enterprise-search/developing-apps-with-search-features.md`

Enterprise Search は以下のフローで動作する:

1. ユーザーが Slack の**検索UI**でクエリを入力
2. Slack が Enterprise Search アプリに `function_executed` イベントを送信
3. アプリが `search_function_callback_id` で指定した関数を実行し、`search_results` を返す
4. Slack が検索結果を表示する

サーチ関数のトリガー条件:
> "The search function specified by the `search_function_callback_id` is triggered when users perform searches or modify search filters."

**重要なポイント**: Enterprise Search は Slack の検索UIを通じてのみトリガーされる。

---

### 2. Slack AI と Enterprise Search の接続点

ソース: `docs/enterprise-search/developing-apps-with-search-features.md`

Enterprise Search のサーチ関数の output parameters のうち、`description` フィールドの説明:
> "Description of the search results. A cropped version of this description is used to help users identify the search results. **In the case of AI answers, the entire description will be fed to the LLM to provide helpful information in natural language.**"

`content` フィールドの説明:
> "Detailed content of search results. **If provided, AI answers will use alongside `title` and `description` to generate more comprehensive search answers.**"

検索結果のキャッシュに関して:
> "Slack caches successful search results for each user and query, for up to three minutes. **Since search AI answers are generated from the search results, AI answers are also cached for those three minutes.**"

**解釈**: ここで言う "AI answers" とは、Slack の検索UI（検索バー）で検索した際に表示される AI 生成の回答のこと。Slack が Enterprise Search の結果（description, content フィールド）を LLM へのインプットとして使い、自然言語の回答を生成する。

---

### 3. Work Objects と AI answers citations の関係

ソース: `docs/messaging/work-objects-overview.md` 89行目

> "To support Work Objects for your app's Enterprise Search results, traditional search results, **and AI answers citations**, your app must subscribe to the `entity_details_requested` event."

これも「検索UIの AI answers」文脈での話であり、Enterprise Search の結果が AI answers の引用として使われることを示している。

---

### 4. Slackbot（AI assistant panel）の仕組み

ソース: `docs/ai/developing-agents.md`, `docs/ai/agent-entry-and-interaction.md`, `docs/ai/agent-context-management.md`

Slack の AI assistant（スプリットビュー・コンテナで動作する AI）は以下のイベントで動作する:
- `assistant_thread_started`: ユーザーがコンテナを開いたとき
- `assistant_thread_context_changed`: ユーザーが別チャンネルに移動したとき
- `message.im`: ユーザーがメッセージを送ったとき

AI assistant が Slack データを検索する方法:
```javascript
const result = await client.assistant.search.context({
  query: userQuery,
  action_token: event.action_token,
  content_types: ['messages', 'files', 'channels'],
  channel_types: ['public_channel', 'private_channel'],
  include_context_messages: true,
  limit: 20
});
```

ソース: `docs/ai/agent-context-management.md` および `docs/ai/developing-agents.md`

これは **Real-time Search API (`assistant.search.context`)** を使った Slack データ（メッセージ・ファイル・チャンネル）の検索であり、**Enterprise Search アプリ（外部データソース）を呼び出すものではない**。

---

### 5. Real-time Search API vs Enterprise Search の違い

| 項目 | Real-time Search API | Enterprise Search |
|------|---------------------|-------------------|
| API メソッド | `assistant.search.context` | なし（`function_executed` イベント受信） |
| 検索対象 | Slack 内のメッセージ・ファイル・チャンネル・ユーザー | 外部データソース（Wiki・独自システムなど） |
| 誰が使うか | サードパーティ AI エージェント | Slack の検索UI が Enterprise Search アプリを呼び出す |
| トリガー | AI エージェントが任意に呼び出す | Slack の検索UIでユーザーが検索したとき自動的に |
| user_context | action_token（メッセージイベントから取得） | `user_context` 型フィールドに自動セット |

---

### 6. Slackbot が Enterprise Search をトリガーするか

ドキュメント全体を調査した結果、**Slackbot（AI assistant panel）が Enterprise Search アプリを自動的に呼び出すという記述は見当たらなかった**。

ドキュメント上で確認できること:
- Enterprise Search は「ユーザーが検索UIで検索したとき」にトリガーされる
- AI assistant（Slackbot相当）は `assistant.search.context` で Slack データを検索する
- 両者は別々の仕組みであり、連携の自動化は文書化されていない

---

### 7. Slackbot がユーザーの代わりに行動する場合の audit log

ソース: `docs/reference/audit-logs-api/methods-actions-reference.md`

```
action: canvas_edited
...
acting_agent: Slackbot
agent_message:
  channel_id: D0123ABC456
  message_ts: "1772835937.732289"
  thread_ts: "1772828335.812309"
```

Slackbot がユーザーの代わりに `file_opened` や `canvas_edited` などの操作を実行できることは確認されているが、これは Enterprise Search の呼び出しではなく、Slack ネイティブの操作についての記述。

---

### 8. user_context の詳細

ソース: `docs/tools/deno-slack-sdk/reference/slack-types.md` （user_context セクション）

```
Property | Type | Description
id       | string | The user_id of the person to which the user_context belongs.
secret   | string | A hash used internally by Slack to validate the authenticity of the id in the user_context.
```

Enterprise Search の search 関数において:
> "Any additional input parameter with type `slack#/types/user_context`, regardless of its name, will be set to the `user_context` value of the **user executing the search**."

ソース: `docs/enterprise-search/developing-apps-with-search-features.md` 79行目

**解釈**: user_context には「検索を実行したユーザー」の user_id が自動的にセットされる。これは Slack の検索UI からユーザーが検索したとき、Slack が自動的に設定するもの。Slackbot が代わりに検索した場合に何が入るかはドキュメントに記述なし。

---

### 9. Enterprise Search のユーザー向けアクセス制御

ソース: `docs/enterprise-search/enterprise-search-access-control.md`

- Enterprise Search アプリはデフォルトでエンドユーザーには利用不可
- オーグ管理者がエンドユーザー向けに有効化する必要がある
- 有効化後、ユーザーはワークスペースメンバーとして検索時に Enterprise Search 結果を取得できる
- エンドユーザーは個別にアプリを無効にすることも可能

---

## 結論

### Q1: SlackbotからEnterprise Searchを動かすことができるのか？

**現時点のドキュメントでは NO（自動的には不可）**。

Enterprise Search は Slack の検索UI（検索バー）でユーザーが検索したときのみトリガーされる。Slackbot（AI assistant panel）が Enterprise Search アプリを自動的に呼び出す仕組みはドキュメントに記述がない。

ただし、間接的なシナリオは存在する:
- ユーザーが Slack の検索UIで検索 → Enterprise Search が呼ばれる → Slack AI が AI answers を生成（検索結果UIで表示）
- この "AI answers" は Slackbot のような AI assistant パネルとは別物（検索結果ページの AI 回答機能）

### Q2: 動かせるならどういう挙動になるのか？

**検索UIを経由した場合（間接的）**:
- ユーザーが Slack 検索UIで検索 → Enterprise Search 関数が `function_executed` イベントで呼ばれる
- Enterprise Search アプリは `search_results` を返す
- Slack AI は `description`・`content` フィールドを LLM に渡して AI answers を生成
- 検索結果とAI answersがユーザーに表示される

**Slackbot（AI assistant panel）直接:**
- Slackbot は `assistant.search.context`（Real-time Search API）で Slack 内データのみを検索
- Enterprise Search（外部データ）は呼ばれない

### Q3: user_contextはSlackbotに質問した人になるか？

**Slack 検索UIの場合（AI answers）**: 検索を実行したユーザーの user_id が user_context に自動的にセットされる。これは Slack の仕様による自動設定。

**Slackbot（AI assistant panel）の場合**: Enterprise Search が呼ばれないため、user_context の問題は発生しない。

---

## 補足: 将来的な統合の可能性

ドキュメントには明記されていないが、以下の方法でカスタム統合は可能と考えられる:

1. Slackbot（カスタムエージェント）がユーザーの質問を受け取る
2. 独自の外部データ検索（Enterprise Search アプリに直接 API 呼び出しではなく、アプリのバックエンドに直接アクセス）を実行
3. 結果を Slackbot のレスポンスに含める

これは Enterprise Search の仕組みとは別の実装になるが、外部データをSlackbotのレスポンスに組み込む標準的な方法。

---

## 問題・疑問点

1. Slack AI（ネイティブの AI assistant）が Enterprise Search 結果を利用するかどうか、公式ドキュメントには明示的な記述がない（検索UIの AI answers は利用するが、AI assistant panel については未確認）
2. 将来的な機能追加で Slackbot と Enterprise Search が統合される可能性は排除できない
3. `admin.conversations.bulkSetExcludeFromSlackAi` という API が存在することから、「Slack AI」が特定のチャンネルの内容を検索・参照する仕組みはあるが、Enterprise Search との関係は不明
