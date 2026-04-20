# user_connection イベント外からの接続状態更新

## 知りたいこと

0043の更問い。user_connectionイベントの外 (cron実行とか)で `apps.user.connection.update()`はできるのか。

## 目的

トークンの有効期限が切れても接続済みと表示され続けるので、外部から更新できるかどうかを知りたい。

## 調査サマリー

**`apps.user.connection.update()` は `user_connection` イベントの外（cron・バッチ・webhook など）からでも呼び出せる。**

### 根拠

API リファレンスを確認した結果、`apps.user.connection.update` の必須引数は `token`・`user_id`・`status` の3つのみ。`trigger_id` などイベントコンテキストへの依存パラメータは一切なく、タイムアウト制約の記述もない。

| API | `trigger_id` 必須 | タイムアウト | イベント外呼び出し |
|-----|-------------------|------------|-----------------|
| `views.open` | ✓（3秒以内） | あり | **不可** |
| `apps.user.connection.update` | なし | **なし** | **可能** |

### 利用可能なパターン

```
✓ cron ジョブ（定期的なトークン有効性チェック）
✓ 外部サービスのトークン失効 webhook 受信時
✓ 検索関数（function_executed）でトークン検証失敗時
✓ OAuth callback 完了後
```

### cron パターンの実装イメージ

```
定期バッチ
    ↓
DB から全ユーザーのトークン情報を取得
    ↓
for each user:
    外部サービスで token validation → 無効なら:
    apps.user.connection.update(user_id, "disconnected")
```

Rate Limit は Tier 2（20+/min）なので大量ユーザー時は配慮が必要。

## 完了サマリー

- **調査日**: 2026-04-20
- **ログファイル**: `logs/0044_connection-update-outside-event.md`
- **結論**: `apps.user.connection.update` はイベントコンテキスト非依存の通常 REST API。cron・webhook・バックグラウンドタスクなど任意のタイミングから呼び出し可能。トークン有効期限切れへの対処として cron による定期バッチも技術的に実現可能。
