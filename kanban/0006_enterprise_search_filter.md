# Enterprise Searchのfilterについて知りたい
## 知りたいこと
`search_function`と`search_filters_functions`の違いを知りたい。

## 目的
search_functionとsearch_filters_functionの違いや、いつ呼ばれるのかがよくわからない。

## 調査サマリー

### 2つの関数の役割

| | search_function | search_filters_function |
|---|---|---|
| **役割** | 実際の検索結果を返す | フィルターの選択肢（定義）を返す |
| **必須/オプション** | **必須** | オプション |
| **呼ばれるタイミング** | 検索実行時・フィルター変更時（都度） | アプリ選択時（検索コンテキスト開始時のみ） |
| **入力** | query（検索文字列）+ filters（ユーザー選択値）+ user_context | user_context のみ |
| **出力** | 検索結果（最大50件） | フィルター定義の配列（最大5個） |
| **キャッシュ** | ユーザー × クエリ単位で最大3分 | ユーザー単位で最大3分 |

### 呼び出しフロー

```
[ユーザーが検索ウィンドウでアプリを選択]
        ↓
search_filters_function が呼ばれる（フィルター定義を返す）
        ↓
フィルター UI が構築される（最大5個のフィルター）
        ↓
[ユーザーが検索クエリ入力・フィルター選択]
        ↓
search_function が呼ばれる（query + 選択されたfilters を受け取り検索結果を返す）
        ↓
検索結果が表示される（最大50件）
```

### 連携の仕組み
`search_filters_function` が返したフィルターの `name`/`value` が UI に表示され、ユーザーが選択すると `search_function` の `filters` パラメータとして渡される。

### キャッシュの違いのポイント
- `search_filters_function` は「検索コンテキストが変わるまで再呼び出しされない」という設計（フィルター定義は短時間では変わらない想定）
- `search_function` はクエリやフィルター選択が変わるたびに呼ばれる

## 完了サマリー

`docs/enterprise-search/developing-apps-with-search-features.md` を調査。2つの関数の違いと呼び出しタイミングを確認した。詳細は `logs/0006_enterprise_search_filter.md` を参照。
