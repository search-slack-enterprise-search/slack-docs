# カスタムエージェントとカスタムボットの実装方法とタイムアウト上限

## 知りたいこと

カスタムエージェントとカスタムボットの実装方法とタイムアウトの上限

## 目的

Slackの理解においてLLMで回答を生成するのがエージェント、プログラムで生成するのがボットであるということがわかった。その上でボットとエージェントの実装方法とタイムアウトの上限を知りたい。

## 調査サマリー

### カスタムエージェントの実装方法

1. `api.slack.com/apps` でSlackアプリを作成
2. サイドバーの「**Agents & AI Apps**」機能を有効化 → `assistant:write` スコープが自動付与
3. イベントをサブスクライブ: `assistant_thread_started`, `assistant_thread_context_changed`, `message.im`
4. Bolt for Python/JavaScript の `Assistant` クラスで実装（推奨）
   - `assistant.threads.setSuggestedPrompts`: プロンプト提案
   - `assistant.threads.setStatus`: ロード状態表示
   - `chat.startStream` / `chat.appendStream` / `chat.stopStream`: テキストストリーミング（推奨）
   - `chat.postMessage`: 通常のメッセージ送信
5. 有料プラン必須（Developer Program の無料サンドボックスで代替可）
6. ワークスペースゲストはアクセス不可

### カスタムボット（通常bot user）の実装方法

1. App Management > Bot Users でボットを追加
2. Events API を有効化し、Request URL を設定（HTTPS推奨）
3. `app_mention`, `message.channels` 等をサブスクライブ
4. 3秒以内にHTTP 200を返し、`chat.postMessage` で応答
5. レガシーカスタムボット（`legacy-bot-users.md`）は**2025年3月31日廃止予定**

### エージェントとボットの主な違い

| 項目 | エージェント | ボット |
|------|------------|-------|
| UIの位置 | トップバー（スプリットビュー） | チャンネル内 |
| 機能設定 | 「Agents & AI Apps」有効化 | Bot User 追加 |
| 主要イベント | `assistant_thread_started`, `message.im` | `app_mention`, `message.channels` |
| 推奨レスポンス | ストリーミング API | `chat.postMessage` |
| ローディング表示 | `setStatus`（ネイティブ） | 手動 |

### タイムアウト上限

| 項目 | 上限 |
|------|------|
| Events API HTTP 200応答 | **3秒** |
| インタラクション acknowledgment | **3秒** |
| response_url 有効期間 | **30分**（最大5回） |
| `chat.update` 呼び出し間隔 | **3秒に1回** |
| Events API リトライ | **3回**（即座→1分→5分） |

**重要**: エージェント・ボット共に、イベント受信から HTTP 200応答まで **3秒以内** が必須。実際の処理は非同期で行うことがベストプラクティス。

## 完了サマリー

- ドキュメント: `docs/ai/developing-agents.md`, `docs/ai/agents.md`, `docs/ai/agent-quickstart.md`, `docs/apis/events-api/index.md`, `docs/interactivity/handling-user-interaction.md`
- ログ: `logs/0026_custom-agent-bot-implementation-timeout.md`
