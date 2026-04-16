# SlackbotからカスタムエージェントをSlackから起動する方法

## 知りたいこと

Slackbotからカスタムエージェントを起動させたいです

## 目的

Slackbotからカスタムエージェントを起動できるようにすることで、UIを一カ所にまとめることができるため

## 調査サマリー

### 結論: 既存SlackbotアプリにAgents & AI Apps機能を追加するのが正解

「Slackbotからカスタムエージェントを起動」の正しい実装は、**同一のSlackアプリにbot機能とagent機能を統合すること**。別々のアプリを連携させる方法はSlack APIとして提供されていない。

### 統合方法

1. App Settings で **「Agents & AI Apps」** を有効化
2. スコープ追加: `assistant:write`, `chat:write`, `im:history`
3. イベント登録: `assistant_thread_started`, `assistant_thread_context_changed`, `message.im`
4. 既存Boltアプリに `app.use(assistant)` を追加するだけ（既存ハンドラーはそのまま動作）

### 1つのアプリで全エントリーポイントを処理する（Caseyパターン）

公式サンプルアプリ「Casey」が同パターンを実装:
- `app_mention` ハンドラー: チャンネルでの @メンション
- `message` ハンドラー: DM・スレッド返信
- `handleAssistantThreadStarted`: Split Pane起動時のサジェストプロンプト設定

### 別アプリへのエージェント呼び出しは非対応

- SlackにBot AがBot Bのエージェントを呼び出すAPIは存在しない
- agent-to-agent handoffsは「still being defined and under exploration」（未定義・検討中）

## 完了サマリー

2026-04-16 調査完了。「UIを一カ所にまとめる」目的を達成するには、既存のSlackbotアプリに `app.use(assistant)` を追加してAgents & AI Apps機能を有効化するのが正解。1つのSlackアプリが `app_mention`・DM・Split Paneの全エントリーポイントを処理できる（Caseyパターン）。別アプリのエージェントをAPIで呼び出す仕組みはない。詳細は `logs/0035_slackbot-trigger-custom-agent.md` 参照。
