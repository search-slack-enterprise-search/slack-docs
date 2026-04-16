# Enterprise Search user_context の詳細フィールド 調査ログ

## 調査日
2026-04-16

## 調査ファイル一覧

1. `docs/enterprise-search/developing-apps-with-search-features.md`
2. `docs/tools/deno-slack-sdk/reference/slack-types.md`
3. `docs/reference/events/function_executed.md`
4. `docs/reference/interaction-payloads.md`
5. `docs/tools/node-slack-sdk/reference/web-api/interfaces/FunctionExecutedEvent.md`
6. `docs/tools/bolt-python/concepts/custom-steps-dynamic-options.md`
7. `docs/tools/bolt-js/concepts/custom-steps-dynamic-options.md`
8. `docs/reference/app-manifest.md`
9. `docs/tools/bolt-python/tutorial/ai-chatbot/index.md`

---

## 調査アプローチ

1. kanbanタスクを読み込み、`user_context` の詳細フィールドを調べることが目的であることを確認
2. `user_context` というキーワードでドキュメント全体をGrep検索 → 6ファイルがヒット
3. Enterprise Searchのメインドキュメント (`developing-apps-with-search-features.md`) を読み込み
4. 型定義のリファレンスである `slack-types.md` を読み込み → `user_context` セクション（行2652-2742）で詳細を確認
5. `interactor` キーワードで検索し、実際のペイロード例を含む `interaction-payloads.md` を確認
6. `function_executed` イベントのリファレンスを確認

---

## 調査結果

### 1. Enterprise Searchドキュメント (`developing-apps-with-search-features.md`)

#### search_function での user_context の使用（行77-83）

```
`*`

Any additional input parameter with type `slack#/types/user_context`, regardless of its name, 
will be set to the `user_context` value of the user executing the search.

`slack#/types/user_context`

Optional
```

- search function の input parameter で `slack#/types/user_context` 型のパラメータを定義すると、**検索を実行しているユーザーの user_context が自動的に注入**される
- パラメータ名は何でもよい（`*` で表記）
- オプション（必須ではない）

#### search_filters_function での user_context の使用（行197-203）

```
*

Any input parameter with type `slack#/types/user_context` regardless of their field 
will be set to the `user_context` value of the user executing the search

`slack#/types/user_context`

Optional
```

- search_filters_function でも同様に、`slack#/types/user_context` 型のパラメータにユーザーの user_context が自動注入される

---

### 2. Slack Types リファレンス (`slack-types.md`)

#### user_context セクション（行2652-2742）

**型名:** `slack#/types/user_context`  
**一般説明:** Represents a user who interacted with a workflow at runtime.

**Workflow Builder での注意点（行2657-2667）:**
> In Workflow Builder, this input type will not have a visible input field and cannot be set manually by a builder
>
> Instead, the way the value is set is dependent on the situation:
> - **If the workflow starts from an explicit user action (with a link trigger, for example),** then the `user_context` will be passed from the trigger to the function input. If the workflow contains a step that alters the `user_context` value (like a message with a button), then the altered `user_context` value is passed to the function input.
> - **If the workflow starts from something _other_ than an explicit user action (from a scheduled trigger, for example),** then the builder of the workflow must place a step that sets the `user_context` value (like a message with a button). This value will then be passed to the input of the function.
>
> If a workflow step requires `user_context` and there is no way to ascertain the value within Workflow Builder, the workflow cannot be published.

**プロパティ（型固有のもの）（行2711-2722）:**

| プロパティ名 | 型 | 説明 |
|-------------|---|------|
| `id` | string | The `user_id` of the person to which the `user_context` belongs. |
| `secret` | string | A hash used internally by Slack to validate the authenticity of the `id` in the `user_context`. This can be safely ignored, since it's only used by us at Slack to avert malicious actors! |

**共通プロパティ（他の型と同じ）:**

| プロパティ名 | 型 | 説明 |
|-------------|---|------|
| `default` | - | An optional parameter default value. |
| `description` | string | An optional parameter description. |
| `examples` | - | An optional list of examples. |
| `hint` | string | An optional parameter hint. |
| `title` | string | An optional parameter title. |
| `type` | string | String that defines the parameter type. |

**Deno SDK での宣言例:**
```typescript
input_parameters: {
  properties: {
    person_reporting_bug: {
      type: Schema.slack.types.user_context,
      description: "Which user?",
    },
  },
},
```

**JSON Manifest での宣言例:**
```json
"input_parameters": {
  "person_reporting_bug": {
    "type": "slack#/types/user_context",
    "description": "Which user?"
  }
}
```

---

### 3. interaction-payloads.md（実際のペイロード例）

`interactivity` 型の `interactor` フィールドが `user_context` 型であることが確認できた（行9, 12）:

```
The `interactivity` type includes properties for both context about the `interactor` (i.e., the user) 
and an `interactivity_pointer`.
```

**実際のペイロード例（行12）:**
```json
{
  "interactor": {
    "id": "U01AB2CDEFG",
    "secret": "AbCdEFghIJklOMno1P2qRStuVwXyZAbcDef3GhijKLM4NoPqRSTuVWXyZaB5CdEfGHIjKLM6NoP7QrSt"
  },
  "interactivity_pointer": "1234567890123.4567890123456.78a90bc12d3e4f567g89h0i1j23k4l56"
}
```

この `interactor` オブジェクトが `user_context` の実際の形を示しており、フィールドは:
- **`id`**: `U01AB2CDEFG` → Slack のユーザーID (`U` または `W` で始まるID)
- **`secret`**: 長いハッシュ文字列 → Slack内部での検証用。開発者は無視してよい

---

### 4. slack-types.md の interactivity セクション（行1367-1444）

`interactivity` 型の定義：

| プロパティ名 | 型 | 説明 |
|-------------|---|------|
| `interactivity_pointer` | string | A pointer used to confirm user-initiated interactivity in a function. |
| `interactor` | `user_context` | Context information of the user who initiated the interactivity. |

→ `interactivity.interactor` が `user_context` 型であることが明示されている。

---

### 5. welcome-bot チュートリアルでの使用例

`interactivity.interactor.id` でユーザーIDを取得する実例（行167）:

```typescript
MessageSetupWorkflow.addStep(WelcomeMessageSetupFunction, {
  message: SetupWorkflowForm.outputs.fields.messageInput,
  channel: SetupWorkflowForm.outputs.fields.channel,
  author: MessageSetupWorkflow.inputs.interactivity.interactor.id,
});
```

→ `user_context.id` でユーザーIDが取得できることを実際のコードで確認。

---

### 6. function_executed イベントリファレンス（`reference/events/function_executed.md`）

`inputs` フィールドに user_context を含む入力パラメータが渡される。
実際のペイロード例（通常の関数実行の場合）:

```json
{
  "token": "XXYYZZ",
  "team_id": "T123ABC456",
  "api_app_id": "A123ABC456",
  "event": {
    "type": "function_executed",
    "function": {...},
    "inputs": {
      "user_id": "USER12345678"   ← user_context の場合はここにオブジェクトが入る
    },
    "function_execution_id": "Fx1234567O9L",
    "workflow_execution_id": "WxABC123DEF0",
    "event_ts": "1698958075.998738",
    "bot_access_token": "abcd-..."
  },
  ...
}
```

---

## まとめ

### `slack#/types/user_context` の詳細フィールド

Enterprise Search の search_function / search_filters_function で受け取る `user_context` のオブジェクト構造:

```json
{
  "id": "U01AB2CDEFG",
  "secret": "AbCdEFghIJklOMno1P2qRStuVwXyZAbcDef3GhijKLM4NoPqRSTuVWXyZaB5CdEfGHIjKLM6NoP7QrSt"
}
```

| フィールド名 | 型 | 内容 | 開発者が使えるか |
|-------------|---|------|----------------|
| `id` | string | 検索を実行したユーザーの Slack user_id (例: `U01AB2CDEFG`) | **はい** - ユーザー特定やパーソナライズに使用可能 |
| `secret` | string | Slack内部でのユーザー正当性検証用ハッシュ | **不要** - Slackが悪意のある操作を防ぐために使用。開発者は無視してよい |

### Enterprise Search での活用可能性

- **`id` (user_id)** を使って:
  - 検索を実行しているユーザーの権限チェック（アクセス制御）
  - ユーザー固有のパーソナライズされた検索結果を返す
  - 外部サービスのユーザーマッピング（Slack ID と外部サービスのユーザーID の対応）
  - audit ログの記録

### 注意点

- `user_context` を受け取るには、input parameter の型を `slack#/types/user_context` に設定する必要がある
- パラメータ名は任意（ドキュメントでは `*` と表記）
- Workflow Builder では UI に表示されず、手動設定不可（自動注入）
- Enterprise Search では、ユーザーが検索を実行したタイミングで自動的に `user_context` が設定される

---

## 問題・疑問点

- `id` がSlackのuser_id（`U`始まり）なのか、enterprise grid環境でのorg-level user_id（`W`始まり）なのかは不明。Enterprise Search はorg対応が必要なため、後者の可能性もある。
- `secret` の具体的な用途（検証アルゴリズム等）はドキュメントに記載されていない。「Slack内部で使用する」とのみ説明されている。
