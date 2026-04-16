# Work Object 有効化時の対応義務（必須 vs 任意）調査ログ

## 調査ファイル一覧

- `docs/messaging/work-objects-implementation.md`（実装詳細・フレックスペーン・entity_details_requested）
- `docs/messaging/work-objects-overview.md`（Enterprise Search セクション）
- `docs/enterprise-search/developing-apps-with-search-features.md`（search_results・external_ref の仕様）
- `docs/reference/methods/entity.presentDetails.md`（エラーステータス一覧）

---

## 調査アプローチ

1. `work-objects-implementation.md` でフレックスペーン実装を「実装しない場合」「応答しない場合」を中心に調査
2. `work-objects-overview.md` の Enterprise Search セクションで「must / can」の語法を確認
3. `entity.presentDetails.md` で応答できるエラーステータス一覧を確認
4. `developing-apps-with-search-features.md` で `external_ref` の仕様を再確認

---

## 調査結果

### 1. フレックスペーンを実装しない場合のフォールバック（`work-objects-implementation.md` 行 104）

```
"If your app does not implement the flexpane, the content displayed in the unfurl will be shown in the flexpane as a placeholder."
```

**解釈**:
- **unfurl（チャット上のアンフール）の場合**: フレックスペーンを実装していないと、アンフールに表示していたコンテンツがプレースホルダとしてフレックスペインに表示される
- ただしこれは「unfurl」のケースの説明であり、Enterprise Search のケースでは「アンフールコンテンツ」は存在しない

---

### 2. Enterprise Search に Work Objects を対応させるための要件（`work-objects-overview.md` 行 87-91）

```
"To support Work Objects for your app's Enterprise Search results, traditional search results, and AI answers citations,
your app **must** subscribe to the `entity_details_requested` event.
You can define the type of Work Objects for your search results, such as an item, within the Work Object Previews view within app settings."

"Once your app is subscribed to the `entity_details_requested` event, it **can** respond to the event and call the
`entity.presentDetails` API method with Work Object metadata to launch the flexpane experience."
```

**語法の分析**:
- `entity_details_requested` をサブスクライブすること → **must**（必須）
- サブスクライブ後に `entity.presentDetails` を呼び出すこと → **can**（任意）

→ 「Work Objects を Enterprise Search で使いたいなら `entity_details_requested` のサブスクリプションが必須」だが、サブスクライブした後の各イベントへの応答は "can"（任意）と読める。

---

### 3. entity.presentDetails のエラーステータス一覧（`entity.presentDetails.md` 行 134-140）

```
status: String. Can be one of ["restricted", "internal_error", "not_found", "custom", "custom_partial_view", "timeout", "edit_error"]
```

**各ステータスの意味**:

| ステータス | 意味 |
|-----------|-----|
| `restricted` | アクセス制限（認証後に表示可） |
| `internal_error` | 内部エラー |
| `not_found` | エンティティが見つからない |
| `custom` | カスタムメッセージ表示 |
| `custom_partial_view` | 部分表示 + アクションボタン |
| `timeout` | タイムアウト（Slack がアプリの無応答時に生成すると推測） |
| `edit_error` | 編集失敗時 |

**重要な点**:
- `not_found` が存在する → アプリが「このエンティティは存在しない」とエラーで応答できる
- `timeout` が存在する → アプリが応答しない場合、Slack 側がタイムアウトエラーをフレックスペーンに表示すると推測される（アプリが送信するものではなく Slack が生成するステータス）

---

### 4. `external_ref` フィールドは search_results で必須（`developing-apps-with-search-features.md` 行 103-163）

search_results オブジェクトの `external_ref` フィールドは **Required**:
```
external_ref: A unique identifier for referencing within the search results.
  id: string [Required]
  type: string [Optional]
```

> "If your app implements Work Objects, this should be same value used for that implementation."

→ Work Objects を実装している場合は **should**（推奨）で同一値を使うべきとされている。つまり、Work Objects を実装していない場合は何でも良い値で `external_ref.id` を設定できる。

---

## 総合解釈

### Work Objects 有効化は「アプリレベルの全体設定」

Work Objects の有効化（Work Object Previews + entity type 選択）は**アプリ全体**に対する設定であり、**個々の search_results レベルでは制御できない**。

### `entity_details_requested` への応答義務

| 状態 | 動作 |
|------|------|
| Work Object Previews **無効** | ユーザーがクリックすると `link` URL に遷移 |
| Work Object Previews **有効** | ユーザーがクリックすると `entity_details_requested` が発火 |
| Work Object Previews 有効 + アプリが **応答する** | フレックスペーンに Work Object が表示される |
| Work Object Previews 有効 + アプリが **エラーで応答** | フレックスペーンにエラーが表示される（`not_found` 等） |
| Work Object Previews 有効 + アプリが **応答しない** | Slack が `timeout` エラーをフレックスペーンに表示（推測） |

→ **Work Object Previews が有効な場合、すべての検索結果クリックが `entity_details_requested` を発火させる**。

### 「対応していない結果」の扱い

Work Objects に対応させたくない個別の検索結果がある場合、アプリは `entity.presentDetails` に以下のエラーを返すことができる:

- `not_found`: エンティティが見つからない旨を表示
- `restricted`: アクセス制限の旨を表示

ただし、いずれもフレックスペーンにエラーが表示される形になり、`link` URL へのシームレスな遷移にはならない。

### 「Work Object に対応していないケース」を実現する方法

1. **Work Object Previews を有効にしない** → すべての検索結果は `link` URL 遷移（Work Object なし）
2. **Work Object Previews を有効にし、すべての `entity_details_requested` に対応** → すべての検索結果が Work Object に対応（`not_found` 等を返す場合はエラー表示）

個々の結果を「Work Object あり / なし」で混在させる方法は現在のドキュメントには記載がない。

---

## 問題・疑問点

- `timeout` ステータスが Slack 側で生成されるものか、アプリが送信できるものかはドキュメントに明記なし（`entity.presentDetails` のエラーステータス一覧に含まれているため、アプリが送信できる可能性もある）
- Work Object Previews を有効にして `entity_details_requested` をサブスクライブしているが、各イベントに応答しなかった場合の UI 動作（タイムアウト後のフレックスペーンの見た目）はドキュメントに記載なし
- unfurl の「フレックスペーンを実装しない場合はプレースホルダを表示」という挙動が Enterprise Search にも適用されるかどうかは不明
