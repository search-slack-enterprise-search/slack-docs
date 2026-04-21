# Managing Organization-Ready Apps について

## 知りたいこと

`Managing organization-ready apps` について詳しく知りたい。

## 目的

Enterprise Search も Organization Level のものであるため

## 調査サマリー

### org-ready アプリとは

- オーグレベルでインストールされる（ワークスペースへは自動追加されない）
- Org Admin が管理ダッシュボードから個別にワークスペースへ追加
- ワークスペースレベルのアプリと比べて追加の権限はない
- 単一の org-wide ボットトークンで複数ワークスペースを操作

### org-ready 化の手順（開発者）

1. app settings で Bot スコープを追加（例: `team:read`）
2. **Org Level Apps** → **Opt-In**
3. manifest.json に `"org_deploy_enabled": true` が反映される
4. Org Admin をコラボレーターに追加
5. Org Admin が承認・インストール後にワークスペースへ追加

### Enterprise Search との関係

- Enterprise Search アプリは org-ready 必須（`org_deploy_enabled: true`）
- オーグにインストール後、1つ以上のワークスペースへのアクセスが必要

### API 利用時の注意

- org トークンで一部 API（`conversations.list`、`users.list` など 21 種類）は `team_id` パラメータが必須
- `team_access_granted` / `team_access_revoked` イベントでワークスペースアクセス変化を把握
- `auth.teams.list` でアプリが承認済みのワークスペース一覧を取得

### Bolt 対応バージョン

- Bolt for Python: 1.1.0+
- Bolt for JavaScript: 3.0.0+
- Bolt for Java: 1.4.0+

## 完了サマリー

Managing organization-ready apps の全ドキュメントを調査。Enterprise Search は org-ready が必須で、Org Admin によるオーグレベルインストール → ワークスペース追加という2段階のフローが必要。org トークン利用時は `team_id` パラメータが必要な API に注意が必要。
