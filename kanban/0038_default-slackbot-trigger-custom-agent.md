# Slack AI標準SlackbotからカスタムエージェントをSlackから起動する方法

## 知りたいこと

slack aiにおいて、slackが標準で持っているSlackbotからカスタムエージェントを起動したい

## 目的

uiを一つにできるので利便性が高い

## 調査サマリー

### 結論: Slack標準Slackbotからカスタムエージェントを起動することは不可能

「Slack標準Slackbot（USLACKBOT）」はSlackの内部システムエンティティ（`is_bot: false`）であり、開発者が拡張・フック・エントリーポイントとして利用する方法はSlack APIに存在しない。

### 標準Slackbotが使えない3つの理由

1. **技術的制限**: 標準Slackbotは `is_bot: false` のシステムエンティティ。開発者はその DM チャンネルのイベントを受信できない
2. **ガイドライン禁止**: Slack Marketplace ガイドラインが「🚫 DON'T send notifications to a user's Slackbot channel」と明示
3. **API不在**: 標準SlackbotへのユーザーDMをカスタムアプリにルーティングするAPIが存在しない

### Slack AI（有料）との関係

Slack AI の有料プロダクト機能（チャンネルサマリー等）も Slack のプロダクト機能であり、開発者がそのエントリーポイントをカスタマイズ・拡張する方法は提供されていない。

### UIを一カ所にまとめる代替手段（タスク0035と同一結論）

自作のSlackアプリに bot + agent 機能を両方統合する（Caseyパターン）:
- `app.use(assistant)` を追加するだけで既存 bot ハンドラーに影響なし
- @メンション・DM・Split Pane・Chat/History タブを1つのアプリで処理可能
- 標準SlackbotそのものはUIに使えないが、自作アプリのDMが機能的に同等の役割を果たす

### agent-to-agent handoffs

`docs/ai/agent-design.md`: "still being defined and under exploration" — 将来的に改善される可能性あり

## 完了サマリー

2026-04-16 調査完了。Slack標準Slackbot（USLACKBOT）はシステムエンティティであり、開発者が起動ポイントとして利用するAPIは存在しない。UIを一カ所にまとめる目的には、自作アプリに `app.use(assistant)` で bot + agent 機能を統合する方法（タスク0035・Caseyパターン）が唯一の正解。詳細は `logs/0038_default-slackbot-trigger-custom-agent.md` 参照。
