# Enterprise Search における Work Object と通常結果の区別方法

## 知りたいこと

Work Objectのときとそうでない時をEnterprise Searchはどうやって区別している？

## 目的

Enterprise SearchでSearchの結果を返したとき、Work Objectとそうでない時をどうやって区別している？
Work Objectだと `entity_details_requested` が別途呼ばれるということを考えると、何か基準があるはず。

## 調査サマリー

**区別の基準は「アプリレベルの設定」**。個々の search_results の中身ではなく、アプリが Work Object を有効化しているかどうかで Slack が動作を変える。

### Slack が Work Object かどうかを判断する条件

1. **アプリ設定の「Work Object Previews」が有効化されている**（エンティティタイプも選択済み）
2. **`entity_details_requested` イベントをサブスクライブしている**

→ この2条件が揃ったアプリの検索結果をユーザーがクリックすると、Slack は `entity_details_requested` を発火させてflexpaneを開く。  
→ 条件が揃っていないアプリの検索結果は、クリック時に `link` URL へ遷移するだけ（通常リンク）。

### search_results と Work Object のリンク

`search_results.external_ref.id` を Work Object の `external_ref.id` と同一値にすることで、どの検索結果がどの Work Object エンティティかを Slack に伝える。ドキュメントに明記:  
> "If your app implements Work Objects, this should be same value used for that implementation."

### entity_details_requested の呼び出し元判別

同じ `entity_details_requested` イベントが unfurl（チャット）からも Enterprise Search からも発火するが、以下のフィールドの有無で区別できる:

| フィールド | unfurl から | Enterprise Search から |
|-----------|------------|----------------------|
| `channel` | あり | **なし** |
| `message_ts` | あり | **なし** |
| `thread_ts` | あり | **なし** |

## 完了サマリー

- **区別の基準**: アプリが「Work Object Previews を有効化 + `entity_details_requested` をサブスクライブ」しているかどうか
- **個別結果レベルのリンク**: `search_results.external_ref.id` と Work Object の `external_ref.id` を同一値にする
- **コンテキスト判別**: `entity_details_requested` イベントの `channel`/`message_ts`/`thread_ts` の有無で unfurl vs Enterprise Search を判別できる
- 参照ログ: `logs/0017_enterprise-search-work-object-distinction.md`
