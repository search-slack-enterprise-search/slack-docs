# Work Objectsとは何か

## 知りたいこと

Work Objectsとは何か？

## 目的

SlackとしてはWork Objectsの使用を想定しているようにも読めたが、どういった物なのか、外部の情報としてどういう扱いなのか詳しく知りたい。

## 調査サマリー

### Work Objects とは

link unfurling（URLリッチプレビュー）の進化版。外部サービスのファイル・タスク・インシデントなどのエンティティを Slack 内で構造化して表示・操作できるフレームワーク。2025年10月22日 GA。

### 2つのコンポーネント

- **Unfurl コンポーネント**: チャンネルに URL を投稿するとチャンネル全員に見えるカード型プレビュー。`chat.unfurl` API の `metadata` パラメータで Work Object メタデータを渡す。
- **Flexpane コンポーネント**: Unfurl カードをクリックすると Slack 右側に開くパネル。ユーザー単位の詳細情報・認証・編集機能を提供。`entity.presentDetails` API で中身を渡す。

### サポートされるエンティティタイプ

| entity_type | 用途 |
|-------------|------|
| `slack#/entities/file` | ドキュメント・画像など |
| `slack#/entities/task` | チケット・To-Do |
| `slack#/entities/incident` | インシデント・障害 |
| `slack#/entities/content_item` | コンテンツページ・記事 |
| `slack#/entities/item` | 汎用（カスタムフィールドのみ） |

### 外部情報としての扱い

- `external_ref.id` で外部サービス上のリソース ID を管理（Slack が Related Conversations トラッキングに使用。変更不可）
- `url` で外部サービスの正規 URL を指定
- **Enterprise Search との連携**: `search_result_id`（Enterprise Search）と `external_ref.id`（Work Objects）は同じ値を使うことが推奨
- Enterprise Search の検索結果アイテムをクリックすると `entity_details_requested` イベントが発火し、Work Objects のフレックスペインが開く仕組み

### 実装に必要なもの

- `link_shared` イベントのサブスクリプション（Unfurl 用）
- `entity_details_requested` イベントのサブスクリプション（Flexpane 用・Enterprise Search 連携用）
- `links:read` スコープ（`link_shared` に必要）

### Marketplace 配布可否

- Work Objects 単体: **配布可能**
- Enterprise Search を含む場合: **配布不可**（Enterprise Search の制約が優先）

## 完了サマリー

Work Objects は「link unfurling を拡張した外部データの構造化表示フレームワーク」。外部サービスのデータを Slack 内でネイティブ近い体験で閲覧・操作できる。Enterprise Search との組み合わせでは、検索結果アイテムに対してフレックスペインで詳細表示する仕組みを提供する。外部情報の識別には `external_ref.id` が使われ、Enterprise Search の `id` と統一することが推奨される。
