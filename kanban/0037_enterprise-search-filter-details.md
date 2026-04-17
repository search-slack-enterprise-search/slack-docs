# Enterprise Search Filter の詳細

## 知りたいこと

Enterprise SearchのFilterがどんなものなのか詳しく知りたい

## 目的

Filterの仕組み、使い方、使い道などイメージが湧かないため

## 調査サマリー

### Filter とは

Enterprise Search の**オプション機能**。アプリ開発者が独自の検索絞り込み条件（フィルターUI）をユーザーに提供できる。

### 仕組み

- アプリマニフェストの `features.search` に `search_filters_function_callback_id`（オプション）を追加
- 指定したカスタムステップ関数が**フィルター定義を返す関数**として機能する
- ユーザーが検索ウィンドウでアプリを選択したタイミングで1回呼ばれ、結果は3分キャッシュ

### フィルターの種類（type）

| type | 説明 |
|---|---|
| `multi_select` | 複数選択可能。`options` 配列（最大）で選択肢を定義 |
| `toggle` | ON/OFF のトグルスイッチ。選択肢不要 |

- フィルターは最大5個まで定義可能

### filter オブジェクトの主なフィールド

- `name`: 開発者が設定するマシン可読な一意キー（search function で `filters[name]` として参照）
- `display_name`: 検索UIに表示される名前
- `type`: `multi_select` or `toggle`
- `options`: 選択肢の配列（`multi_select` では必須）

### search function との連携

- ユーザーがフィルターを選択した状態で検索すると、search function の入力パラメータ `filters` にkey-valueペアとして渡ってくる
  - key: filter の `name`
  - value: 選択された option の `value`
- フィルター変更のたびに search function が再呼び出しされる

### 動的フィルターが可能

- フィルター関数には `user_context`（ユーザー情報）が渡ってくるため、ユーザーごとに異なる選択肢を動的生成できる
- 例: そのユーザーが所属するチームのカテゴリ一覧を動的に返す

### 使い道のイメージ

- **multi_select**: ドキュメントのカテゴリ（Tech/HR/Finance）、ファイル種別（PDF/Word）、チケットステータス（Open/Closed）
- **toggle**: 「自分が関わったもののみ」「最近更新されたもののみ」

### 疑問点

- `option` オブジェクトの説明に `select` や `dropdown` という type への言及があるが、filter の type 定義には `multi_select` と `toggle` しか記載されていない（古いAPIの残滓か別称か不明）

## 完了サマリー

`docs/enterprise-search/developing-apps-with-search-features.md` の L183-L289 を中心に調査。Enterprise Search Filter の仕組み・構造・使い道を把握した。フィルターは最大5個まで定義でき `multi_select`（複数選択）と `toggle`（ON/OFF）の2種類があり、ユーザーの選択内容は search function に `filters` パラメータとして渡される。ユーザーコンテキストを活用した動的フィルターも可能。
