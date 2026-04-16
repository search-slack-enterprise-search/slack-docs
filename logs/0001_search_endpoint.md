# 0001_search_endpoint 調査ログ

## ヘッダー

- タスク番号: 0001
- タイトル: search_endpoint
- 開始日時: 2026-04-16T13:32:12+09:00
- 完了日時: 2026-04-16T13:42:00+09:00

---

## タスク概要

kanban ファイル `kanban/0001_search_endpoint.md` より転記:

**知りたいこと**: Enterprise Search を実行させるときに必要なエンドポイント

**目的**: Enterprise Search のドキュメントを見ると、別途アプリケーションサーバーを動かしているように見える。しかし、ぱっとドキュメントを見た限り、アプリケーションサーバーのエンドポイントを設定する項目が見つからない。どうやってエンドポイントを設定している？

---

## 調査結果

### 調査したファイルと発見した事実

#### 1. `docs/enterprise-search/developing-apps-with-search-features.md`

Enterprise Search の主要ドキュメント。マニフェスト例（46行目）に以下が記載されている:

```json
"settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
        "bot_events": [
            "function_executed",
            "entity_details_requested"
        ]
    },
    "app_type": "remote",
    "function_runtime": "remote"
}
```

**重要な発見**: このマニフェスト例には `request_url` も `socket_mode_enabled` も記載されていない。これが「エンドポイント設定が見当たらない」という混乱の原因。

`features.search` ブロックは callback_id のみを指定し、URL は含まない:
```json
"features": {
    "search": {
        "search_function_callback_id": "id123456",
        "search_filters_function_callback_id": "id987654"
    }
}
```

通信フローに関する記述（291-308行目）:
1. アプリが `function_executed` イベントリクエストを受け取る
2. アプリが `functions.completeSuccess` または `functions.completeError` API メソッドへリクエストを送信してファンクション実行を完了させる
3. アプリがイベントに acknowledge する（HTTP 200 OK を返す）
4. ファンクション実行は **10秒以内** に完了する必要がある

347行目で Socket Mode への言及:
> "This is particularly useful when using Socket Mode, or when you need to handle the `function_executed` event within the default 3-second timeout."

サンプルアプリへの言及:
- Python: https://github.com/slack-samples/bolt-python-search-template
- TypeScript: https://github.com/slack-samples/bolt-ts-search-template

#### 2. `docs/reference/app-manifest.md`

マニフェストスキーマのリファレンス。Enterprise Search 固有の URL 設定フィールドは存在しない。

エンドポイント関連フィールドの定義:

| フィールド | 行 | 説明 |
|---|---|---|
| `settings.event_subscriptions.request_url` | 679 | Events API のリクエスト URL（HTTPS 必須）。設定時は App Manifest セクションで手動検証が必要 |
| `settings.socket_mode_enabled` | 779 | Socket Mode 有効化フラグ（boolean）。`true` にすると HTTP エンドポイント不要 |
| `settings.function_runtime` | 829 | `remote`（セルフホスト）または `slack`（Deno Slack SDK）。`functions` を使う場合は必須 |

679行目の引用:
> "A string containing the full `https` URL that acts as the Events API request URL. If set, you'll need to manually verify the Request URL in the **App Manifest** section of your app's settings."

#### 3. `docs/apis/events-api/using-socket-mode.md`

Socket Mode の説明。重要な事実:

- Socket Mode は公開 HTTP Request URL なしで Events API とインタラクティブ機能を使える（5行目）
- WebSocket URL は静的でなく、実行時に `apps.connections.open` API を呼び出して動的に生成される（9行目）
- App-level token (`xapp-***`) が必要（67-69行目）
- ファイアウォール内やセキュリティ上の懸念がある場合に適している（11行目）
- Socket Mode アプリは現在 Slack Marketplace には公開不可（17行目）
- Socket Mode はいつでも HTTP エンドポイントに切り替え可能（13行目）

マニフェストでの設定例（48行目）:
```yaml
settings:
  event_subscriptions:
    bot_events:
      - app_mention
  socket_mode_enabled: true
```

Bolt for Python/JS では `SLACK_APP_TOKEN` 環境変数を設定するだけで Socket Mode が利用可能。

#### 4. `docs/apis/events-api/using-http-request-urls.md`

HTTP Request URL 設定の説明:

- `url_verification` ハンドシェイクが必要（Slack が指定 URL に HTTP POST を送信、`challenge` 値を含む JSON を返す必要がある）
- イベント受信後 **3 秒以内** に HTTP 2xx を返す必要がある
- 失敗時は最大3回リトライ（即座 / 1分後 / 5分後）
- 60分間で配信の 95% 以上が失敗するとサブスクリプションが一時的に無効化される

#### 5. `docs/apis/events-api/comparing-http-socket-mode.md`

HTTP と Socket Mode の比較。推奨方針:

> "For its convenience, ease of setup, and ability to work behind a firewall, we recommend using Socket Mode when developing your app and using it locally. Once deployed and published for use in a team setting, we recommend using HTTP request URLs."

| 観点 | HTTP | Socket Mode |
|---|---|---|
| メッセージングパターン | リクエスト-レスポンス | 双方向 |
| 公開 URL | 必要 | 不要 |
| スケーラビリティ | 水平スケールしやすい | 難しい（最大10接続） |
| 本番環境での推奨 | 推奨 | 開発時に推奨 |

#### 6. `docs/app-manifests/configuring-apps-with-app-manifests.md`

バリデーションエラーの記述（107行目）:
```json
{
    "ok": false,
    "error": "invalid_manifest",
    "errors": [
        {
            "message": "Event Subscription requires either Request URL or Socket Mode Enabled",
            "pointer": "/settings/event_subscriptions"
        }
    ]
}
```

**確証**: `event_subscriptions` を持つアプリは `request_url` か `socket_mode_enabled` のいずれかが必須。

---

## 実装プラン

調査は完了しており、ドキュメントを作成しない純粋な調査タスクであるため、「実装プラン」は調査結果の整理・記録を指す。

### 結論: Enterprise Search のエンドポイント設定方法

Enterprise Search には**専用のエンドポイント設定項目がない**。アプリケーションサーバーのエンドポイント設定は、Slack アプリ共通のトランスポート設定（方式1または方式2）で行う。

**方式1: HTTP Request URL**

マニフェストの `settings.event_subscriptions.request_url` に HTTPS URL を指定する。本番環境推奨。

```json
"settings": {
    "org_deploy_enabled": true,
    "event_subscriptions": {
        "request_url": "https://your-server.example.com/slack/events",
        "bot_events": ["function_executed", "entity_details_requested"]
    },
    "function_runtime": "remote"
}
```

**方式2: Socket Mode（WebSocket）**

マニフェストの `settings.socket_mode_enabled` を `true` にする。開発時・ファイアウォール内推奨。

```json
"settings": {
    "org_deploy_enabled": true,
    "socket_mode_enabled": true,
    "event_subscriptions": {
        "bot_events": ["function_executed", "entity_details_requested"]
    },
    "function_runtime": "remote"
}
```

**なぜドキュメントに記載がないか**:

Enterprise Search のドキュメント（`developing-apps-with-search-features.md`）のマニフェスト例はトランスポート設定を省略している。Enterprise Search 固有の設定ではなく Slack アプリ全般に共通するため、Enterprise Search ドキュメントでは触れられていない。

---

## プランニング経緯

- 初回提案: HTTP Request URL 方式のみを回答として提示
- ユーザーのフィードバック: Enterprise Search での具体的なトランスポート設定方法（HTTP/Socket Mode の両方）を詳細に記載するよう要求
- 修正後: 両方式の具体的なマニフェスト例、設定手順、いずれかが必須である根拠、ドキュメント省略の理由を網羅した詳細プランに更新
- 最終プランが承認された

---

## 会話内容

1. ユーザーが `/kanban` コマンドを実行
2. `kanban/0001_search_endpoint.md` を読み込み、タスク内容を把握
3. プランモードに入り、2つの Explore エージェントを並列実行
   - エージェント1: Enterprise Search ドキュメント全体の調査
   - エージェント2: マニフェスト・認証・Events API の調査
4. 両エージェントとも「Enterprise Search 固有のエンドポイント設定なし、標準の Events API トランスポート設定を使う」という結論で一致
5. 初回プランを作成・提示（HTTP Request URL の説明のみ）
6. ユーザーが「Enterprise Search でどうやってトランスポートの設定を行うのかについても記載して」とフィードバック
7. Socket Mode の詳細・両方式のマニフェスト例・省略理由を追加し、プランを更新
8. ユーザーがプランを承認

---

## 編集したファイル

- `logs/0001_search_endpoint.md`（本ファイル）— 新規作成
- `kanban/0001_search_endpoint.md` — 完了サマリー追記

---

## 実行したコマンド

- JST 現在時刻取得: `TZ=Asia/Tokyo date +"%Y-%m-%dT%H:%M:%S+09:00"`
- logs ディレクトリ確認: `ls logs/`

---

## 判断・意思決定

- トランスポート設定がドキュメントに記載されていない理由: Enterprise Search 固有ではなく Slack アプリ全般の標準設定であるため省略されている
- Socket Mode は Enterprise Search ドキュメント（347行目）でも明示的に言及されており、使用可能であることが確認できる
- `app_type: "remote"` はマニフェストリファレンスには定義がないが、Enterprise Search ドキュメントのサンプルに記載あり（詳細不明）

---

## エラー・問題

特になし。

---

## 完了日時

2026-04-16T13:42:00+09:00
