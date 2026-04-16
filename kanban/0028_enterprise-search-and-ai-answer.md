# enterprise-search-and-ai-answer
## 知りたいこと
[Slack エンタープライズ検索を設定および管理する | Slack](https://slack.com/intl/ja-jp/help/articles/39044407124755-Slack-%E3%82%A8%E3%83%B3%E3%82%BF%E3%83%BC%E3%83%97%E3%83%A9%E3%82%A4%E3%82%BA%E6%A4%9C%E7%B4%A2%E3%82%92%E8%A8%AD%E5%AE%9A%E3%81%8A%E3%82%88%E3%81%B3%E7%AE%A1%E7%90%86%E3%81%99%E3%82%8B)

こちらのページを読む限り、Enterprise SearchにおいてAIによる回答も使えるように見える。
本当にSlackbotの回答として使えないのか。


## 目的
Slackbotの回答としてEnterprise Searchを使えないのか知りたい。

## 調査サマリー

### Enterprise Search の AI Answers はSlack標準機能として存在する

Enterprise Search の search_results で `description` と `content` フィールドを提供すると、Slackが**ネイティブに AI Answer を自動生成**して検索UIに表示する。これは「Slackbot」が返答するのではなく、Slackの検索UIの中でAIが回答する仕組み。

- `description`: AI Answerの元情報として LLM に直接入力される
- `content`: オプション。より包括的なAI Answer生成に使われる
- キャッシュ期間: 検索結果と同じ3分間

**条件**: Slack AI Search（Business+ または Enterprise+の有料機能）が有効なワークスペースが必要。`assistant.search.info` メソッドで `is_ai_search_enabled: true` を確認して判定可能。

### カスタムAgentとしてSlackデータを検索して回答することも可能

カスタムAgent（Agents & AI Apps）が `assistant.search.context` API を使ってSlack内のメッセージ・ファイル・チャンネルを検索し、その結果をコンテキストとして自前LLMで回答生成することができる。

- 自然言語の質問形式にするとセマンティックサーチが発動する
- bot tokenを使う場合は `action_token`（イベントペイロード内）が必要
- レガシーの `search.messages` は使わないこと

**注意**: これは Slack内データ（過去メッセージ等）の検索。Enterprise Searchで登録した外部データソース（Wiki等のカスタムコネクター）を Agent が直接取得するAPIは明示されていない。

### 整理: 3つのアプローチ

| アプローチ | 概要 | 条件 |
|---|---|---|
| Enterprise Search + AI Answers（ネイティブ） | Slackの検索UIでAIが自動回答。アプリはdescription/contentを充実させるだけ | Slack AI Search（有料）が必要 |
| Custom Agent + assistant.search.context | Agentがアクティブに検索して自前LLMで回答 | Agents & AI Apps 有効 |
| Slack MCP Server 経由 | Claude.ai等の外部AIがSlackデータに接続 | MCP対応の外部AIが必要 |

## 完了サマリー

- **調査日**: 2026-04-16
- **ログ**: `logs/0028_enterprise-search-and-ai-answer.md`
- **結論**:
  - Enterprise Search で AI Answer を使う方法は存在し、`description` と `content` フィールドを充実させればSlackがネイティブにAI回答を生成する（ただしSlack AI Search有料機能が必要）
  - カスタムBotがEnterprise SearchのAI Answers機能を「乗っ取って」返答することはできない仕組み
  - Custom Agentとして `assistant.search.context` でSlack内データを検索して回答生成する方法は別途存在する
  - Enterprise Searchの外部データソース（カスタムコネクター）をAgentが直接検索するAPIは、ドキュメント内に明示的な記述なし
