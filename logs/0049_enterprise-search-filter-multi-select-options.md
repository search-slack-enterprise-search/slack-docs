# Enterprise Search Filter の multi_select 選択肢事前定義要否

## 調査概要

- **調査日**: 2026-04-21
- **調査者**: Claude Code
- **タスクファイル**: kanban/0049_enterprise-search-filter-multi-select-options.md

---

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md` — 主要調査対象
- `docs/enterprise-search/index.md` — 概要確認
- `docs/enterprise-search/connection-reporting.md` — 周辺確認
- `docs/enterprise-search/enterprise-search-access-control.md` — 周辺確認
- `docs/reference/app-manifest.md` — マニフェストスキーマ確認
- `docs/ja-jp/enterprise-search/` — 日本語訳（存在しない）

---

## 調査アプローチ

`enterprise-search/developing-apps-with-search-features.md` が Enterprise Search のフィルター定義に関する唯一の詳細ドキュメント。まず全体構造を把握し、`multi_select` と `options` の記述を重点的に確認した。

---

## 調査結果

### 1. manifest.json に記載するフィルター関連情報

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`  
**行 7–33**

manifest.json の `features.search` ブロックに記載するのは **コールバック ID のみ**。フィルターの定義（選択肢を含む）は manifest.json に一切記載しない。

```json
"features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```

| フィールド | 説明 | 必須 |
|---|---|---|
| `search_function_callback_id` | 検索結果を返す関数の callback_id | 必須 |
| `search_filters_function_callback_id` | 利用可能なフィルターを返す関数の callback_id | オプション |

引用（行 9）:
> Your app must include the `search` object within the `features` block of its app manifest. This object links the search functionality in Slack to specific custom steps defined by your app.

---

### 2. フィルター定義はどこで行うか

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`  
**行 183–207**

フィルター定義は manifest.json ではなく、**`search_filters_function_callback_id` で指定した関数が実行時に動的に返す**。

引用（行 183–185）:
> Apps can define a single custom step function that provides search filters available to users and passes them to the search function. The function's `callback_id` should be set as the `search_filters_function_callback_id` in the app manifest.

出力パラメータ（行 205–207）:
> The function must define an output parameter named `filter` of the `slack#/types/search_filters` type. The `slack#/types/search_filters` type is an array of up to 5 `filter` objects. Any other output parameters will be ignored by search operations.

---

### 3. filter オブジェクトの完全なスキーマ

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`  
**行 209–257**

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `name` | 検索関数内で参照するためのマシンリーダブルな一意の名前 | string | 必須 |
| `display_name` | 検索 UI でフィルターを説明する人間が読める名前 | string | 必須 |
| `display_name_plural` | 複数オプション選択時のフィルターラベル（未指定時は `display_name` を使用） | string | オプション（`multi_select` 時のみ） |
| `type` | `multi_select` または `toggle` | string | 必須 |
| `options` | フィルターのコンテキストを定義するオプションの配列 | object | **`type` が `multi_select` の場合は必須、それ以外はオプション** |

**行 251–257 の引用（最重要）**:
> An array of options used to define the context of a `select`, `multi_select`, or `dropdown`. See [`option` object](#option-object).
>
> **Required if type is `multi_select`, otherwise optional.**

---

### 4. option オブジェクトの完全なスキーマ

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`  
**行 259–283**

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `name` | 検索 UI でフィルターを説明する人間が読める名前 | string | 必須 |
| `value` | 検索関数内で解決するための開発者が設定した一意の識別子 | string | 必須 |

---

### 5. フィルターのキャッシュ仕様

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`  
**行 285–289**

引用:
> When a user selects the app in the search window and views its results, the function defined as `search_filters_function_callback_id` is called. Slack doesn't expect these filters to change while the user is in the same search context. For this reason, once the filters are received, they will be cached and the function won't be called again until the search context changes.
>
> Slack caches successful filter results for each user for up to three minutes.

---

## 結論

### Q1: multi_select は選択肢（options）も事前定義する必要があるか？

**答え: manifest.json への事前定義は不要。ただし関数の戻り値には options は必須。**

- manifest.json に記載するのは `search_filters_function_callback_id`（コールバック ID）のみ
- フィルターの選択肢（options）は `search_filters_function_callback_id` で指定した関数が実行時に返す
- `type` が `multi_select` の場合、その関数の戻り値（filter オブジェクト）に `options` フィールドを含めることが**必須**（ドキュメント行 257 に明記）

### Q2: manifest.json にどこまで記載する必要があるか？

**答え: manifest.json にはコールバック ID のみ記載する。フィルター定義（options 含む）は一切書かない。**

manifest.json の記載内容（フィルター関連）:
```json
"features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```

フィルターの実際の定義（name、display_name、type、options）はコード（関数の実装）内で定義し、関数の実行時に Slack へ返す。
