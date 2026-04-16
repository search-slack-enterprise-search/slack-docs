#!/usr/bin/env bash
# kanban 未完了タスクチェック
# UserPromptSubmit hook として使用
# 未完了タスクがある場合はリマインドメッセージを stdout に出力し、Claude のコンテキストに挿入される

KANBAN_DIR="kanban"

if [ ! -d "$KANBAN_DIR" ]; then
    exit 0
fi

incomplete=()
for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue
    if ! grep -q "## 完了サマリー" "$f"; then
        incomplete+=("$(basename "$f")")
    fi
done

if [ ${#incomplete[@]} -gt 0 ]; then
    echo "[kanban reminder] 未完了タスクがあります: ${incomplete[*]}"
    echo "作業が進んだら logs/ のログファイルへ記録し、完了時は kanban ファイルへ完了サマリーを追記してください。"
fi
