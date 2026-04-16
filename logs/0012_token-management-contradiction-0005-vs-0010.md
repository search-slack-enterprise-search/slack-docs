# 0005番と0010番のトークン保持・管理に関する矛盾の解消 調査ログ

## タスク概要

- **kanban ファイル**: `kanban/0012_token-management-contradiction-0005-vs-0010.md`
- **知りたいこと**: 0005番と0010番のカンバンで「Slack がトークンを保持する」という記述が矛盾している。どちらが正しいのか？
- **目的**: 回答の矛盾を解消し、正しく理解したい
- **調査日**: 2026-04-16

---

## 調査ファイル一覧

| ファイルパス | 内容 |
|---|---|
| `kanban/0005_external-auth-slack-ui-flow.md` | 0005番 kanban（Deno SDK External Auth の調査） |
| `kanban/0010_oauth-token-refresh-in-own-db.md` | 0010番 kanban（Enterprise Search トークン更新の調査） |
| `logs/0005_external-auth-slack-ui-flow.md` | 0005番 詳細ログ |
| `logs/0010_oauth-token-refresh-in-own-db.md` | 0010番 詳細ログ |
| `docs/enterprise-search/developing-apps-with-search-features.md` | Enterprise Search 実装ガイド（Bolt 使用の明示） |
| `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md` | Deno SDK 外部認証ガイド（Slack トークン管理） |
| `docs/reference/methods/apps.auth.external.get.md` | apps.auth.external.get API リファレンス |

---

## 調査アプローチ

1. 0005番と0010番の kanban・ログファイルを読み込み、矛盾箇所を特定する
2. Enterprise Search のドキュメントで「どのフレームワークを使うか」を確認する
3. Deno SDK External Auth のドキュメントで「どのランタイムを対象とするか」を確認する
4. `apps.auth.external.get` API のドキュメントで Bolt から呼べるか確認する

---

## 調査結果

### 1. 矛盾とされている2つの記述

#### 0005番（`kanban/0005_external-auth-slack-ui-flow.md`）の記述

**完了サマリー（kanban ファイル行49-51）**:
> "Slack がトークンを保存し、以降のワークフロー実行で使用される"

詳細ログ（`logs/0005_external-auth-slack-ui-flow.md` 行79）:
> "Slack がトークンを保存し、以降のワークフロー実行で使用される"
> "エンドユーザーは Slack CLI を使う必要がない"

この調査は **`credential_source: "END_USER"` を使う Deno SDK の外部認証（External Authentication）** の話。

#### 0010番（`kanban/0010_oauth-token-refresh-in-own-db.md`）の記述

**調査サマリー（kanban ファイル行12-23）**:
> "Enterprise Search + Connection Reporting と Deno SDK External Auth では、トークンストアが1つしか存在しない"
> "Enterprise Search + Connection Reporting（Bolt）: アプリ独自 DB のみ（Slack はトークンを持たない）"

この調査は **Enterprise Search + Connection Reporting（Bolt アプリ）** のトークン管理の話。

---

### 2. 矛盾の原因：2つの異なるアーキテクチャ

**これは矛盾ではない。** 0005番と0010番は**異なるアーキテクチャ**について話しているため、トークン管理の主体が異なる。

| | 0005番（Deno SDK External Auth） | 0010番（Enterprise Search + Bolt） |
|---|---|---|
| **フレームワーク** | Deno SDK（deno-slack-sdk） | Bolt for Node / Python |
| **ランタイム** | ROSI（Run on Slack Infrastructure） | Remote アプリ |
| **app_type** | `slack`（Slack ホスティング） | `remote` |
| **function_runtime** | `slack`（暗黙） | `remote` |
| **トークン管理者** | **Slack** | **アプリ独自 DB** |
| **`credential_source`** | 使用可（`END_USER` / `DEVELOPER`） | 使用不可 |

---

### 3. Enterprise Search は Bolt（Remote アプリ）専用

**ソース**: `docs/enterprise-search/developing-apps-with-search-features.md`（行 46、309-311）

アプリマニフェストの設定:
```json
"settings": {
  "org_deploy_enabled": true,
  "app_type": "remote",
  "function_runtime": "remote"
}
```

実装セクションの記述（行 309-311）:
> "## Implementing Enterprise Search using Bolt {#implement-search}"
> "You can implement Enterprise Search using the Bolt framework for Node or Python."

**重要**: Enterprise Search は `app_type: "remote"` かつ `function_runtime: "remote"` の Remote アプリ（Bolt アプリ）として実装する。Deno SDK（ROSI）では実装できない。

---

### 4. Deno SDK External Auth は ROSI 専用

**ソース**: `docs/tools/deno-slack-sdk/guides/integrating-with-services-requiring-external-authentication.md` 冒頭

> "Workflow apps require a paid plan"
> "You can use the Slack CLI to encrypt and to store OAuth2 credentials."

このドキュメント全体を通じて「Deno SDK」「custom functions」「workflows」という ROSI 固有の概念を前提としている。`credential_source` も `Schema.slack.types.oauth2` 型も Deno SDK 専用の機能である。

---

### 5. `apps.auth.external.get` の Bolt からの利用可否

**ソース**: `docs/reference/methods/apps.auth.external.get.md`

このAPIは技術的には Bolt（JavaScript/Python/Java）から呼び出せる:
```
app.client.apps.auth.external.get  // Bolt JS
app.client.apps_auth_external_get  // Bolt Python
```

しかし、`external_token_id` パラメータは **Deno SDK External Auth 機能でのみ作成される** トークンの ID である。Enterprise Search + Connection Reporting では `external_token_id` が存在しないため、このAPIは実質的に使用できない。

ドキュメント（行 78-84）のコード例も Deno SDK（`deno-simple-survey` サンプルアプリ）のもののみ参照されている:
> "The following example code snippet is from a custom function defined within the Deno simple survey sample app"
> "For more code examples, refer to External authentication → /tools/deno-slack-sdk/..."

---

### 6. 矛盾解消のまとめ

```
[0005番が話していること]
Deno SDK External Auth（ROSI）
  ├── credential_source: "END_USER" を設定
  ├── ユーザーが Link Trigger をクリック
  ├── OAuth2 フローを完了
  └── → Slack がトークンを保存・管理（✓ Slack がトークンを持つ）

[0010番が話していること]
Enterprise Search + Connection Reporting（Bolt Remote App）
  ├── function_runtime: "remote"
  ├── Bolt for Node/Python で実装
  ├── Connection Reporting で OAuth フロー管理
  └── → アプリ独自 DB がトークンを保存・管理（✓ Slack はトークンを持たない）

[2つは別のアーキテクチャ]
Enterprise Search を実装する場合は必ず Bolt（Remote App）を使う
→ 0010番の結論（アプリ独自 DB でトークン管理）が Enterprise Search に適用される
→ 0005番（Deno SDK External Auth）は Enterprise Search では使えない
```

---

## 判断・意思決定

### 矛盾ではなく「文脈（アーキテクチャ）の違い」

0005番と0010番の記述は一見矛盾しているが、実際には異なるアーキテクチャについて話していた。どちらも正しい記述である。

- **Deno SDK External Auth（ROSI）** → Slack がトークンを管理する
- **Enterprise Search + Connection Reporting（Bolt Remote App）** → アプリ独自 DB がトークンを管理する

これらは排他的な選択肢であり、2つを組み合わせることはできない（Enterprise Search は Bolt Remote アプリ専用）。

### Enterprise Search を実装する場合の正解

**0010番の結論が正しく適用される**:
- Slack は外部 OAuth トークンを管理しない
- アプリ独自 DB でトークンを管理する
- 標準 OAuth2 リフレッシュフローをアプリが独自実装する

### 0005番の「Slack がトークンを保存する」は何の話か

**Deno SDK External Auth（ROSI）の話**。Deno SDK を使ったワークフローアプリで `credential_source: "END_USER"` を使う場合、Slack がトークンを管理する。ただしこれは Enterprise Search とは無関係の機能。

---

## 問題・疑問点

1. **Enterprise Search を Deno SDK で実装できるか未確認**: ドキュメントでは「Bolt for Node or Python」と明記されているが、Deno SDK で Enterprise Search を実装する方法の記載がない（存在しない可能性が高い）。別途確認が必要な場合は新タスクを作成すること。

2. **`apps.auth.external.get` を Bolt + Enterprise Search で使えるか**: `external_token_id` は Deno SDK External Auth でしか作成できないため、Enterprise Search では実質的に使えないが、技術的に「ゼロではない」可能性は調査できていない。
