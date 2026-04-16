# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## 概要

このディレクトリはダウンロードされた Slack 開発者ドキュメントのスナップショットを含む。`docs/` はタイムスタンプ付きのスナップショットディレクトリ (`../../02_scripts/download_slack_docs/docs/` 以下) へのシンボリックリンク。

ドキュメントは Slack のデベロッパープラットフォーム全般をカバーしており、特に **Enterprise Search** — Slack 内から外部データソースをリアルタイム検索できる機能 — に焦点を当てている。

## ドキュメント構成

`docs/` 以下の主要ディレクトリ:

- `enterprise-search/` — Enterprise Search の中核ドキュメント（概要・アプリ開発・接続レポート・アクセス制御）
- `apis/web-api/` — リアルタイム検索 API を含む Web API リファレンス
- `apis/events-api/` — Events API リファレンス
- `authentication/` — アプリ認証・トークン種別
- `messaging/` — メッセージングと Work Objects（Work Objects は Enterprise Search をサポート）
- `reference/` — Block Kit リファレンス・マニフェストスキーマなど
- `ja-jp/` — ドキュメントの日本語訳

## Enterprise Search の重要事項

- Enterprise Search アプリは Slack Marketplace への公開・配布**不可**
- アプリはオーグ対応（org-ready）である必要がある（オーグレベルでインストール、ワークスペースへのアクセス許可が必要）
- 外部データソース（Wiki・独自システムなど）を Slack 検索に統合する機能
- 主要ドキュメント: `enterprise-search/developing-apps-with-search-features.md`、`enterprise-search/connection-reporting.md`、`enterprise-search/enterprise-search-access-control.md`

## `/kanban` によるドキュメント調査

ドキュメントの調査タスクは `/kanban` スキルで管理する。`kanban/` にタスクファイルを作成し、`/kanban` を実行すると、調査→ログ記録の流れで進む。

- タスクファイルの形式・命名規則: `~/.claude/skills/kanban/references/kanban-workflow.md` を参照
- 調査結果は `logs/` に詳細ログとして記録される
- Enterprise Search が主な調査対象だが、関連するドキュメント（Work Objects・認証・Web API など）も調査範囲に含む

## ドキュメントスナップショットの更新

ダウンロードスクリプトは `../../02_scripts/download_slack_docs/` にある。再実行後、`docs` シンボリックリンクを新しいタイムスタンプ付きスナップショットディレクトリに向け直す。
