# 0005番と0010番のトークン保持・管理に関する矛盾の解消

## 知りたいこと

0005番のカンバンではSlackがトークンを保持するとある。
0010番のカンバンで言っていることと矛盾している。
トークンを保持するのなら、どこかのタイミングで更新がされているはずだし、失効時にはリフレッシュなりしているはず。

## 目的

回答の矛盾があり、理解ができない。
この矛盾を解消したい。

---

## 調査サマリー

### 結論：矛盾ではなく「アーキテクチャの違い」

**0005番と0010番は異なるアーキテクチャについて話していたため、トークン管理の主体が異なって見えていた。どちらも正しい記述。**

| | 0005番（Deno SDK External Auth） | 0010番（Enterprise Search + Bolt） |
|---|---|---|
| **フレームワーク** | Deno SDK（deno-slack-sdk） | Bolt for Node / Python |
| **ランタイム** | ROSI（Slack ホスティング） | Remote アプリ |
| **トークン管理者** | **Slack** | **アプリ独自 DB** |

### Enterprise Search は Bolt（Remote アプリ）専用

`docs/enterprise-search/developing-apps-with-search-features.md` に明記:

```json
"app_type": "remote",
"function_runtime": "remote"
```

> "You can implement Enterprise Search using the Bolt framework for Node or Python."

Enterprise Search は必ず Bolt Remote アプリとして実装する。Deno SDK（ROSI）では実装できない。

### 各アーキテクチャのトークン管理

**Deno SDK External Auth（ROSI）**:
- `credential_source: "END_USER"` を設定すると、ユーザーが Link Trigger から OAuth2 フローを完了
- **Slack がトークンを保存・管理**（`apps.auth.external.get` で取得）

**Enterprise Search + Connection Reporting（Bolt Remote App）**:
- Connection Reporting でユーザーの認証フローを管理
- **アプリ独自 DB がトークンを保存・管理**（Slack は外部 OAuth トークンを持たない）

### Enterprise Search に適用すべきなのは 0010番の結論

- Slack は外部 OAuth トークンを管理しない
- アプリ独自 DB でトークンを管理する
- 標準 OAuth2 リフレッシュフローをアプリが独自実装する

---

## 完了サマリー

- **調査日**: 2026-04-16
- **ログファイル**: `logs/0012_token-management-contradiction-0005-vs-0010.md`
- **結論**: 0005番（Deno SDK External Auth）と0010番（Enterprise Search + Bolt）は異なるアーキテクチャの話であり矛盾ではない。Enterprise Search は Bolt Remote アプリとして実装するため、「アプリ独自 DB がトークンを管理する」という0010番の結論が正しく適用される。Deno SDK External Auth（Slack がトークンを管理）は Enterprise Search では使えない。
