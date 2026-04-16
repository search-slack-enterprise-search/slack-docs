# Enterprise Search user_context の詳細フィールド

## 知りたいこと

Enterprise Searchでuser_contextを渡すとき、具体的に何が渡ってきているのか

## 目的

具体的に何が渡ってきているのかを知ることで、検索で何が使えるのかを知りたい

## 調査サマリー

`slack#/types/user_context` は以下の2フィールドのみを持つシンプルなオブジェクト:

```json
{
  "id": "U01AB2CDEFG",
  "secret": "AbCdEFghIJkl...（長いハッシュ文字列）"
}
```

| フィールド | 型 | 内容 | 開発者が使えるか |
|-----------|---|------|----------------|
| `id` | string | 検索を実行したユーザーの Slack user_id | **はい** |
| `secret` | string | Slack内部でのユーザー正当性検証用ハッシュ | **不要**（無視してよい） |

**Enterprise Searchでの受け取り方:**
- search_function または search_filters_function の input parameter に `slack#/types/user_context` 型を定義すると、自動注入される
- パラメータ名は何でもよい（ドキュメントでは `*` と表記）

**`id` の活用例:**
- ユーザーのアクセス権チェック（Enterprise Search アクセス制御）
- 外部サービスのユーザーマッピング（Slack ID ↔ 外部ユーザー ID）
- ユーザー固有の検索結果パーソナライズ

**参照ドキュメント:**
- `docs/enterprise-search/developing-apps-with-search-features.md`（行77-83, 197-203）
- `docs/tools/deno-slack-sdk/reference/slack-types.md`（行2652-2742 の User context セクション）
- `docs/reference/interaction-payloads.md`（実際のペイロード例）

## 完了サマリー

調査完了（2026-04-16）。`user_context` は `id`（Slack user_id）と `secret`（内部検証用ハッシュ）の2フィールドのみ。実際に検索パーソナライズやアクセス制御で使えるのは `id` フィールドのみ。詳細は `logs/0007_enterprise-search-user-context-fields.md` を参照。
