# Enterprise Search における Filter 定義実装の必須可否

## 知りたいこと

Enterprise Searchにおいて、Filterの定義実装は必須なのか

## 目的

Filterはなくても動くように思えるが、その確証が欲しい

## 調査サマリー

**Filter（`search_filters_function_callback_id`）の実装は必須ではなく、完全にオプションである。**

公式ドキュメント（`docs/enterprise-search/developing-apps-with-search-features.md`）に以下が明記されている:

| フィールド | 必須/オプション |
|---|---|
| `search_function_callback_id` | **Required（必須）** |
| `search_filters_function_callback_id` | **Optional（オプション）** |

セクション見出し自体も "**Adding optional search filters**" となっており、Filter 機能全体がオプションであることを示している。

フィルターを定義しない場合は `search_filters_function_callback_id` をマニフェストから省略するだけでよく、search function 側の `filters` 入力パラメータもオプションのため、動作上の問題はない。

## 完了サマリー

- 調査日: 2026-04-20
- 結論: Filter（`search_filters_function_callback_id`）は**オプション**。マニフェストから省略して構わない。
- 根拠: `docs/enterprise-search/developing-apps-with-search-features.md` の search object テーブルに "Optional" と明記、セクション見出しにも "Adding **optional** search filters" と記載。
- 詳細ログ: `logs/0041_enterprise-search-filter-mandatory.md`
