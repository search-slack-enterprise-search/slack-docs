# Enterprise Search Filter の multi_select 選択肢事前定義要否

## 知りたいこと

Enterprise Search の Filter において multi_select は選択肢も事前定義する必要があるのでしょうか？

## 目的

manifest.json にどこまで記載する必要があるのかを知りたい。

## 調査サマリー

### 結論

**manifest.json にフィルターの選択肢（options）は一切記載しない。manifest.json にはコールバック ID のみ記載する。**

`multi_select` の選択肢（options）は `search_filters_function_callback_id` で指定した関数が実行時に返す。ただし `type` が `multi_select` の場合、その関数の戻り値（filter オブジェクト）に `options` フィールドを含めることは**必須**。

### manifest.json に記載する内容（フィルター関連）

```json
"features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```

### filter オブジェクトのスキーマ（関数の戻り値）

| フィールド | 必須 |
|---|---|
| `name` | 必須 |
| `display_name` | 必須 |
| `display_name_plural` | オプション（multi_select 時のみ意味あり） |
| `type` | 必須（`multi_select` or `toggle`） |
| `options` | **`multi_select` の場合は必須**、それ以外はオプション |

### option オブジェクトのスキーマ

| フィールド | 必須 |
|---|---|
| `name` | 必須（表示名） |
| `value` | 必須（識別子） |

### 根拠ドキュメント

`docs/enterprise-search/developing-apps-with-search-features.md` 行 257:
> Required if type is `multi_select`, otherwise optional.

## 完了サマリー

- manifest.json には `search_filters_function_callback_id`（コールバック ID）のみ記載
- フィルターの選択肢（options）はコード内で定義し、関数の実行時に返す
- `multi_select` タイプの場合、関数の戻り値に `options` を含めること自体は必須
- ログ: `logs/0049_enterprise-search-filter-multi-select-options.md`
