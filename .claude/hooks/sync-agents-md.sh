#!/usr/bin/env bash
# CLAUDE.md から AGENTS.md を生成する同期スクリプト
# PostToolUse hook (Edit/Write) として使用
# CLAUDE.md の内容を Codex 向けに変換して AGENTS.md に書き出す

set -euo pipefail

CLAUDE_MD="CLAUDE.md"
AGENTS_MD="AGENTS.md"

if [ ! -f "$CLAUDE_MD" ]; then
    exit 0
fi

# CLAUDE.md を変換して AGENTS.md 相当の内容を生成
new_content=$(
    awk '/^## Kanban ワークフロー/{exit} {print}' "$CLAUDE_MD" \
    | sed 's/^# CLAUDE\.md$/# AGENTS.md/' \
    | sed 's/This file provides guidance to Claude Code (claude\.ai\/code)/This file provides guidance to AI coding agents/' \
    | sed -e 's/[[:space:]]*$//' \
    | awk '
        /[^[:space:]]/ { blank=0; print; next }
        blank < 1      { blank++; print }
    '
)

# 現在の内容と比較し、差分があれば上書き
if [ -f "$AGENTS_MD" ]; then
    current_content=$(cat "$AGENTS_MD")
    if [ "$new_content" = "$current_content" ]; then
        exit 0
    fi
fi

printf '%s\n' "$new_content" > "$AGENTS_MD"
echo "[sync-agents-md] AGENTS.md を更新しました"
