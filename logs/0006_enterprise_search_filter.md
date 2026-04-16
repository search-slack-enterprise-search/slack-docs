# Enterprise Search の filter について: search_function vs search_filters_function

## 調査日
2026-04-16

## タスク概要
`search_function` と `search_filters_functions` の違いを調査する。

## 調査ファイル一覧
- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/enterprise-search/index.md`

---

## 調査結果

### ドキュメントの構造

`docs/enterprise-search/developing-apps-with-search-features.md` に `search_function` と `search_filters_function` の両方の詳細な説明が記載されている。

---

## search_function（search_function_callback_id）

### 概要
ユーザーが検索を実行したとき、または検索フィルターを変更したときに呼び出される関数。**必須（Required）**。

### アプリマニフェストでの定義
```json
"features": {
    "search": {
        "search_function_callback_id": "id123456"
    }
}
```

### 入力パラメータ

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `query` | エンドユーザーが入力した検索クエリ文字列 | string | Required |
| `filters` | ユーザーが選択したフィルターのキー/バリューペアを含むオブジェクト | object | Optional |
| `*` | `slack#/types/user_context` 型の任意の入力パラメータ（名前不問） | user_context | Optional |

**注意**: `query` の値は、ユーザーが入力した生のクエリとは異なる場合がある。Slack が他の検索（ネイティブコンテンツや組み込みコネクタ）に合わせてクエリを解析・書き換えるため。セキュリティと検索体験向上のための処理。

### 出力パラメータ
`search_results`（型: `slack#/types/search_results`）: 最大50件の検索結果オブジェクトの配列。他の出力パラメータは無視される。

#### search_results オブジェクトのフィールド

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `external_ref` | 検索結果内での参照用ユニーク識別子 | object | Required |
| `title` | 簡潔な見出しラベル | string | Required |
| `description` | 検索結果の説明（AI回答ではLLMに全文が渡される） | string | Required |
| `link` | 検索結果のソースに移動するためのURI | string | Required |
| `date_updated` | 作成日または最終更新日（"YYYY-MM-DD"形式） | string | Required |
| `content` | 詳細なコンテンツ（AI回答生成に利用） | string | Optional |

#### external_ref オブジェクトのフィールド

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `id` | ユニーク識別子（Work Objects を実装している場合は同じ値を使用） | string | Required |
| `type` | ソースシステム内の内部エンティティ型（IDがグローバルに一意でない場合に必要） | string | Optional |

### 呼ばれるタイミング（Invocations）
ドキュメント記述（行177-181）：
> The search function specified by the `search_function_callback_id` is triggered when users perform searches or modify search filters.
> 
> Slack caches successful search results for each user and query, for up to three minutes. Since search AI answers are generated from the search results, AI answers are also cached for those three minutes.

- **ユーザーが検索を実行するたびに呼ばれる**
- **ユーザーが検索フィルターを変更するたびにも呼ばれる**
- キャッシュ: ユーザーとクエリの組み合わせで最大3分間キャッシュ

---

## search_filters_function（search_filters_function_callback_id）

### 概要
ユーザーが使用できる検索フィルターの選択肢を返す関数。**オプション（Optional）**。

### アプリマニフェストでの定義
```json
"features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```

### 入力パラメータ

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `*` | `slack#/types/user_context` 型の任意の入力パラメータ（名前不問） | user_context | Optional |

**注意**: `query` や `filters` は入力として受け取らない。ユーザーコンテキストのみ。

### 出力パラメータ
`filter`（型: `slack#/types/search_filters`）: 最大5つのフィルターオブジェクトの配列。他の出力パラメータは無視される。

#### filter オブジェクトのフィールド

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `name` | 開発者が設定するマシンリーダブルなユニーク名（search_function で参照される） | string | Required |
| `display_name` | UIに表示される人が読めるフィルター名 | string | Required |
| `display_name_plural` | `multi_select` 時に複数選択された場合のラベル（省略時は `display_name` を使用） | string | Optional |
| `type` | `multi_select` または `toggle` | string | Required |
| `options` | `multi_select` などで使用するオプションの配列 | object | `multi_select` 時は Required |

#### option オブジェクトのフィールド

| フィールド | 説明 | 型 | 必須 |
|---|---|---|---|
| `name` | UIに表示されるオプション名 | string | Required |
| `value` | 開発者が設定するユニーク識別子（search_function で解決される） | string | Required |

### 呼ばれるタイミング（Invocations）
ドキュメント記述（行285-289）：
> When a user selects the app in the search window and views its results, the function defined as `search_filters_function_callback_id` is called. Slack doesn't expect these filters to change while the user is in the same search context. For this reason, once the filters are received, they will be cached and the function won't be called again until the search context changes.
> 
> Slack caches successful filter results for each user for up to three minutes.

- **ユーザーが検索ウィンドウでアプリを選択して結果を表示したときに呼ばれる**
- 同じ検索コンテキスト内ではキャッシュが使われ、再呼び出しされない
- キャッシュ: ユーザーごとに最大3分間キャッシュ

---

## 2つの関数の関係と全体フロー

```
[ユーザーが検索ウィンドウでアプリを選択]
        ↓
search_filters_function が呼ばれる
（ユーザーコンテキストを受け取り、フィルター定義の配列を返す）
        ↓
フィルター定義がUIに表示される（最大5個）
        ↓
[ユーザーが検索クエリを入力 / フィルターを選択]
        ↓
search_function が呼ばれる
（query + 選択されたfilters + user_context を受け取り、検索結果を返す）
        ↓
検索結果がUIに表示される（最大50件）
```

---

## 主な違いの比較表

| 比較項目 | search_function | search_filters_function |
|---|---|---|
| **役割** | 実際の検索結果を返す | フィルターの選択肢を定義して返す |
| **必須/オプション** | **必須** | オプション |
| **入力: query** | あり（Required） | なし |
| **入力: filters** | あり（Optional、ユーザー選択値） | なし |
| **入力: user_context** | あり（Optional） | あり（Optional） |
| **出力** | search_results（最大50件） | filter（最大5個のフィルター定義） |
| **呼ばれるタイミング** | 検索実行時・フィルター変更時 | アプリ選択時（検索コンテキスト開始時） |
| **呼ばれる頻度** | 検索・フィルター変更のたびに | 検索コンテキスト内で1回（キャッシュ後は再呼び出しなし） |
| **キャッシュキー** | ユーザー × クエリ | ユーザー |
| **キャッシュ時間** | 最大3分 | 最大3分 |

---

## 重要なポイント

1. **連携の仕組み**: `search_filters_function` が返したフィルター定義の `name`/`value` が、ユーザーが選択すると `search_function` の `filters` パラメータとして渡される。開発者はこの `name`/`value` を使って検索ロジックにフィルタリングを適用する。

2. **呼び出し順序**: `search_filters_function` の方が先に呼ばれ、フィルター UI を構築する。その後、ユーザーが検索するたびに `search_function` が呼ばれる。

3. **キャッシュ戦略の違い**: `search_filters_function` のキャッシュはユーザー単位（フィルター定義はユーザーごとに同じと想定）。`search_function` のキャッシュはユーザー × クエリ単位（クエリが変わると再実行）。

4. **フィルター定義はユーザー依存可能**: `search_filters_function` は `user_context` を受け取れるため、ユーザーによって異なるフィルター選択肢を返すことができる（例: そのユーザーがアクセス可能なカテゴリのみ）。

---

## 調査アプローチ

1. `search_filters_function` のキーワードで全ドキュメントを検索 → `developing-apps-with-search-features.md` のみヒット
2. `search_function_callback_id` でも検索 → 同様に同ファイルのみ
3. `developing-apps-with-search-features.md` を全文読み込み
4. `enterprise-search/index.md` も確認（Enterprise Search の概要のみ）

メインの情報は全て `developing-apps-with-search-features.md` に集約されている。
