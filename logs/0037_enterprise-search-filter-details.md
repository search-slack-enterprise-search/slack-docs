# Enterprise Search Filter の詳細 - 調査ログ

## 調査情報

- タスクファイル: `kanban/0037_enterprise-search-filter-details.md`
- 調査日: 2026-04-17
- 調査者: Claude (kanban スキル)

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md` — メイン調査対象
- `docs/enterprise-search/enterprise-search-access-control.md` — filter 関連記述なし
- `docs/reference/app-manifest.md` — filter 関連記述なし

## 調査アプローチ

1. `docs/enterprise-search/` 以下を `filter` キーワードでgrep → `developing-apps-with-search-features.md` に集中
2. `slack#/types/search_filters` キーワードでドキュメント全体を検索 → 同一ファイルのみ
3. `search_filters_function_callback_id` キーワードでドキュメント全体を検索 → 同一ファイルのみ
4. `docs/enterprise-search/developing-apps-with-search-features.md` を全文読み込み

## 調査結果

### Filter の位置づけ

Enterprise Search における Filter は**オプション機能**であり、アプリ開発者が独自の検索絞り込み条件をユーザーに提供できるものである。

ソース: `docs/enterprise-search/developing-apps-with-search-features.md` L183-L289

```
## Adding optional search filters {#adding-search-filters}

Apps can define a single custom step function that provides search filters available to users and passes them to the search function.
The function's `callback_id` should be set as the `search_filters_function_callback_id` in the app manifest.
```

---

### アプリマニフェストへの設定

アプリマニフェストの `features.search` オブジェクトに `search_filters_function_callback_id` を追加することでフィルター機能を有効化する（`search_function_callback_id` は必須、`search_filters_function_callback_id` はオプション）。

```json
..."features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```

ソース: L23-L33

| フィールド | 説明 | 必須 |
|---|---|---|
| `search_function_callback_id` | 検索結果を返すカスタムステップ関数のコールバックID | 必須 |
| `search_filters_function_callback_id` | フィルターを返すカスタムステップ関数のコールバックID | オプション |

---

### フィルター関数の入力パラメータ

ソース: L187-L203

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `*` | `slack#/types/user_context` 型のパラメータ（名前問わず）にユーザーコンテキストがセット | `slack#/types/user_context` | オプション |

→ フィルター関数への入力は基本的に「誰が検索しているか」のユーザー情報のみ。クエリ文字列は渡ってこない。

---

### フィルター関数の出力パラメータ

ソース: L205-L207

```
The function must define an output parameter named `filter` of the `slack#/types/search_filters` type.
The `slack#/types/search_filters` type is an array of up to 5 `filter` objects.
Any other output parameters will be ignored by search operations.
```

- 出力パラメータ名は **`filter`** 固定
- 型は `slack#/types/search_filters`（最大5個のfilterオブジェクトの配列）
- 他の出力パラメータは無視される

---

### filter オブジェクトの構造

ソース: L209-L256

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `name` | 開発者が設定するマシン可読な一意名。search function 内で参照するためのキー | string | 必須 |
| `display_name` | 検索UIに表示される人間可読な名前 | string | 必須 |
| `display_name_plural` | `multi_select` 時、複数選択されている場合のラベル表示名。未指定時は `display_name` を使用 | string | オプション（multi_select時） |
| `type` | フィルターの種類。`multi_select` または `toggle` | string | 必須 |
| `options` | 選択肢の配列（`option` オブジェクト）。`multi_select` の場合は必須 | object | `multi_select` 時は必須、他はオプション |

フィルタータイプ:
- **`multi_select`**: 複数選択可能なフィルター。選択肢（`options`）が必須
- **`toggle`**: オン/オフのトグルスイッチ型フィルター。選択肢不要

---

### option オブジェクトの構造

ソース: L259-L282

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `name` | 検索UIに表示される人間可読な名前 | string | 必須 |
| `value` | 開発者が設定する一意識別子。search function 内で解決するために使用 | string | 必須 |

---

### 検索関数（search function）との連携

ソース: L69-L75

検索関数の入力パラメータ `filters` にユーザーが選択したフィルターのkey-valueペアが渡ってくる。

```
`filters`
An object containing the key-value pair of the filters selected by the user when interacting with search.
(type: object, optional)
```

- キー: filter オブジェクトの `name`（開発者が設定したマシン可読名）
- 値: ユーザーが選択した option の `value`

ユーザーがフィルターを変更すると、検索関数が再トリガーされる（L179）:
```
The search function specified by the `search_function_callback_id` is triggered when users perform searches or modify search filters.
```

---

### キャッシュ動作

ソース: L287-L289

```
When a user selects the app in the search window and views its results, the function defined as `search_filters_function_callback_id` is called.
Slack doesn't expect these filters to change while the user is in the same search context.
For this reason, once the filters are received, they will be cached and the function won't be called again until the search context changes.

Slack caches successful filter results for each user for up to three minutes.
```

- フィルター関数はユーザーが検索ウィンドウでアプリを選択したときに1回だけ呼ばれる
- 同一検索コンテキスト内では再呼び出しされない
- フィルター結果はユーザーごとに最大**3分間**キャッシュされる
- 検索コンテキストが変わると再呼び出し

---

### 使い道・ユースケースのイメージ

ドキュメントには具体的な使用例の記述はないが、仕組みから以下が想定される:

**multi_select の使用例:**
- 外部 Wiki の「カテゴリ」フィルター（Tech, HR, Finance, Marketing など）
- ファイルの「ドキュメントタイプ」フィルター（PDF, Word, Spreadsheet など）
- チケットの「ステータス」フィルター（Open, In Progress, Closed など）
- 「担当者」フィルター（ユーザーコンテキストに基づいてチームメンバーを動的に返す）

**toggle の使用例:**
- 「自分が関わったもののみ」ON/OFF
- 「最近更新されたもののみ」ON/OFF
- 「お気に入りのみ」ON/OFF

**ユーザーコンテキストを活用した動的フィルター:**
- フィルター関数はユーザー情報（user_context）を受け取れるため、ユーザーごとに異なるフィルター選択肢を返すことが可能
- 例: そのユーザーが所属するチームやプロジェクトに応じたカテゴリ一覧を動的生成

---

### フロー整理

```
1. ユーザーが検索ウィンドウでアプリを選択
         ↓
2. Slack が search_filters_function を呼び出す
   - input: user_context（任意）
   - output: filter[]（最大5個）
         ↓
3. Slack はフィルター選択UIを表示（キャッシュ: 3分間）
         ↓
4. ユーザーがクエリを入力 or フィルターを変更
         ↓
5. Slack が search_function を呼び出す
   - input: query（文字列）, filters（ユーザーが選択したkey-value）, user_context（任意）
   - output: search_results[]（最大50件）
         ↓
6. Slack が検索結果を表示（キャッシュ: 3分間）
```

---

## 問題・疑問点

- フィルター関数に `query` は渡ってこないため、クエリの内容に応じて動的にフィルター選択肢を変えることは（現時点では）できない
- `type` として `dropdown` が `option` オブジェクトの説明（L252）で言及されているが、filter オブジェクトの `type` フィールドの説明（L244-L245）では `multi_select` と `toggle` のみ記載。`dropdown` は別のコンテキストで使われていると思われるが詳細不明
  - L252: `An array of options used to define the context of a select, multi_select, or dropdown.`（`select` と `dropdown` も記述されているが、type としては定義されていない。UIの別称か古いAPIか不明）
