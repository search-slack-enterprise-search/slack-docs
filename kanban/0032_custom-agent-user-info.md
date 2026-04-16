# カスタムエージェントでのユーザー情報取得

## 知りたいこと

カスタムエージェントを動かすとき、起点となったユーザーの情報(IDとか)を取得できるかどうか

## 目的

起点となったユーザーの情報を取得できないと、外部から情報を引っ張ってくるときなどで絞り込みが困難なため

## 調査サマリー

**取得可能。** カスタムエージェントのすべてのエントリーポイントでユーザーIDを取得できる。

### エントリーポイント別の取得方法

| エントリーポイント | イベント | 取得フィールド |
|---|---|---|
| エージェントコンテナ スレッド開始 | `assistant_thread_started` | `event.assistant_thread.user_id` |
| エージェントコンテナへのメッセージ | `message.im` | `payload["user"]`（Python） / `context.userId`（JS） |
| チャンネル @メンション | `app_mention` | `event.user` |
| スラッシュコマンド | slash command | `command.user_id` |
| ボタン/アクション | `block_actions` | `body.user.id` |

### Bolt での取得例（Python）

```python
@assistant.user_message
def respond_in_assistant_thread(payload: dict, context: BoltContext, ...):
    user_id = payload["user"]  # または context["user_id"]
```

### Bolt での取得例（JavaScript）

```javascript
userMessage: async ({ context, ... }) => {
    const { userId, teamId } = context;
}
```

Bolt は `context` オブジェクトに `user_id`（Python）/ `userId`（JS）、`team_id`/`teamId`、`channel_id`、`enterprise_id` を自動付与する。

ユーザーIDを取得後、`users.info` API でメールアドレス・表示名・タイムゾーンなどのフルプロフィールも取得可能。

## 完了サマリー

カスタムエージェントを動かすとき、起点となったユーザーのIDはすべてのエントリーポイントで取得可能であることを確認した。エージェントコンテナのスレッド開始時は `event.assistant_thread.user_id`、メッセージ受信時は Bolt の `payload["user"]` または `context.userId`（JS）で取得できる。取得したユーザーIDは外部システムとの照合や絞り込みクエリのパラメータとして利用可能。
