# Enterprise Search が Bolt の Python と Node 専用機能である理由

## 知りたいこと

Enterprise Search が Bolt の Python と Node 専用機能である理由

## 目的

Event Subscription で動かせる以上、Web API を実装すれば動くように思えるため。Bolt 専用とされる根拠や制約を明確にする。

## 調査サマリー

「Bolt 専用」と言われる理由は2層構造:

1. **公式ドキュメントの明示**: `developing-apps-with-search-features.md` に "You can implement Enterprise Search using the Bolt framework for Node or Python" と明記されている
2. **マニフェスト制約**: `app_type: "remote"` + `function_runtime: "remote"` は Bolt をターゲットとした設定。Deno SDK（ROSI）は `app_type: "slack"` のみ対応するため技術的に実装不可

**ただし技術的には Bolt 専用ではない**:
- Event Subscription（HTTP POST）は任意の HTTP サーバーで受信可能
- `functions.completeSuccess` などの Web API は標準 HTTP で任意言語から呼び出し可能
- 「Web API を実装すれば動く」というユーザーの仮説は技術的に正しい

実務的には公式サンプル・ドキュメントがすべて Bolt (Python/Node) を前提とするため事実上の標準になっているが、Bolt 以外での実装も原理的には可能。

## 完了サマリー

- 調査日: 2026-04-17
- 結論: 「Bolt 専用」は公式ドキュメントの表記とマニフェスト設定に由来。技術的には任意の HTTP 実装で動作可能
- ログ: `logs/0040_enterprise-search-bolt-only-reason.md`
