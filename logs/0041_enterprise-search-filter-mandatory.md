# Enterprise Search における Filter 定義実装の必須可否 - 調査ログ

## 調査情報

- タスクファイル: `kanban/0041_enterprise-search-filter-mandatory.md`
- 調査日: 2026-04-20
- 調査者: Claude (kanban スキル)

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md` — メイン調査対象（唯一の情報源）
- `docs/reference/app-manifest.md` — `search_function` 関連記述なし（Enterprise Search のマニフェスト仕様は developing-apps-with-search-features.md に集約）
- `logs/0037_enterprise-search-filter-details.md` — 過去の関連調査ログ（参照）
- `logs/0006_enterprise_search_filter.md` — 過去の関連調査ログ（参照）

## 調査アプローチ

1. 過去の関連ログ（0037, 0006）を参照し、既存の調査結果を確認
2. `docs/enterprise-search/developing-apps-with-search-features.md` を直接 grep し、ドキュメントソースで確認
3. `docs/reference/app-manifest.md` で `search_function` を検索し、マニフェスト仕様の記述有無を確認

## 調査結果

### 結論: Filter の実装は**必須ではない（オプション）**

Enterprise Search において、Filter（`search_filters_function_callback_id`）の実装は完全にオプションである。`search_function_callback_id`（検索結果を返す関数）のみが必須要件。

---

### ドキュメントの直接的な記述

ソース: `docs/enterprise-search/developing-apps-with-search-features.md` L11-L27

```
## The search object {#search-object}

Your app must include the `search` object within the `features` block of its app manifest.
This object links the search functionality in Slack to specific custom steps defined by your app.

`search_function_callback_id`
The `callback_id` of the function executed whenever Slack needs to collect search results from your app.
Required

`search_filters_function_callback_id`
The `callback_id` of the function executed to return the available filters for your search functionality.
Optional
```

**Required / Optional が明記されている:**
| フィールド | 必須/オプション |
|---|---|
| `search_function_callback_id` | **Required（必須）** |
| `search_filters_function_callback_id` | **Optional（オプション）** |

---

### セクション見出しにも "optional" と明記

ソース: `docs/enterprise-search/developing-apps-with-search-features.md` L183

```
## Adding optional search filters {#adding-search-filters}
```

セクション見出し自体が "**optional** search filters" となっており、Filter 機能全体がオプションであることを示している。

---

### search function の `filters` 入力パラメータもオプション

ソース: `docs/enterprise-search/developing-apps-with-search-features.md` L69-L75

```
`filters`
An object containing the key-value pair of the filters selected by the user when interacting with search.
object
Optional
```

- search function（必須側）の入力パラメータとして `filters` がある
- これも **Optional** と明記されている
- つまり、フィルター関数が定義されていない場合は `filters` が渡ってこないだけで、search function は正常に動作する

---

### アプリマニフェストの最小構成

Filter なしで動作する最小構成:

```json
..."features": {
    "search": {
        "search_function_callback_id": "id123456"
    }
}
```

Filter ありの構成:

```json
..."features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```

---

### `app-manifest.md` での記述

`docs/reference/app-manifest.md` に `search_function` / `search_filters_function_callback_id` の記述は存在しない。Enterprise Search のマニフェスト仕様は `developing-apps-with-search-features.md` に完全に集約されている。

---

### 動作の仕組みから見た根拠

Filter を定義しない場合のフロー:

```
1. ユーザーが検索ウィンドウでアプリを選択
         ↓
2. search_filters_function が未定義のため、フィルター UI は表示されない
         ↓
3. ユーザーがクエリを入力
         ↓
4. Slack が search_function を呼び出す
   - input: query（必須）, filters（渡ってこない or 空のオブジェクト）, user_context（任意）
   - output: search_results[]（最大50件）
         ↓
5. Slack が検索結果を表示
```

search function の `filters` 入力はオプションであるため、フィルターが渡ってこない状態でも search function は問題なく動作する。

## 問題・疑問点

- 特になし。フィルター不要時はマニフェストから `search_filters_function_callback_id` を省略するだけで OK という明確な結論が得られた。
