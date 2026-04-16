# Enterprise Search と Slack AI (Slackbot) 連携

## 知りたいこと

Enterprise SearchとSlack AI (Slackbot)との連携について。SlackbotからEnterprise Searchを動かすことができるのかをまず知りたい。動かせるのならどういう挙動になるのか、user_contextはちゃんとSlackbotに質問した人になるかなども知りたい。

## 目的

SlackbotからEnterprise Searchを呼び出せるか確認し、その挙動・user_contextの扱いを把握することで、Slackbot経由での外部データ検索の実現可能性を評価する。

## 調査サマリー

### 結論

**Slackbot（AI assistant panel）は Enterprise Search を自動的にトリガーしない。**

Enterprise Search は Slack の**検索UI**（検索バー）でユーザーが検索したときのみ `function_executed` イベントで呼び出される。Slackbot（AI assistant panel）と Enterprise Search は別々の仕組みであり、自動的な連携はドキュメントに記述がない。

### 主要な発見

1. **Enterprise Search のトリガー方法**
   - Slack の検索UI経由のみ（`function_executed` イベント）
   - `search_function_callback_id` で指定した関数が呼び出される
   - Slackbot から直接トリガーする仕組みはない

2. **Slack AI と Enterprise Search の接続点（検索UI文脈）**
   - Slack の検索UIで Enterprise Search の結果が得られると、Slack AI が `description` と `content` フィールドを LLM に渡して "AI answers"（検索結果ページの AI 回答）を生成する
   - "AI answers" = 検索結果ページ上の AI 生成回答（AI assistant panel とは別物）
   - Work Objects の "AI answers citations" にも Enterprise Search 結果が使われる

3. **Slackbot（AI assistant panel）の実際の仕組み**
   - `assistant.search.context`（Real-time Search API）で Slack 内データ（メッセージ・ファイル・チャンネル）のみを検索
   - Enterprise Search（外部データソース）は呼ばれない

4. **user_context の扱い**
   - Enterprise Search の search 関数に `slack#/types/user_context` 型のフィールドを定義すると、**検索を実行したユーザー**の user_id が自動的にセットされる
   - Slack 検索UIから検索した場合は、そのユーザーの user_id が入る
   - Slackbot から Enterprise Search を呼ぶ仕組みが存在しないため、「Slackbotに質問した人の user_context」という状況は現時点では発生しない

### 関連ドキュメント
- `docs/enterprise-search/developing-apps-with-search-features.md` - AI answers と user_context の動作
- `docs/apis/web-api/real-time-search-api.md` - Real-time Search API（Slack 内データ検索）
- `docs/ai/developing-agents.md` - AI エージェントの実装方法
- `docs/messaging/work-objects-overview.md` - AI answers citations の記述

## 完了サマリー

**調査完了日**: 2026-04-16

SlackbotからEnterprise Searchを直接呼び出すことはできない（ドキュメント上の記述なし）。Enterprise Search はSlack検索UIでユーザーが検索したときのみトリガーされ、Slack AIはその結果を使ってAI answersを生成する（検索結果ページ内）。user_contextは検索を実行したユーザーが自動セットされる仕組みのため、Slackbot（AI assistant panel）文脈では関係しない。Slackbot経由での外部データ検索を実現するには、Enterprise Searchとは別に外部APIをカスタム統合する必要がある。
