# ログ: Work Objects の actions から Slack ワークフローを起動できるか

## 調査ファイル一覧

- `docs/messaging/work-objects-implementation.md`（actions セクション l.606-728 を精読）
- `docs/reference/block-kit/block-elements/workflow-button-element.md`（全文精読）
- `docs/reference/block-kit/composition-objects/workflow-object.md`（全文精読）
- `docs/reference/block-kit/composition-objects/trigger-object.md`（全文精読）
- `docs/messaging/work-objects-overview.md`（rg 検索）
- 全ドキュメントに対して `workflow_button` で rg 検索

## 調査アプローチ

1. Work Objects の actions スキーマのプロパティ定義を `work-objects-implementation.md` で確認
2. Slack に `workflow_button` というBlock Kit 要素が存在するかを `fd` + `rg` で検索
3. `workflow_button` の仕様（どの block/surface で使えるか）を確認
4. Work Objects の actions スキーマと `workflow_button` のスキーマを比較

---

## 調査結果

### 1. Work Objects の actions スキーマ（`work-objects-implementation.md` l.632-687 より）

Work Objects の `primary_actions` / `overflow_actions` の各アクション定義に使えるプロパティは以下の通り:

| プロパティ | 必須 | 型 | 説明 |
|---|---|---|---|
| `text` | Yes | string | ボタンに表示するテキスト |
| `action_id` | Yes | string | アクション識別子（max 255文字） |
| `value` | No | string | インタラクションペイロードに送る値（max 2000文字） |
| `style` | No | string | `primary`（緑）または `danger`（赤） |
| `url` | No | string | クリック時にブラウザでこの URL を開く（max 3000文字） |
| `accessibility_label` | No | string | スクリーンリーダー用テキスト（max 75文字） |

**重要な確認事項**: `workflow` フィールドが存在しない。

ボタンクリック時には `block_actions` インタラクションリクエストがアプリに送信される。`block_actions` ペイロード例（l.712）では:

```json
"actions": [
  {
    "type": "button",
    "text": { "type": "plain_text", "text": "Summarize issue with AI", "emoji": true },
    "action_id": "github_wo_button_summarize_issue",
    "block_id": "TPdc",
    "style": "primary",
    "value": "user",
    "action_ts": "1748809126.803329"
  }
]
```

`type: "button"` が使われており、通常の button タイプのみが対応している。

---

### 2. `workflow_button` Block Kit 要素（`workflow-button-element.md` より）

Slack には `workflow_button` という Block Kit 要素が存在し、ワークフローを Slack 内で直接起動できる。

**フィールド定義**:

| フィールド | 必須 | 説明 |
|---|---|---|
| `type` | Required | 常に `"workflow_button"` |
| `text` | Required | ボタンテキスト（plain_text のみ、max 75文字） |
| `workflow` | Required | `workflow` オブジェクト（trigger URL を含む） |
| `action_id` | Required | アクション識別子（max 255文字） |
| `style` | Optional | `primary` または `danger` |
| `accessibility_label` | Optional | スクリーンリーダー用（max 75文字） |

**workflow オブジェクト** (`workflow-object.md` より):
- `trigger` オブジェクト（必須）: ワークフローのトリガー情報

**trigger オブジェクト** (`trigger-object.md` より):
- `url` (Required): link trigger URL（`https://slack.com/shortcuts/Ft0123ABC456/...` 形式）
- `customizable_input_parameters` (Optional): ワークフローへの入力パラメータ配列

使用例:
```json
{
  "type": "workflow_button",
  "text": { "type": "plain_text", "text": "Run Workflow" },
  "action_id": "workflowbutton123",
  "workflow": {
    "trigger": {
      "url": "https://slack.com/shortcuts/Ft0123ABC456/xyz...zyx",
      "customizable_input_parameters": [
        { "name": "input_parameter_a", "value": "Value for input param A" }
      ]
    }
  }
}
```

**使用可能な場所** (`workflow-button-element.md` l.69 より):
> 「The workflow button element must be used inside of the **section block** or the **actions block**.」

---

### 3. 比較・結論

| 比較項目 | Work Objects actions | Block Kit workflow_button |
|---|---|---|
| `workflow` フィールド | **なし** | あり（必須） |
| `type` フィールド | なし（暗黙的に `button`） | `"workflow_button"` |
| 使用可能な場所 | Work Objects の entity_payload | section block / actions block |
| ワークフロー直接起動 | **不可** | 可能 |

Work Objects の `actions`（`primary_actions` / `overflow_actions`）のスキーマには `workflow` フィールドが存在せず、`workflow_button` タイプはサポートされていない。

`work-objects-implementation.md` の全文を `rg` で検索した結果、`workflow`（ワークフロー）に関する記述は一切なし。Work Objects の actions は通常の `button` タイプのみ対応している。

---

### 4. 代替手段の検討

**方法A: `url` フィールドにワークフローの link trigger URL を設定**

Work Objects actions の `url` フィールドは「クリック時にブラウザでこの URL を開く」動作をする。Slack ワークフローには link trigger（`https://slack.com/shortcuts/...` 形式）が存在するため、この URL を設定することは技術的に可能。

ただし挙動は:
- ブラウザが開く
- Slack desktop アプリがインストールされていれば、deep link としてワークフローが起動するかもしれない
- **「Slack 内で直接ワークフローを起動する」ではない**

`workflow_button` は Slack 内でクリックした瞬間にワークフローが起動するが、`url` 経由ではブラウザを経由する挙動になる。

**方法B: `block_actions` ハンドラでサーバーサイド処理**

Work Objects の actions でボタンをクリックすると `block_actions` イベントがアプリに送られる。アプリがこのイベントを受け取った後、`chat.postMessage` で `workflow_button` を含む Block Kit メッセージを送るなどの間接的な対応は可能。ただしこれはワークフローを直接起動するものではない。

**方法C: Work Objects の actions 外で `workflow_button` を使う**

Work Objects の unfurl や flexpane コンテンツとは別に、同じメッセージや別のメッセージで Block Kit の actions block に `workflow_button` を含めることは可能。ただし Work Objects の `actions` スキーマを通じた実装ではない。

---

## 問題・疑問点

- Work Objects の actions に将来 `workflow_button` タイプへの対応が追加されるかどうかは不明（ドキュメントに記載なし）
- `url` フィールドに link trigger URL を設定した場合の Slack クライアントでの実際の挙動（deep link としてワークフローが起動するかどうか）は本ドキュメントから確認できない
- Bolt や外部サーバーアプリから REST API 経由でワークフローを直接起動する公式 API があるかどうかは本ドキュメントでは未確認（`admin.workflows.*` API は存在するが、起動用ではなく管理用）
