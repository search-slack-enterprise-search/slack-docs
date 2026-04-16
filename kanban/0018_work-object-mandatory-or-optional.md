# Work Object 有効化時の対応義務（必須 vs 任意）

## 知りたいこと

0017番への更問い。
WorkObjectを有効化しEntityTypeが設定されているときは必ずWorkObjectに対応させる必要があるのか

## 目的

WorkObjectを有効化するとWorkObjectに必ず対応させる必要があるのかを知りたい。
特に、WorkObjectに対応していないケースも想定されるから。

## 調査サマリー

Work Object Previews は**アプリ全体の設定**であり、有効化すると**すべての検索結果クリックが `entity_details_requested` を発火**させる。個々の search_results レベルで Work Object 対応を ON/OFF する手段はドキュメントに記載なし。

### 有効化時の応答について

ドキュメントの語法:
- `entity_details_requested` のサブスクリプション → **must**（必須）
- サブスクライブ後、各イベントへの `entity.presentDetails` 呼び出し → **can**（任意）

### 「対応しない結果」の扱い

Work Object に対応させたくない結果に対しては `entity.presentDetails` で `not_found` / `restricted` などのエラーを返す方法がある。ただし、いずれもフレックスペーンにエラーが表示される形になり、`link` URL へのシームレスな遷移にはならない。

### まとめ

| 状態 | 動作 |
|------|------|
| Work Object Previews 無効 | `link` URL に遷移（Work Object なし） |
| Work Object Previews 有効 + entity_details 対応 | フレックスペーンに Work Object が表示 |
| Work Object Previews 有効 + `not_found` を返す | フレックスペーンにエラーが表示 |
| Work Object Previews 有効 + 無応答 | Slack が timeout エラーをフレックスペーンに表示（推測） |

→ **「Work Object に対応していないケース」を実現したいなら Work Object Previews を有効にしないのが最もシンプル**。

## 完了サマリー

- Work Object Previews はアプリ全体の設定。有効化するとすべての検索結果クリックが `entity_details_requested` を発火させる
- 個々の search_results レベルで Work Object 対応を制御する仕組みはドキュメントに記載なし
- `not_found` などのエラーで応答することは可能だが、その場合はフレックスペーンにエラーが表示される（`link` URL 遷移にはならない）
- **Work Object に対応させないケースを作りたいなら Work Object Previews を有効にしないことが最もシンプルな方法**
- 参照ログ: `logs/0018_work-object-mandatory-or-optional.md`
