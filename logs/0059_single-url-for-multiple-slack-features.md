# 複数 Slack 機能で同一 URL を使用可能か確認 — 調査ログ

## 調査概要

- **タスク番号**: 0059
- **調査日**: 2026-04-24
- **知りたいこと**: Event Subscription もスラッシュコマンドも manifest.json で同じ URL を書いて良いか
- **目的**: 複数の機能で同一の URL でいいのかを確認したい
- **参照タスク**: 0058（Bolt Python Lambda URL リクエストパス）

---

## 調査アプローチ

1. 前回（0059 の途中まで）の調査を継続
2. 「same url」「single url」「single endpoint」キーワードで全ドキュメントを検索
3. 特に以下を重点確認:
   - `docs/apis/events-api/using-http-request-urls.md`（単一 URL に関する明示的な記述）
   - `docs/interactivity/implementing-slash-commands.md`（`command` フィールドの説明）
   - `docs/interactivity/adding-interactive-modals-to-home-tab.md`（modal の endpoint 説明）
   - `docs/interactivity/handling-user-interaction.md`（interactivity の Request URL）

---

## 調査ファイル一覧

- `docs/apis/events-api/using-http-request-urls.md`
- `docs/interactivity/implementing-slash-commands.md`
- `docs/interactivity/adding-interactive-modals-to-home-tab.md`
- `docs/interactivity/handling-user-interaction.md`
- `docs/reference/app-manifest.md`
- `docs/tools/bolt-python/creating-an-app.md`

---

## 調査結果

### 1. Events API: アプリは Request URL を1つしか持てない

**ドキュメント**: `docs/apis/events-api/using-http-request-urls.md`（1〜15行）

> "**Since your application will have only one Events API request URL**, you'll need to do any additional dispatch or routing server-side after receiving event data."

**日本語訳**: 「アプリが持てる Events API の Request URL は 1 つだけであるため、イベントデータを受信した後のディスパッチやルーティングはサーバー側で行う必要があります。」

**重要な意味**: Events API の Request URL はアプリ全体で1つ。全てのイベントタイプがこの1つの URL に送られる。サーバー側（=Bolt）が `event.type` フィールドで振り分ける。

同ファイルより:

> "Your request URL is the target location where all of the events your application is subscribed to will be delivered, regardless of the workspace or event type."

→ ワークスペースやイベントタイプに関係なく、全イベントが1つの URL に届く。

### 2. スラッシュコマンド: 1つの URL で複数コマンドを処理できる

**ドキュメント**: `docs/interactivity/implementing-slash-commands.md`（128行）

> "`command` — The command that was entered to trigger this request. **This value can be useful if you want to use a single Request URL to service multiple slash commands**, as it allows you to tell them apart."

**日本語訳**: 「`command` — このリクエストをトリガーするために入力されたコマンド。複数のスラッシュコマンドに対して単一の Request URL を使いたい場合、この値を使うことで各コマンドを区別できます。」

→ ドキュメントが**明示的に**「1つの URL で複数スラッシュコマンドを処理できる」と述べている。

### 3. モーダル: アクションと同一エンドポイントを使用

**ドキュメント**: `docs/interactivity/adding-interactive-modals-to-home-tab.md`

> "When the form in the modal is submitted, a payload is sent to the **same endpoint of the action**. You can differentiate the submission by checking the `type` in the payload data."

→ モーダル送信（`view_submission`）はアクション（`block_actions`）と同じエンドポイントに届く。`type` フィールドで種別を区別する。

### 4. Interactivity の Request URL: ボタン・ショートカット・モーダルが共通

**ドキュメント**: `docs/interactivity/handling-user-interaction.md`（40〜45行）

> "**Request URL**: the URL we'll send the request payload to when **interactive components** or **shortcuts** are used."
> 
> "This **Request URL** is also used by **modals** for `view_submission` event payloads. Your app can distinguish between the different types of payload using the `type` field."

→ Interactivity の Request URL は:
- インタラクティブコンポーネント（ボタン等）= `block_actions`
- ショートカット（グローバル・メッセージ）= `shortcut` / `message_action`
- モーダル送信 = `view_submission`
- モーダルキャンセル = `view_closed`

これらすべてが**1つの Request URL** に届き、`type` フィールドで区別する。

### 5. manifest.json での Request URL フィールドの整理

**ドキュメント**: `docs/reference/app-manifest.md`（JSON 例より）

```json
{
    "settings": {
        "event_subscriptions": {
            "request_url": "https://example.com/slack/the_Events_API_request_URL"
        },
        "interactivity": {
            "is_enabled": true,
            "request_url": "https://example.com/slack/message_action",
            "message_menu_options_url": "https://example.com/slack/message_menu_options"
        }
    },
    "features": {
        "slash_commands": [
            {
                "command": "/z",
                "url": "https://example.com/slack/slash/please"
            }
        ]
    }
}
```

manifest.json のサンプルでは各フィールドに異なる URL が設定されているが、これは**説明目的のデモ**であり、制約ではない。ドキュメント各所の記述から、**全フィールドに同一 URL を設定することが明示的にサポートされている**。

---

## 結論

### **YES: Event Subscription もスラッシュコマンドも同一 URL で良い**

manifest.json の全 `request_url` フィールドに同一の URL（例: Lambda Function URL のルートパス）を設定できる。

**技術的根拠（ドキュメントの直接引用）**:

| 根拠 | 出典 |
|------|------|
| Events API は「アプリに1つの Request URL しかない」 | `docs/apis/events-api/using-http-request-urls.md` |
| スラッシュコマンドは「単一 URL で複数コマンドを処理できる」 | `docs/interactivity/implementing-slash-commands.md` |
| モーダル送信はアクションと「同一エンドポイント」に届く | `docs/interactivity/adding-interactive-modals-to-home-tab.md` |

### Bolt によるルーティングの仕組み

Slack は全ての機能のリクエストを同一 URL に POST する。リクエストボディの `type` フィールド（または `command` フィールド）で種別が判別できる:

| 送信元 | request body の識別フィールド | Bolt ハンドラー |
|--------|------------------------------|----------------|
| Events API | `event.type`（例: `app_mention`） | `app.event()` |
| Block Actions（ボタン等） | `type: "block_actions"` | `app.action()` |
| Shortcuts | `type: "shortcut"` / `"message_action"` | `app.shortcut()` |
| Modal Submit | `type: "view_submission"` | `app.view()` |
| Slash Commands | `command: "/mycommand"` | `app.command()` |

Bolt は URL パスではなくこれらのフィールドでルーティングするため、全機能に同一 URL を使用できる。

### Lambda Function URL での manifest.json 設定例

```json
{
    "settings": {
        "event_subscriptions": {
            "request_url": "https://xxxx.lambda-url.us-east-1.on.aws/"
        },
        "interactivity": {
            "is_enabled": true,
            "request_url": "https://xxxx.lambda-url.us-east-1.on.aws/"
        }
    },
    "features": {
        "slash_commands": [
            {
                "command": "/mycommand",
                "url": "https://xxxx.lambda-url.us-east-1.on.aws/"
            }
        ]
    }
}
```

全フィールドに Lambda Function URL のルートパスをそのまま設定すれば良い。

---

## 問題・疑問点

- `settings.interactivity.message_menu_options_url`（External Select Menu）だけは、Slack がオプションを取得するために別タイミングで呼ばれる。同一 URL でも動作するが、URL Verification のような特殊なレスポンスは不要（POSTリクエストへの通常のJSONレスポンスを返す）。
- 仮に `message_menu_options_url` を別途設定したい場合は別 URL も可能だが、必須ではない。
