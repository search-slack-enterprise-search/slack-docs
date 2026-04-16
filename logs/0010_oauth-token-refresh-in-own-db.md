# 自社 DB の OAuth トークン更新方法 調査ログ

## 調査概要

- **タスクファイル**: `kanban/0010_oauth-token-refresh-in-own-db.md`
- **調査日**: 2026-04-16
- **目的**: Enterprise Search + Connection Reporting でアプリ独自 DB に保存した外部 OAuth トークンの更新方法を明らかにする

---

## 調査したファイル一覧

1. `docs/authentication/using-token-rotation.md`
2. `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`（行 323–404）
3. `docs/reference/methods/apps.auth.external.get.md`
4. `docs/reference/events/tokens_revoked.md`
5. `docs/tools/bolt-js/concepts/token-rotation.md`
6. `docs/enterprise-search/developing-apps-with-search-features.md`（行 307 ── 10秒制約の確認）
7. 過去ログ: `logs/0009_enterprise-search-external-auth-integration.md`

---

## 調査アプローチ

1. タスクの前提「Slackが保存しているOAuthトークンが更新された際」を検証するため、Slack と外部トークンの関係を確認
2. Deno SDK の `apps.auth.external.get` のリフレッシュ動作を確認
3. `tokens_revoked` イベント（Slack 側でのトークン失効通知）を確認
4. Bolt フレームワークのトークンローテーション機能を確認
5. advisor に確認

---

## 調査結果

### コアとなる発見：前提の誤り

**「Slackが保存しているOAuthトークンが更新された際に自社DBのトークンも更新する必要がある」という前提は誤り**。

Enterprise Search + Connection Reporting と Deno SDK External Auth では、トークンストアが1つしか存在しない（2つのストアが共存するシナリオは存在しない）。

| アプローチ | トークンを管理するのは誰か | 同期が必要か |
|---|---|---|
| Enterprise Search + Connection Reporting（Bolt アプリ） | アプリ独自 DB のみ | 不要（Slack はトークンを持たない） |
| Deno SDK External Auth | Slack のみ | 不要（アプリは DB を持たない） |

---

### 1. Enterprise Search + Connection Reporting の場合

**ファイル**: 過去ログ `logs/0009_enterprise-search-external-auth-integration.md` + `docs/enterprise-search/developing-apps-with-search-features.md`

- Slack が保存する外部サービスの OAuth トークンは**存在しない**
- アプリ独自の DB のみがトークンを持つ
- Slack は「接続状態（connected / disconnected）」の UI 表示のみを管理
- **トークンのリフレッシュはアプリが独自に実装する**（標準 OAuth2 リフレッシュトークンフロー）

#### アプリが実装すべきトークンリフレッシュフロー

```
[DB に保存する情報]
{
  user_id: "U012A3BC4DE",
  access_token: "...",
  refresh_token: "...",
  expires_at: 1764270000  ← UNIX時刻（access_token の有効期限）
}

[リフレッシュ処理]
1. expires_at を確認
2. expires_at が近づいたら外部サービスのトークンエンドポイントを呼ぶ：
   POST https://external-service.example.com/oauth/token
   grant_type=refresh_token
   refresh_token={stored_refresh_token}
   client_id={client_id}
   client_secret={client_secret}

3. 新しいトークンで DB を更新
4. リフレッシュ失敗時は apps.user.connection.update(status: "disconnected") を呼び
   ユーザーに再接続を促す
```

---

### 2. Deno SDK External Auth の場合

**ファイル**: `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md`（行 323–329）、`docs/reference/methods/apps.auth.external.get.md`

Deno SDK External Auth では **Slack がトークンを管理** しており、アプリは DB を持たない。

#### Slack による自動リフレッシュ

`apps.auth.external.get` を呼び出すたびに Slack が有効期限を確認し、期限切れの場合は**自動的にリフレッシュ**する：

```typescript
// アプリは常にこれを呼ぶだけ。リフレッシュは Slack が処理
const tokenResponse = await client.apps.auth.external.get({
  external_token_id: inputs.googleAccessTokenId,
});
// → 常に有効なトークンが返ってくる（Slack が内部でリフレッシュ済み）
const externalToken = tokenResponse.external_token;
```

#### 強制リフレッシュ（force_refresh: true）

```typescript
// エラーハンドリングやリトライ時に強制リフレッシュ
const result = await client.apps.auth.external.get({
  external_token_id: inputs.googleAccessTokenId,
  force_refresh: true  // 期限切れでなくても強制リフレッシュ
});
```

**ソース**（行 323–329）:
> "If you ever want to force a refresh of your external token as a part of error handling, retry mechanism, or something similar, you can use the sample code below"

#### リフレッシュ関連のエラー

| エラー | 説明 |
|---|---|
| `access_token_exchange_failed` | トークンのリフレッシュ中にエラーが発生 |
| `no_refresh_token` | リフレッシュトークンが存在しない（期限切れのアクセストークンを更新できない） |

---

### 3. Slack からのトークン失効通知

**ファイル**: `docs/reference/events/tokens_revoked.md`

`tokens_revoked` イベントは Slack の **bot/user トークン（`xoxb-`/`xoxp-`）が失効した場合のみ**発火する。外部サービスの OAuth トークンに関するイベントは存在しない。

```json
{
  "event": {
    "type": "tokens_revoked",
    "tokens": {
      "oauth": ["UXXXXXXXX"],  ← Slack ユーザートークンの失効
      "bot": ["UXXXXXXXX"]     ← Slack ボットトークンの失効
    }
  }
}
```

**外部サービスの OAuth トークン失効・期限切れに関するイベントは Slack から発火しない**（Enterprise Search + Connection Reporting でも Deno SDK External Auth でも）。

---

### 4. Bolt フレームワークのトークンローテーション

**ファイル**: `docs/tools/bolt-js/concepts/token-rotation.md`

Bolt の token rotation 機能も **Slack 自身のボット/ユーザートークン**（`xoxe.xoxb-`）のローテーションに関するもの。外部サービスの OAuth トークンとは無関係。

> "Bolt for JavaScript will rotate tokens automatically in response to incoming events so long as the built-in OAuth functionality is used."

---

### 5. 10秒制約とトークンリフレッシュのタイミング

**ファイル**: `docs/enterprise-search/developing-apps-with-search-features.md`（行 307）

Enterprise Search の search_function は **10秒以内に完了**しなければならない：

> "Your app must complete the function execution within 10 seconds."

これにより、search_function 内でのリアクティブなトークンリフレッシュ（検索中にトークン切れを検知してリフレッシュ）は時間的に危険になる。

#### 推奨設計: プロアクティブリフレッシュ（バックグラウンドジョブ）

```
[推奨パターン: プロアクティブリフレッシュ]

バックグラウンドジョブ（定期実行）:
  - expires_at が現在時刻 + 5分 以内のトークンを検索
  - 対象ユーザーのリフレッシュトークンフロー実行
  - DB の access_token と expires_at を更新

↓ search_function:
  1. DB からトークン取得
  2. トークンなし → functions.completeError（再接続案内）
  3. トークンあり → 外部 API 呼び出し（既にリフレッシュ済みで安全）
  4. 外部 API が 401 → リアクティブリフレッシュを試みる（10秒以内に収める）
  5. functions.completeSuccess / functions.completeError
```

#### リアクティブリフレッシュ（フォールバック）

10秒制約内でリフレッシュする場合のフロー:

```python
@app.event("function_executed")
def handle_search(event, client):
    # ...
    access_token = token_store.get(user_id)
    
    result = call_external_api(query, access_token)
    
    if result.status_code == 401:
        # トークン期限切れ → リフレッシュを試みる
        refresh_result = token_store.refresh(user_id)
        if not refresh_result.ok:
            # リフレッシュ失敗 → 再認証を促す
            client.apps_user_connection_update(user_id=user_id, status="disconnected")
            client.functions_completeError(
                function_execution_id=execution_id,
                error="Session expired. Please reconnect at https://..."
            )
            return
        access_token = refresh_result.new_token
        result = call_external_api(query, access_token)
    
    # 正常ケース
    client.functions_completeSuccess(...)
```

---

## 判断・意思決定

### 前提の訂正が最重要

ユーザーの質問は「Slackが保存しているOAuthトークンが更新された際に自社DBのトークンも更新する手段」を知りたいというものだったが、そのような状況は存在しない。

- Enterprise Search では Slack は外部サービスの OAuth トークンを一切管理しない
- Deno SDK External Auth では Slack がすべてを管理し、アプリ側の DB は不要

どちらのアプローチも「2つのストアの同期」は不要。

### 実際の問題は標準 OAuth2 ライフサイクル管理

Enterprise Search + Connection Reporting でアプリが直面するのは、標準的な OAuth2 トークンライフサイクル管理:
- 有効期限の管理
- リフレッシュトークンを使った自動更新
- リフレッシュ失敗時の再認証フロー

これは Slack 固有の問題ではなく、一般的な OAuth2 実装の問題。

---

## 問題・疑問点

1. **search_function でのインラインリフレッシュの時間**: リフレッシュトークンの呼び出し + 外部 API 呼び出しを 10 秒以内に収めるのは環境によっては厳しい場合がある。外部サービスの応答時間によっては実質的にプロアクティブリフレッシュ必須となる。

2. **apps.auth.external.get が Bolt アプリから呼べるか**: `apps.auth.external.get` のドキュメントに Bolt.js/Python/Java の SDK メソッドが記載されているが、これは Deno SDK の外部認証でのみ有効（`oauth2` 型パラメータとセット）なのか、Bolt アプリから独立して呼べるのかは不明。もし Bolt アプリから呼べるのであれば、Enterprise Search でも活用できる可能性がある。

---

## まとめ

### 質問への回答

「OAuthトークンを自社のDBに保存する運用ということだが、OAuthトークンを更新した時に自社DBのトークンを更新できるのか」

**前提の修正**: Enterprise Search + Connection Reporting において、Slack は外部 OAuth トークンを保存しない。自社 DB のみがトークンを持つ。

**実際の課題と解決策**:

| 課題 | 解決策 |
|---|---|
| 外部トークンの有効期限切れ検知 | DB に `expires_at` を保存し、使用前に確認 |
| トークンのリフレッシュ | 外部サービスの token endpoint に `grant_type=refresh_token` で POST |
| 10秒制約への対応 | バックグラウンドジョブでプロアクティブリフレッシュ推奨 |
| リフレッシュ失敗時（再認証必要） | `apps.user.connection.update(status: "disconnected")` + `functions.completeError` でユーザーに再接続を促す |
| Slack からの失効通知 | **存在しない**（`tokens_revoked` イベントは Slack の bot/user トークン専用） |

**参考**: Deno SDK External Auth では Slack がトークン管理・自動リフレッシュを担い、アプリは `apps.auth.external.get` を呼ぶだけで済む（ただし Enterprise Search の search_function では使用不可）。
