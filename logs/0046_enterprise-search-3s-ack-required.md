# Enterprise Search における 3 秒以内 ack の必要性 — 調査ログ

## 調査ファイル一覧

- `docs/enterprise-search/developing-apps-with-search-features.md`
- `docs/apis/events-api/index.md`
- `docs/apis/events-api/using-http-request-urls.md`
- `docs/tools/bolt-python/concepts/acknowledge.md`
- `docs/tools/bolt-js/concepts/acknowledge.md`

---

## 調査アプローチ

1. Enterprise Search の主要ドキュメント `developing-apps-with-search-features.md` で `ack`, `3 second`, `timeout`, `respond` を grep して該当箇所を特定
2. Events API の標準仕様（`docs/apis/events-api/index.md`）で一般的な 3 秒ルールを確認
3. Bolt Python/JS の ack ドキュメントで標準的な ack 仕様を確認

---

## 調査結果

### 1. Events API 標準仕様（`docs/apis/events-api/index.md`）

**3 秒以内の応答が必須**（標準ルール）:

> "Your app should respond to the event request with an HTTP 2xx _within three seconds_. If it does not, we'll consider the event delivery attempt failed. After a failure, we'll retry three times, backing off exponentially."

失敗理由として明記されている `http_timeout`:

> "`http_timeout`: Your server took longer than 3 seconds to respond to the previous event delivery attempt."

失敗条件として 3 秒超は明示的に列挙されている:

> "We wait longer than _3 seconds_ to receive a valid response from your server."

### 2. Bolt Python ack 仕様（`docs/tools/bolt-python/concepts/acknowledge.md`）

> "We recommend calling `ack()` right away before initiating any time-consuming processes such as fetching information from your database or sending a new message, since you only have 3 seconds to respond before Slack registers a timeout error."

標準では **3 秒以内** に `ack()` を呼ぶことが求められる。

### 3. Bolt JS ack 仕様（`docs/tools/bolt-js/concepts/acknowledge.md`）

> "We recommend calling `ack()` right away before sending a new message or fetching information from your database since you only have 3 seconds to respond."

こちらも **3 秒以内**。

### 4. Enterprise Search 固有の仕様（`docs/enterprise-search/developing-apps-with-search-features.md` L291–L348）

#### 同期処理の要件

> "To ensure fast search results delivery, apps must handle `function_executed` events **synchronously**. This means the app must complete the function's execution and provide output parameters **before acknowledging the event**."

重要: 通常の Bolt アプリは「まず ack() し、その後処理する」という非同期パターンを推奨しているが、Enterprise Search では**逆順**が求められる。

#### 推奨実装フロー（L297–L307）

1. `function_executed` イベントリクエストを受信する
2. `functions.completeSuccess` または `functions.completeError` API を呼んで関数実行を完了させる
3. イベントに対してレスポンスすることで ack する
   - **「関数実行を 10 秒以内に完了しなければならない」**

#### Bolt Python での対応（L313–L327）

`function_executed` イベントの ack 挙動をコントロールするために 2 つのパラメータを設定:

| パラメータ | 説明 |
|---|---|
| `auto_acknowledge=False` | 開発者が手動で `ack()` を呼ぶタイミングを制御する |
| `ack_timeout=10` | **デフォルトのタイムアウトを 3 秒から 10 秒に延長する** |

引用:

> "`ack_timeout=10`: This extends the default timeout from **3 to 10 seconds**."

#### Bolt JS（Node）での対応（L335–L347）

| パラメータ | 説明 |
|---|---|
| `auto_acknowledge=False` | 開発者が手動で `ack()` を呼ぶタイミングを制御する |

引用:

> "This is particularly useful when using [Socket Mode], or when you need to handle the `function_executed` event within the **default 3-second timeout**."

Bolt JS の場合、`ack_timeout` パラメータによる延長は言及されておらず、「デフォルト 3 秒以内」か Socket Mode で対応するとされている。

---

## 判断・解釈

### 3 秒ルールの適用可否

- **適用される**: Enterprise Search の `function_executed` イベントも Events API の一部であり、デフォルトの 3 秒ルールが適用される
- **ただし特殊**: 通常イベントは「先に ack → 後で処理」のパターンが推奨されるが、Enterprise Search は「先に処理 → 後で ack」という同期パターンが必須
- これは矛盾するため、**Bolt フレームワークによる ack タイムアウト延長で解決**する

### ack タイムアウトの実際

| フレームワーク | デフォルト | Enterprise Search での推奨設定 |
|---|---|---|
| Bolt Python | 3 秒 | `ack_timeout=10`（10 秒に延長） |
| Bolt JS | 3 秒 | Socket Mode または `auto_acknowledge=False`（3 秒以内で処理） |
| HTTP 直接実装 | 3 秒（Events API 仕様） | 処理を 10 秒以内に完了させて ack |

### Enterprise Search 全体のタイムアウト

- **関数実行完了 + ack: 10 秒以内**が最終デッドライン（L307: "Your app must complete the function execution within 10 seconds."）
- これは標準 Events API の 3 秒ルールよりも**緩和**された仕様として提供されている

---

## 問題・疑問点

- Bolt JS に `ack_timeout` パラメータが存在しない（Bolt Python のみ言及）。Bolt JS で 10 秒を超える処理が必要な場合は Socket Mode しか選択肢がないかどうかは明示されていない
- HTTP（非 Bolt）実装の場合、どのように 10 秒の ack タイムアウトを実現するかは言及なし（Events API 標準の 3 秒ルールのみが適用されるなら、10 秒以内の処理は不可能かもしれない）
