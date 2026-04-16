#!/usr/bin/env bash
# PreToolUse hook: ホワイトリスト外のパスへのアクセスをブロック
# ホワイトリスト: .claude/path-whitelist.txt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHITELIST_FILE="$SCRIPT_DIR/../path-whitelist.txt"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# stdin からツール入力を読み込む
TOOL_INPUT=$(cat)

# パス引数を取得（ツールによってキー名が異なる）
PATH_ARG=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // .pattern // ""')

# パス引数なしの場合は許可
if [[ -z "$PATH_ARG" ]]; then
  exit 0
fi

# 絶対パスをプロジェクトルートからの相対パスに正規化
if [[ "$PATH_ARG" == "$PROJECT_DIR/"* ]]; then
  PATH_ARG="${PATH_ARG#$PROJECT_DIR/}"
elif [[ "$PATH_ARG" == "$PROJECT_DIR" ]]; then
  exit 0
fi

# 先頭の ./ を除去
PATH_ARG="${PATH_ARG#./}"

# ホワイトリストファイルが存在しない場合は許可（フェイルオープン）
if [[ ! -f "$WHITELIST_FILE" ]]; then
  exit 0
fi

# ホワイトリストと照合
while IFS= read -r allowed || [[ -n "$allowed" ]]; do
  # コメント・空行をスキップ
  [[ -z "$allowed" || "$allowed" == \#* ]] && continue
  # 末尾スラッシュを除去して比較
  allowed="${allowed%/}"

  if [[ "$PATH_ARG" == "$allowed" || "$PATH_ARG" == "$allowed/"* ]]; then
    exit 0
  fi
done < "$WHITELIST_FILE"

# ホワイトリスト外 → ブロック
echo "{\"decision\": \"deny\", \"reason\": \"Path '$PATH_ARG' is outside allowed directories. Edit .claude/path-whitelist.txt to add it.\"}"
exit 0
