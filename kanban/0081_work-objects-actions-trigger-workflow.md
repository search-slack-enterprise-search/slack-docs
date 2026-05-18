# Work Objects の actions から Slack ワークフローを起動できるか

## 知りたいこと

Work ObjectsのTaskエンティティのactionsにおいて、Slackのワークフローを起動することはできるのか

## 目的

ワークフローを使うことができるのかを知りたい

## 調査サマリー

### 結論: Work Objects の actions からワークフローを直接起動することは**できない**

#### Work Objects の actions スキーマの制約

`work-objects-implementation.md` の actions プロパティ定義を確認した結果、各アクションのプロパティは以下のみ:

| プロパティ | 必須 | 説明 |
|---|---|---|
| `text` | Yes | ボタンテキスト |
| `action_id` | Yes | アクション識別子 |
| `value` | No | インタラクションペイロードに送る値 |
| `style` | No | `primary` または `danger` |
| `url` | No | クリック時にブラウザで開く URL |
| `accessibility_label` | No | スクリーンリーダー用テキスト |

**`workflow` フィールドが存在しない**ため、Block Kit の `workflow_button` タイプは使えない。

`block_actions` ペイロード例でも `type: "button"` が使われており、Work Objects の actions は通常の `button` タイプのみ対応。

#### Slack の `workflow_button` Block Kit 要素について

Slack には `workflow_button` という Block Kit 要素が存在し、ワークフローを Slack 内で直接起動できる。使用可能な場所は **section block または actions block のみ**であり、Work Objects の actions スキーマとは別物。

#### 代替手段

| 方法 | 内容 | 評価 |
|---|---|---|
| `url` フィールドに link trigger URL を設定 | ブラウザが開く（deep link経由でワークフローが起動する可能性あり） | Slack 内での直接起動ではない |
| `block_actions` ハンドラでサーバーサイド処理 | ボタンクリック後にアプリが別の処理を実行 | ワークフロー直接起動ではない |
| Work Objects 外で `workflow_button` を使う | 別の Block Kit メッセージで `workflow_button` を含める | Work Objects の actions とは無関係 |

## 完了サマリー

Work Objects（Task エンティティを含む全エンティティ）の `actions`（`primary_actions` / `overflow_actions`）では、Slack ワークフローを**直接起動することはできない**ことを確認した。

Work Objects の actions スキーマには `workflow_button` タイプに必要な `workflow` フィールドが存在せず、通常の `button` タイプのみが対応している。`workflow_button` は Block Kit の section block / actions block 専用要素であり、Work Objects の actions とは別の仕組み。

ワークフローに近い動作をさせるには、`url` フィールドにワークフローの link trigger URL を設定してブラウザ経由で起動させる方法か、`block_actions` ハンドラでアプリがサーバーサイド処理を行う方法しかない。
