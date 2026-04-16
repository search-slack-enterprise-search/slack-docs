# 0033: Bolt カスタムエージェントのack()後タイムアウト時間 — 調査ログ

## 調査日
2026-04-16

## タスクファイル
kanban/0033_bolt-agent-post-ack-timeout.md

## 調査テーマ
Boltで構築したカスタムエージェントにおいて、3秒以内にack()をした後のタイムアウト時間

---

## 調査したファイル一覧

- `docs/tools/bolt-python/concepts/lazy-listeners.md`
- `docs/tools/bolt-python/concepts/acknowledge.md`
- `docs/tools/bolt-python/concepts/event-listening.md`
- `docs/tools/bolt-python/concepts/using-the-assistant-class.md`
- `docs/tools/bolt-python/concepts/adding-agent-features.md`
- `docs/ai/developing-agents.md`
- `docs/interactivity/implementing-slash-commands.md`
- `docs/interactivity/handling-user-interaction.md`
- `docs/apis/events-api/index.md`
- `docs/apis/events-api/using-http-request-urls.md`
- `docs/reference/methods/assistant.threads.setStatus.md`
- `logs/0029_custom-agent-async-implementation.md`（参考）
- `logs/0031_lambda-bolt-custom-agent.md`（参考）

---

## 調査結果

### 1. ack() の役割と3秒制限

ソース: `docs/tools/bolt-python/concepts/acknowledge.md`、`docs/tools/bolt-python/concepts/lazy-listeners.md`

カスタムエージェントが受け取る `message.im` イベントは **Events API** のイベントである。Events APIのイベントに対しては、**HTTP 200を3秒以内**に返す必要がある（これが ack() の役割）。

`acknowledge.md`より：
```
We recommend calling ack() right away before initiating any time-consuming processes such as 
fetching information from your database or sending a new message, since you only have 3 seconds 
to respond before Slack registers a timeout error.
```

`lazy-listeners.md`より（Events API イベントについて）：
```
Note that in the case of events, while the listener doesn't need to explicitly call the ack() 
method, it still needs to complete its function within 3 seconds as well.
```

---

### 2. Events APIイベントにおけるack()後の処理時間制限

ソース: `docs/apis/events-api/index.md`、`docs/interactivity/handling-user-interaction.md`

**結論: Events APIを使うカスタムエージェントでは、ack()後にSlack側から課せられる処理タイムアウトは存在しない。**

Events APIはSlackからのイベント通知を受信するだけで、`response_url` のような「限られた時間内に使わなければならない応答URL」は存在しない。ack()（HTTP 200）を返した後、アプリは `chat.postMessage` や `assistant.threads.setStatus` などのWeb APIを任意のタイミングで呼び出せる。

比較: スラッシュコマンド・インタラクティブコンポーネント（Actions/Shortcuts/Modals等）の場合、ペイロードに `response_url` が含まれ、これを使った応答は **30分以内・最大5回** という制限がある。

`handling-user-interaction.md` 93行目より：
```
These responses can be sent up to 5 times within 30 minutes of receiving the payload.
```

ただしこれはスラッシュコマンドやブロックアクションなど、`response_url` を持つインタラクションにのみ適用される。**`message.im` などのEvents APIイベントにはこの制限は適用されない。**

---

### 3. setStatus の2分タイムアウト

ソース: `docs/reference/methods/assistant.threads.setStatus.md`（74行目）

ack()後の処理中にローディング表示（スピナー）を出すために `assistant.threads.setStatus` を呼ぶが、このAPIには重要な制限がある：

> **`status`** - Status of the specified bot user, e.g., 'is thinking...'. A **two minute timeout applies**, which will cause the status to be **removed if no message has been sent**.

つまり：
- `setStatus()` を呼んでローディング表示を出すと、**2分後にメッセージが送信されていない場合、自動的にクリアされる**
- これは **視覚的なローディング表示が消える**だけであり、処理そのものが止まるわけではない
- 2分を超えた後でも `chat.postMessage` や `say()` でメッセージを送ることは可能

この情報は `logs/0031_lambda-bolt-custom-agent.md` の「4. Assistant API メソッドの詳細」にも記録されていた：
```
タイムアウト: 2分で自動クリア
```

---

### 4. Lazy Listener（FaaS/Lambda環境）でのack()後タイムアウト

ソース: `docs/tools/bolt-python/concepts/lazy-listeners.md`

AWS Lambda + Bolt でLazy Listenerを使う場合：
- `ack` 関数は3秒以内に呼ばれる
- `lazy` リスト内の関数は、BoltがLambdaを**自己invoke**することで別のLambda実行として起動される
- lazy関数のタイムアウトは **Lambdaに設定したタイムアウト値**（デフォルト3秒、最大15分）

```python
def respond_to_slack_within_3_seconds(body, ack):
    ack(f"Accepted! (task: {body['text']})")

def run_long_process(respond, body):
    time.sleep(5)  # 3秒超でも可能（Lazyなら）
    respond(f"Completed! (task: {body['text']})")

app.command("/start-process")(
    ack=respond_to_slack_within_3_seconds,
    lazy=[run_long_process]
)
```

`logs/0031_lambda-bolt-custom-agent.md` のserverless.yml例では：
```yaml
timeout: 30  # 十分な余裕を持たせる（推奨30秒以上）
```

---

## 結論

### Q: ack()後のタイムアウトは何秒か？

**Slack側から課せられるタイムアウトは存在しない（Events APIイベントの場合）。**

ただし実際の制約は以下の通り：

| タイムアウト | 内容 | 時間 |
|------------|------|------|
| **ack() 呼び出し期限** | Events APIへのHTTP 200応答 | **3秒以内** |
| **setStatus の自動クリア** | メッセージ未送信時のローディング表示消滅 | **2分後** |
| **Slackが課す処理タイムアウト** | ack()後の処理に対する制限 | **なし（制限なし）** |
| **Lambda タイムアウト（インフラ制約）** | Lambda関数の最大実行時間 | 最大15分（設定依存） |

### 実践的な注意点

1. **2分以内に応答できる見込みの場合**: 通常通り `set_status()` → LLM処理 → `say()` の流れで問題ない
2. **2分を超える可能性がある場合**: `setStatus` のローディング表示が消えるため、ユーザーが混乱する可能性がある。中間結果を逐次送信するストリーミングアプローチを検討するか、処理分割を行う
3. **Lambda環境**: Lazy Listenerパターンを使えばack()と処理を分離できる。Lambda自体のタイムアウトを十分長く設定する必要がある（ドキュメントでは30秒以上推奨）

---

## 調査アプローチ

1. `acknowledge.md` と `lazy-listeners.md` でBoltのack()の仕組みを確認
2. `handling-user-interaction.md` と `implementing-slash-commands.md` でresponse_urlの30分制限を確認（カスタムエージェントには非適用）
3. `apis/events-api/index.md` でEvents APIのレスポンス要件を確認
4. `reference/methods/assistant.threads.setStatus.md` でsetStatusの2分タイムアウトを確認
5. 過去調査ログ（0029, 0031）を参照して既知情報を補完

---

## 問題・疑問点

- `setStatus` の2分タイムアウト後でも `setStatus` を再度呼んでローディング表示を延長できるかどうかはドキュメントに明記されていない（おそらく可能）
- Lazy Listenerが `assistant.thread_started` や `message.im` のAssistantクラスハンドラと組み合わせて使えるかどうかは引き続き要確認（0031でも未解決）
