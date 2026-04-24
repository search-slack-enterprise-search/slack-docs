# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

このリポジトリは [Slack Developer Docs](https://docs.slack.dev/) をダウンロードしたスナップショットを含む。`docs/` はタイムスタンプ付きのスナップショットディレクトリへのシンボリックリンク。

ドキュメントは Slack のデベロッパープラットフォーム全般をカバーしている。

今回の調査では特に **Enterprise Search** — Slack 内から外部データソースをリアルタイム検索できる機能 —で何ができるかに焦点をあてている。
とはいえ、実際の調査ではそれにこだわらず 検索/探索 してほしい。

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

ダウンロードスクリプトでドキュメントを再取得後、`docs` シンボリックリンクを新しいタイムスタンプ付きスナップショットディレクトリに向け直す。

## ツール使用方針

- ファイル検索には `grep` ではなく `rg` (ripgrep)を使用すること
- ファイル探索には `find` ではなく `fd` を使用すること
- `grep -r` や `find` は使わず、常に `rg` / `fd` を使うこと
