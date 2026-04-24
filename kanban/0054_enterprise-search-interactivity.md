# Enterprise Search と Interactivity の連携

## 知りたいこと

Enterprise Searchとinteractivityの連携について教えて

## 目的

manifest.jsonの書き方を調べていたらinterractivityで検索結果にボタンを使えるように見えた。
連携できるのか、連携できるのならどう使えるのかを知りたい。

## 調査サマリー

**結論: Enterprise Search と interactivity は直接連携しない。Work Objects を経由することでボタン等のインタラクティブ要素を利用できる。**

### ポイント

- `settings.interactivity` はアプリ全体の設定であり、Enterprise Search 専用ではない
- Enterprise Search の `search_results` オブジェクトはボタン等の interactive elements を持たない（フィールドは title・description・link・date_updated・content・external_ref のみ）
- **Work Objects を実装すると、ユーザーが検索結果をクリックしてフレックスペインを開いた際にアクションボタンを表示できる**
- フレックスペインには `primary_actions`（最大2つ）と `overflow_actions`（最大5つ）が配置可能
- ボタンをクリックすると `block_actions` イベントが `settings.interactivity.request_url` に送信される

### 実装に必要なもの

1. **manifest.json の設定**:
   - `event_subscriptions.bot_events` に `entity_details_requested` を追加
   - `settings.interactivity.is_enabled: true` と `request_url` を設定

2. **Work Objects の設定**:
   - アプリ設定画面の「Work Object Previews」でエンティティタイプを有効化（UI操作）
   - `entity_payload.actions` にボタンを定義

3. **Enterprise Search との紐付け**:
   - `search_results` の `external_ref.id` と Work Object の `external_ref.id` を一致させる

### フロー

```
ユーザーが検索 → function_executed イベント → search_results を返す（external_ref.id 含む）
→ ユーザーが検索結果をクリック → entity_details_requested イベント（Enterprise Search 経由は channel 等なし）
→ entity.presentDetails でフレックスペイン表示（ボタン含む）
→ ユーザーがボタンクリック → block_actions が request_url に送信
```

詳細は `logs/0054_enterprise-search-interactivity.md` を参照。

## 完了サマリー

2026-04-24 調査完了。Enterprise Search の検索結果にボタンを追加するには Work Objects との連携が必要であることを確認。`settings.interactivity` は Work Objects のボタンクリック時の `block_actions` 受信に使用する。
