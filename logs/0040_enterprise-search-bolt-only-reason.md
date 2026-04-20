# Enterprise Search が Bolt の Python と Node 専用機能である理由

## 調査ファイル一覧

既存の調査ログを横断参照:

- `logs/0012_token-management-contradiction-0005-vs-0010.md` — 「Bolt 専用」明示的記述あり
- `logs/0036_enterprise-search-detailed-flow.md` — Enterprise Search の全体フロー
- `logs/0039_enterprise-search-on-aws-lambda.md` — Lambda での動作可否・Bolt の必要性
- `logs/0001_search_endpoint.md` — エンドポイント設定方法（HTTP/Socket Mode）
- `logs/0006_enterprise_search_filter.md` — search_function / search_filters_function の詳細
- `logs/0037_enterprise-search-filter-details.md` — フィルター機能の詳細

参照している公式ドキュメント:

- `docs/enterprise-search/developing-apps-with-search-features.md` — 中核ドキュメント
- `docs/enterprise-search/index.md` — 概要
- `docs/apis/web-api/real-time-search-api.md` — Web API リファレンス
- `docs/reference/app-manifest.md` — マニフェストスキーマ
- `docs/reference/methods/functions.completeSuccess.md`
- `docs/reference/methods/functions.completeError.md`
- `docs/reference/methods/entity.presentDetails.md`

---

## 調査アプローチ

既存の調査ログ（0001, 0006, 0012, 0036, 0037, 0039）を横断参照し、「Bolt 専用」の根拠と「Bolt 以外でも動く」証拠を両面から整理した。

---

## 調査結果

### 1. 公式ドキュメントの明示的な記述

**ソース**: `docs/enterprise-search/developing-apps-with-search-features.md` 行 309-311（logs/0012 行 75-92 で記録）

```
## Implementing Enterprise Search using Bolt {#implement-search}
You can implement Enterprise Search using the Bolt framework for Node or Python.
```

これが「Bolt Python/Node 専用」と言われる直接の根拠。公式ドキュメントが明示している。

### 2. マニフェスト設定の制約

Enterprise Search 実装に必須のマニフェスト設定（`developing-apps-with-search-features.md` 行 46）:

```json
{
  "features": {
    "search": {
      "search_function_callback_id": "id123456",
      "search_filters_function_callback_id": "id987654"
    }
  },
  "settings": {
    "org_deploy_enabled": true,
    "app_type": "remote",
    "function_runtime": "remote"
  }
}
```

- `app_type: "remote"` は Bolt フレームワーク（Node.js / Python）をターゲットとした設定
- `function_runtime: "remote"` も同様
- **Deno SDK は `app_type: "slack"`（ROSI）のみ対応** → Enterprise Search は実装不可

### 3. イベント処理の同期要件（logs/0036 行 143-151）

```python
# Bolt for Python での実装パターン
@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack, complete, fail, inputs):
    results = search_external_data(inputs.get("query"), inputs.get("filters"))
    complete(outputs={"search_results": [...]})
    ack()
```

- 10秒以内に同期的に完了させる必要がある
- Bolt の `@app.function()` decorator、`auto_acknowledge=False`、`ack_timeout=10` が使われる
- `complete()`, `fail()` は Bolt が提供するヘルパーメソッド

### 4. Lazy Listener は不要（logs/0039 行 159-165）

Enterprise Search は 10 秒以内に同期完了するため、Lazy Listener（3秒超の処理向け機能）は不要。Lambda でもそのまま同期実行可能。これは Bolt の特定機能への依存が低いことを意味するが、同時に実装例がすべて Bolt を前提にしている。

### 5. Event Subscription は標準 HTTP（logs/0001 行 152-169）

```json
"settings": {
  "event_subscriptions": {
    "request_url": "https://your-server.example.com/slack/events",
    "bot_events": ["function_executed", "entity_details_requested"]
  }
}
```

- `request_url` は任意の HTTP エンドポイントを指定可能
- Bolt 以外（Flask, Express, Django, 自前実装など）でも受信可能

### 6. Web API は汎用（理論的に Bolt 不要）

`functions.completeSuccess`, `functions.completeError`, `entity.presentDetails` は標準 Slack Web API:

```bash
curl -X POST https://slack.com/api/functions.completeSuccess \
  -H "Content-Type: application/json" \
  -d '{
    "token": "xwfp-...",
    "function_execution_id": "Fx123...",
    "outputs": {"search_results": [...]}
  }'
```

任意の言語・フレームワークから HTTP POST 可能。Bolt は不要。

---

## 結論

### 「Bolt 専用」と言われる理由（2層構造）

**表層**: 公式ドキュメントが "You can implement Enterprise Search using the Bolt framework for Node or Python" と明記しており、サンプル・テンプレートもすべて Bolt (Python/Node) を前提としている。

**技術的根拠**:
1. `app_type: "remote"` + `function_runtime: "remote"` は Bolt をターゲットとしたマニフェスト設定
2. Deno SDK（ROSI）は `app_type: "slack"` のみ対応 → 技術的に選択肢外
3. Bolt の `@app.function()` decorator パターンが実装の中心

### 実際には「Bolt 専用ではない」

- Event Subscription（HTTP POST）は汎用 → 任意の HTTP サーバーで受信可能
- Web API（`functions.complete*`, `entity.presentDetails`）は汎用 HTTP → 任意言語から呼び出し可能
- 署名検証（HMAC-SHA256）は標準的な HTTP 処理
- 理論的には Flask, Express, Django, 自前実装でも動作する

### ユーザーの仮説は正しい

「Event Subscription で動かせる以上、Web API を実装すれば動くように思える」という仮説は**技術的には正しい**。ただし：

- 公式ドキュメント・サンプルがすべて Bolt を前提としているため、実務的には Bolt が事実上の標準
- 自前実装の場合、署名検証・トークン管理・ACK 処理をすべて自前で実装する必要がある
- 公式サポートの観点から、Bolt 以外の実装はドキュメントに記載がなく、動作保証もない

---

## 問題・疑問点

- Bolt for Java/Go など他言語の SDK は `app_type: "remote"` をサポートするか不明（ドキュメントに記載なし）
- 「Bolt 以外で実装した場合」の公式サポート有無は不明
