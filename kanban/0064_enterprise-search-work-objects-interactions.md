# Enterprise Search と Work Objects・Interactions の組み合わせでできること

## 知りたいこと

Enterprise SearchとWork Objects, interactionsを組み合わせて何ができるか

## 目的

これらを組み合わせることで何ができるのかを知りたい

## 調査サマリー

### 結論: Enterprise Search + Work Objects + Interactions の組み合わせで実現できること

**連携の仕組み**:
- Enterprise Search の `search_results.external_ref.id` と Work Objects の `external_ref.id` に**同じ値を使う**ことで連携する
- `entity_details_requested` イベントを購読すると、検索結果クリック時に flexpane を提供できる

**実現できる主なシナリオ**:

| シナリオ | 流れ |
|---|---|
| 検索→リッチプレビュー→アクション | 検索結果をクリック → Work Object flexpane 表示 → ボタンで外部システム操作（`block_actions`） |
| 検索→フィールド編集 | flexpane 内でタスクのステータス・担当者・期日等を Slack から直接編集（`view_submission`） |
| 検索→認証→詳細表示 | 未認証ユーザーには認証フロー → 認証後にフル情報の flexpane |
| AI アンサー+引用 | AI が `description`/`content` で回答生成 → 引用から flexpane へ |
| 関連会話の活用 | 同じ外部アイテムが参照された全 Slack 会話を flexpane の Related Conversations タブで確認 |

**インタラクション手段**:
- アクションボタン（primary 最大2個 + overflow 最大5個）
- フィールド編集（日付・ユーザー・ステータス等の入力要素に自動マッピング）
- Dynamic External Select（入力に応じて動的オプション取得）
- 認証フロー（`user_auth_required`）

**制約**:
- Marketplace 公開不可・org-ready 必須
- `external_ref.id` は変更不可（Related Conversations が壊れる）
- Bolt for Python の Work Objects SDK サポートは Coming soon
- 検索結果から flexpane を開くと `channel`/`message_ts` 等のコンテキストは提供されない

### 詳細ログ

`logs/0064_enterprise-search-work-objects-interactions.md`

## 完了サマリー

Enterprise Search・Work Objects・Interactions の組み合わせにより、**Slack 内から外部システムのデータを検索し、リッチな詳細表示と直接編集・アクション実行まで一貫して行える**ことが確認できた。3機能をつなぐ核心は `external_ref.id` の共有と `entity_details_requested` イベントの購読であり、これにより検索結果と Work Object flexpane が連動する。
