# Enterprise Search 有効化方法

## 知りたいこと

Enterprise Searchの有効化について

## 目的

Enterprise SearchではAppを入れただけでは使用できないと聞いた。どうやって有効化するかを知りたい。

## 調査サマリー

Enterprise Search の有効化は **4つのステップ**が必要で、それぞれ異なる担当者が作業する。

### ステップ 1：開発者による App 設定
- App マニフェストの `features.search` に `search_function_callback_id` を追加
- `org_deploy_enabled: true` でオーグ対応を宣言
- `function_executed` イベントを購読
- 検索結果を返すカスタムステップ関数を実装

### ステップ 2：App のオーグレベルインストール（Org Admin）
- API の設定 UI / OAuth フロー / Slack CLI のいずれかでインストール
- **この時点ではどのワークスペースでも使えない**（自動追加なし）

### ステップ 3：ワークスペースへの App 追加（Org Admin）
- 管理ダッシュボード（`app.slack.com/manage/<enterprise-id>`）→ Integrations → Installed apps → 対象 App の「Add to more workspaces」
- 複数ワークスペースへの一括追加が可能

### ステップ 4：エンドユーザーへの有効化（Org Admin）
- ワークスペース追加後も **デフォルトでエンドユーザーには非表示**
- Org Admin が Slack ヘルプ記事の手順に従って有効化操作を実施
  - 参照: https://slack.com/help/articles/39044407124755-Set-up-and-manage-Slack-enterprise-search

### 補足
- エンドユーザーは個別にアプリを無効化することも可能
- 具体的なエンドユーザー有効化の手順はドキュメントスナップショット外（Slack ヘルプ記事）

## 完了サマリー

「App を入れただけでは使えない」理由は3段階ある：
1. オーグレベルにインストールしても、ワークスペースには自動追加されない（Org Admin の手動操作が必要）
2. ワークスペースに追加しても、エンドユーザーにはデフォルトで非表示（Org Admin の有効化操作が必要）
3. そもそも開発者側で App マニフェストへの設定が必要

ログ: `logs/0022_enterprise-search-activation.md`
