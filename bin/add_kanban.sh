#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $(basename "$0") <title>" >&2
    exit 1
fi

title="$1"
kanban_dir="$(cd "$(dirname "$0")/.." && pwd)/kanban"

# 既存ファイルから最大番号を取得
max_num=-1
for f in "$kanban_dir"/[0-9][0-9][0-9][0-9]_*.md; do
    [ -e "$f" ] || continue
    num="${f##*/}"
    num="${num%%_*}"
    num=$((10#$num))
    if [ "$num" -gt "$max_num" ]; then
        max_num="$num"
    fi
done

next_num=$((max_num + 1))
padded=$(printf "%04d" "$next_num")
filename="${kanban_dir}/${padded}_${title}.md"

cat > "$filename" <<EOF
# ${title}
## 知りたいこと

## 目的

EOF
echo "Created: $filename"
