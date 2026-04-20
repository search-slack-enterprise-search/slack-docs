# Enterprise Search における 3 秒以内 ack の必要性
## 知りたいこと

Enterprise Searchにおいて、3秒以内のackは必要かどうか

## 目的

Enterprise SearchはEvent Subscriptionの一部として実装されている。Event Subscriptionを利用したものでは3秒以内にackを返す必要なものが多い。Enterprise Searchでも必要か。

## 調査サマリー

**Enterprise Search の `function_executed` イベントには、デフォルトで 3 秒以内の ack ルールが適用される。ただし、Enterprise Search では通常とは逆に「処理完了 → ack」の同期パターンが必須のため、Bolt フレームワークで ack タイムアウトを 10 秒に延長して対応する。**

### 標準 Events API ルール

- Events API 全体: 3 秒以内に HTTP 2xx を返さないと `http_timeout` として失敗扱いになり最大 3 回リトライされる
- Bolt Python/JS とも: デフォルト 3 秒以内に `ack()` を呼ぶよう推奨

### Enterprise Search 固有の要件（`developing-apps-with-search-features.md`）

- `function_executed` イベントを**同期的**に処理する必要がある
  - 通常: 「先に ack → 後で処理」
  - Enterprise Search: **「先に処理完了（`functions.completeSuccess`/`functions.completeError`）→ その後 ack」**（逆順）
- 関数実行の完了 + ack は **10 秒以内**に行う必要がある

### フレームワーク別の対応

| フレームワーク | 設定 | 内容 |
|---|---|---|
| Bolt Python | `auto_acknowledge=False` + `ack_timeout=10` | ack タイムアウトを 3 秒 → 10 秒に延長 |
| Bolt JS | `auto_acknowledge=False` | デフォルト 3 秒以内か Socket Mode で対応 |

### 残る疑問点

- Bolt JS では `ack_timeout` パラメータが言及されておらず、HTTP モードで 10 秒を超える検索処理が必要な場合の対応が不明
- HTTP 直接実装（非 Bolt）での 10 秒 ack タイムアウト実現方法は言及なし

## 完了サマリー

Enterprise Search の ack に関して:
- **3 秒ルールはデフォルトで適用される**（Events API 標準）
- **ただし実運用では 10 秒に延長が推奨**（Bolt Python: `ack_timeout=10`、Bolt JS: Socket Mode または 3 秒以内で完了）
- Enterprise Search は「処理完了 → ack」という同期パターンが必須であり、これを実現するために ack タイムアウトの延長または Socket Mode が必要
