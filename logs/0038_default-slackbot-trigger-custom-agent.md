# 0038: Slack AI標準SlackbotからカスタムエージェントをSlackから起動する方法

## 調査日時

2026-04-16

## 調査ファイル一覧

- `docs/ai/agent-entry-and-interaction.md`（実パス: `/home/yuta/spaces/01_work/slack_enterprise_search/02_scripts/slack_docs_archiver/docs/2026_04_15-20_11_57/ai/agent-entry-and-interaction.md`）
- `docs/ai/agents.md`
- `docs/ai/agent-design.md`
- `docs/ai/developing-agents.md`
- `docs/ai/index.md`
- `docs/other-ai-integrations.md`
- `docs/surfaces/app-design.md`
- `docs/reference/methods/chat.postMessage.md`（Slackbot DM への postMessage の確認）
- `logs/0035_slackbot-trigger-custom-agent.md`（先行タスク参照）
- `logs/0034_slackbot-custom-agent-invocation.md`（先行タスク参照）
- `logs/0021_slack-ai-slackbot-external-data-access.md`（先行タスク参照）

---

## 調査アプローチ

### タスク0035との違いを明確化

タスク0035は「Slackbotからカスタムエージェントを起動する方法」という広い問いに答えたが、タスク0038は「**Slack が標準で持っているSlackbot**」に限定した問い。

ユーザーの意図は以下のように解釈した：
- 「Slack標準Slackbot」 = Slack がすべてのワークスペースにデフォルトで提供している組み込みの Slackbot（ID: `USLACKBOT`）。ユーザーがDMを送れる、Slackの内部システムbot。
- 「Slack AI において」 = Slack AI という文脈・製品において（つまり、有料Slack AIに搭載されているAI機能の文脈で）
- 「カスタムエージェントを起動したい」 = 開発者が作成したカスタムエージェント（Agents & AI Apps）を起動させたい
- 「UIを一つにできるので利便性が高い」 = 既存の標準Slackbotと自作カスタムエージェントを同一のエントリーポイントから起動したい

### 調査の焦点

1. Slack標準Slackbot（USLACKBOT）の技術的な性質を確認
2. カスタムエージェントのエントリーポイントと標準Slackbotの関係を確認
3. Slack AI（有料プロダクト）の組み込みAI機能とカスタムエージェントの関係を確認
4. 「UIを一つにする」目的に対する代替アプローチを確認

---

## 調査結果

### 1. Slack標準Slackbot（USLACKBOT）の技術的性質

#### 1.1 標準SlackbotはSlackの内部システムエンティティ

`docs/apis/web-api/pagination.md` の `users.list` レスポンス例より:

```json
{
  "id": "USLACKBOT",
  "team_id": "T0123ABC456",
  "name": "slackbot",
  "deleted": false,
  "color": "757575",
  "real_name": "slackbot",
  ...
  "is_admin": false,
  "is_owner": false,
  "is_bot": false,   ← 重要: botフラグはfalse
  ...
}
```

**重要な発見**: Slack標準Slackbot は `is_bot: false` である。これは Slack の内部システムユーザーであり、開発者が作成するBot app（`is_bot: true`）とは根本的に異なる。

#### 1.2 開発者は標準Slackbotを拡張できない

`docs/reference/methods/reminders.add.md` より:
> "`cannot_add_slackbot`"
> "Reminders can't be sent to Slackbot."

`docs/slack-marketplace/slack-marketplace-app-guidelines-and-requirements.md` より:
> "🚫 **DON'T** send notifications to a user's Slackbot channel. Use the app home Messages tab instead."

`docs/developer-policy.md` より:
> "Infringing upon any intellectual property rights in your design. You must include, with your submission, a well-designed, high quality, distinctive icon that doesn't **resemble Slackbot or the Slack icon**"

これらから、Slack標準Slackbot はSlackの内部エンティティとして保護されており、開発者が統合・拡張することは**不可**であることが明確。

#### 1.3 標準Slackbotへのメッセージはカスタムエージェントで受信できない

`docs/reference/methods/chat.postMessage.md` より:
> "If the `channel` parameter is set to a User ID (beginning with `U`), the message will appear in that user's direct message channel with Slackbot."

これは「アプリが特定ユーザーのSlackbot DMチャンネルに投稿できる」という意味であり、**標準SlackbotへのユーザーDMをカスタムアプリが受信できる**という意味ではない。

Slackのイベントサブスクリプションシステムでは、カスタムアプリは**自分のbot_user**が存在するチャンネル（自分のDM、自分がメンバーのチャンネル等）のイベントのみ受信可能。標準Slackbotへのメッセージは受信不可。

---

### 2. Slack AI（有料プロダクト）の組み込みAI機能とカスタムエージェントの関係

#### 2.1 「Slack AI」製品と開発者向け「Agents & AI Apps」は別物

`docs/ai/developing-agents.md` 冒頭:
> "Developing and using some AI features require a **paid plan**, despite being visible in the app settings on any plan."
> "Don't have a paid plan? Join the **Developer Program** and provision a fully-featured sandbox for free."

`docs/ai/index.md` より（AI in Slack の概要）:
> "Slack provides a set of tools, APIs, and platform features for bringing AI-powered experiences into the flow of work."

概要として:
- **Slack AI（有料プロダクト）**: チャンネルサマリー・スレッドサマリー・AI検索など、Slack が提供する組み込みAI機能。ユーザーが利用するもので、開発者がそのエントリーポイントをカスタマイズする仕組みはない。
- **Agents & AI Apps（開発者向け）**: 開発者が自分でSlackアプリを作成し、カスタムエージェントとして動作させる機能。Split Pane（トップバー）・DM・@メンションから起動できる。

#### 2.2 Slack AI（有料）の組み込みアシスタントはカスタム不可

`docs/ai/agents.md` より:
> "Agents are autonomous, goal-oriented AI apps that can reason, use tools, and maintain context across conversations in Slack."

> "Able to use tools: **Agents take actions using tools**; these are functions the agent can invoke to read or write to external systems."

Agents & AI Appsは「開発者が構築するカスタムアプリ」として定義されている。Slack AI 有料プロダクトの組み込みアシスタント（Slack自身のAI）を開発者がカスタマイズ・拡張するAPIは、ドキュメントに記載されていない。

---

### 3. カスタムエージェントのエントリーポイント（再確認）

`docs/ai/agent-entry-and-interaction.md` より（既存ログ0034・0035と同じ内容を直接確認）:

> "Four interaction surfaces act as entry points:
> - App mentions
> - Direct messages
> - Top bar entry point for launching the agent in a split pane
> - Chat and History tabs in the app UI"

> "The latter two entry points require you to enable the **Agents & AI Apps** setting in your app settings to become available in the Slack UI"

**4つのエントリーポイントはすべて、開発者が自分で作成したSlackアプリに対するもの**。標準Slackbotはこの4つに含まれていない。

#### 3.1 DM（Direct Messages）エントリーポイントの詳細

> "Listen for the `message.im` event for when a user messages your agent **outside of the assistant container**. Filter on `channel_type: im` to distinguish from group DMs."

これは「ユーザーが**自分のカスタムエージェントアプリ**にDMを送った場合」のイベント。標準SlackbotへのDMとは別。

---

### 4. 「UIを一つにする」目的の達成方法

#### 4.1 不可能なアプローチ: 標準Slackbotへのフック

技術的な理由から不可能:
- 標準Slackbot（USLACKBOT）は `is_bot: false` のシステムエンティティ
- 開発者がイベントを受信できるのは自分のアプリ（自分のbot_user）に届くイベントのみ
- Slack ドキュメントが「Slackbot DMチャンネルを使わないこと」を明示的にガイドラインで禁止

#### 4.2 可能なアプローチ: 既存SlackbotアプリにAgents & AI Apps機能を統合（0035で確認済み）

`docs/ai/agent-entry-and-interaction.md` と `docs/tools/bolt-js/concepts/using-the-assistant-class.md` から確認（0035ログより）:

```javascript
// 既存Boltアプリに以下を追加するだけ
const assistant = new Assistant({
  threadStarted: async ({ say, setSuggestedPrompts }) => { ... },
  threadContextChanged: async ({ assistantThread }) => { ... },
  userMessage: async ({ message, say, setStatus }) => { ... }
});
app.use(assistant);  // 既存のbot機能（app_mention等）はそのまま動作
```

これにより、1つのSlackアプリが以下の全エントリーポイントを処理:
- チャンネルでの `@メンション`（`app_mention` ハンドラー）
- 通常のDM（`message.im` ハンドラー）
- Split Pane / トップバーからの起動（`Assistant` クラス）
- Chat/History タブ（`Assistant` クラス + DM）

**ユーザー視点では、1つのアプリが「UIの一カ所」として機能する。**

#### 4.3 標準Slackbotとの差異

「標準Slackbotが使えない代わりに、自作アプリを同様の窓口として使う」という発想の転換が必要:

| | Slack標準Slackbot | カスタムエージェントアプリ |
|---|---|---|
| 作成主体 | Slack社 | 開発者 |
| エントリーポイント | ユーザーが直接DMを送信 | DM・@メンション・Split Pane・Chat/Historyタブ |
| カスタマイズ | 不可 | 完全にカスタマイズ可能 |
| 外部API連携 | 不可 | 可能（カスタムツール） |
| インストール | 全ワークスペースに自動で存在 | 管理者によるアプリインストールが必要 |

---

### 5. agent-to-agent handoffs の現状（再確認）

`docs/ai/agent-design.md` より（直接確認）:

> "Some newer interaction patterns like **ambient agents and agent-to-agent handoffs** are still being defined and under exploration. Think of this as a living document."

標準Slackbotを含む「異なるSlackアプリ/エンティティ間での自動エージェント連携」は現時点では未定義・検討中。

---

## 判断・意思決定

### タスク0038がタスク0035と実質的に同じ結論になる理由

ユーザーが「Slack標準Slackbotを使ってカスタムエージェントを起動したい」という問いを持つとき、実際には2つの異なる前提のどちらかを持っている:

**前提A**: 「標準Slackbotは開発者が拡張できる」という誤解  
→ 実際には不可。標準Slackbotはシステムエンティティ。

**前提B**: 「標準Slackbotと同じ場所（ユーザーがDMを送る先）をカスタムエージェントに使えれば便利」という要望  
→ 標準Slackbotそのものは使えないが、**自作アプリへのDM** が機能的に同等の役割を果たす。

タスク0035の「既存SlackbotアプリにAgents & AI Apps機能を追加する」パターンが、前提Bに対する正しい回答。

---

## 問題・疑問点

1. **「Slack AI」と「Agents & AI Apps」のUI上の違い**: Slack AI（有料）の組み込みアシスタントとカスタムエージェントが同じトップバー領域に表示される場合、ユーザーにとってどう見えるかは、ドキュメントに詳細がない。実際のUIを確認する必要がある。

2. **将来的な統合の可能性**: agent-to-agent handoffs が「under exploration」とされているため、将来的に標準Slackbotやその他のエージェントとの連携APIが提供される可能性はある。

3. **Salesforce Agentforce との違い**: `docs/other-ai-integrations.md` では Agentforce（Salesforce プラットフォーム上のエージェント）が紹介されているが、これは Salesforce 環境を前提とした別アプローチ。

---

## まとめ

| 質問 | 回答 |
|------|------|
| **Slack標準Slackbot（USLACKBOT）はカスタムエージェントの起動ポイントとして利用できるか？** | **不可**。標準Slackbotは `is_bot: false` のシステムエンティティ。開発者はイベントを受信できない。Slackのガイドラインもその利用を禁止している |
| **Slack AI（有料）の組み込みアシスタントをカスタムエージェントに置き換え・連携できるか？** | **不可**。Slack AIの組み込み機能はSlackのプロダクト機能であり、開発者がエントリーポイントをカスタマイズする仕組みはない |
| **UIを一カ所にまとめる代替方法は？** | 自作の Slack アプリに bot 機能と Agents & AI Apps 機能を統合する（`app.use(assistant)` を追加）。1つのアプリが @メンション・DM・Split Pane すべてのエントリーポイントを処理できる（タスク0035・Caseyパターン） |
| **agent-to-agent handoffsによる将来的な連携は？** | 現在「still being defined and under exploration」の段階。将来対応の可能性あり |
