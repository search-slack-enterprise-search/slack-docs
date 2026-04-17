# Enterprise Search 詳細フロー

## 知りたいこと

Enterprise Searchの詳しいフローを教えてください。

## 目的

Enterprise Searchを実装する上でフローを理解することが助けになるため。

## 調査サマリー

### 全体フロー（概要）

1. ユーザーが検索入力 → Slack がクエリをリライト → キャッシュ確認（3分）
2. キャッシュ MISS → `function_executed` イベントをアプリに送信
3. アプリが10秒以内に外部システムを検索 → `functions.completeSuccess` で最大50件返却
4. Slack が結果をキャッシュして表示・AI 回答生成
5. ユーザーが結果クリック → `entity_details_requested` イベント送信
6. アプリが `entity.presentDetails` で Flexpane 詳細を返却（10分ごとに再発火）

### 実装すべきコンポーネント

- **検索関数**: `function_executed` ハンドラー（10秒制限、`search_results[]` を返却）
- **フィルター関数**: 任意（最大5個のフィルター定義を返却）
- **Flexpane ハンドラー**: `entity_details_requested` → `entity.presentDetails`
- **接続管理**: `user_connection` → モーダル表示 → `apps.user.connection.update`

### 重要な制約

| 制約 | 値 |
|---|---|
| 検索関数タイムアウト | 10秒 |
| 検索結果最大数 | 50件 |
| フィルター最大数 | 5個 |
| 検索結果キャッシュ | 3分（user × query） |
| Flexpane 更新間隔 | 10分 |
| Workflow Token 有効期限 | 15分 or 関数完了（先着） |

### external_ref の注意点

変更不可（Related Conversations が壊れる）。外部システムのリソース ID を安定した識別子として設定すること。

## 完了サマリー

Enterprise Search の詳細フローを全体的に調査・整理した。検索フロー（function_executed → completeSuccess）、Flexpane フロー（entity_details_requested → entity.presentDetails）、外部認証フロー（user_connection → apps.user.connection.update）の3つの主要フローと各タイムアウト・制約を確認した。詳細は `logs/0036_enterprise-search-detailed-flow.md` を参照。
