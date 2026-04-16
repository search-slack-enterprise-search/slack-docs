# Work Object の登録要否：Slack に登録が必要か、単なるデータ形式か

## 知りたいこと

0011番の調査内容を深掘りしたい。
Work Object は Slack に事前登録する必要があるのか、それとも単にレスポンスデータの形式（スキーマ）に過ぎないのかが不明確。

## 目的

Work Object の実装方法を正確に理解したい。「登録が必要」であれば何をどこに登録するのか、「形式だけ」であればどのスキーマに従えばよいのかを明確にする。

## 調査サマリー

Work Objects の「登録」には 2 つのレベルがある：

### アプリ設定レベルの登録（必要）

`api.slack.com/apps` の **Work Object Previews** で以下を行う必要がある：
1. Work Objects 機能のトグルを有効化
2. 使用するエンティティタイプ（File / Task / Incident / Content Item / Item）を選択
3. 保存

また、`entity_details_requested` イベントのサブスクライブも必要（Events & Subscriptions の設定）。

### 個々のエンティティデータの登録（不要）

各 Work Object の実データは事前登録不要。API 呼び出し時にペイロードとして渡すだけ：
- Unfurl → `chat.unfurl` の `metadata` パラメータに JSON を含める
- Flexpane → `entity.presentDetails` の `metadata` パラメータに JSON を含める
- Notifications → `chat.postMessage` の `eventAndEntityMetadata` パラメータに含める

### エンティティタイプは Slack が固定定義

5 種類（File / Task / Incident / Content Item / Item）のみ。アプリ側でカスタムタイプを新規定義・登録することはできない。「Item」は汎用タイプで何でも表現できる。

### Enterprise Search との組み合わせ

Enterprise Search と Work Objects を組み合わせる場合、アプリマニフェストに `search` オブジェクトの追加も必要。Work Object Previews では使用する entity type（例：Item）を設定する。

### 結論

「登録が必要か、単なるデータ形式か」の問いには**両方が答え**：
- アプリ設定レベルでは登録（有効化・エンティティタイプ宣言）が必要
- 個々のエンティティデータは Slack が定義したスキーマに従って API 呼び出し時に渡すだけ（事前登録不要）

## 完了サマリー

- 調査日: 2026-04-16
- ログ: `logs/0013_work-object-registration-vs-data-format.md`
- 主要調査ファイル: `docs/messaging/work-objects-implementation.md`、`docs/messaging/work-objects-overview.md`、`docs/enterprise-search/developing-apps-with-search-features.md`
