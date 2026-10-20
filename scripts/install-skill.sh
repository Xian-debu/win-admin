#!/usr/bin/env bash
# 把 win-admin 的 SKILL.md 安装到 DSH 技能目录，让 agent 在需要操作 Windows GUI 时自动看到。
# 用法：
#   bash scripts/install-skill.sh            # 安装/更新到 ~/.dsh/skills/win-admin
#   bash scripts/install-skill.sh --dir DIR  # 指定技能根目录（默认 $DSH_SKILLS_DIR 或 ~/.dsh/skills）
#   bash scripts/install-skill.sh --remove   # 卸载
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="${DSH_SKILLS_DIR:-$HOME/.dsh/skills}"
NAME="win-admin"
REMOVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) SKILLS_DIR="$2"; shift 2 ;;
    --remove) REMOVE=1; shift ;;
    -h|--help) sed -n "2,7p" "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
TARGET="$SKILLS_DIR/$NAME"
if [ "$REMOVE" = "1" ]; then
  if [ -d "$TARGET" ]; then rm -rf "$TARGET"; echo "removed $TARGET"; else echo "not installed: $TARGET"; fi
  exit 0
fi
[ -f "$ROOT/SKILL.md" ] || { echo "missing $ROOT/SKILL.md" >&2; exit 3; }
mkdir -p "$TARGET"
cp -f "$ROOT/SKILL.md" "$TARGET/SKILL.md"
V="$(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"
printf "installed %s (win-admin %s) -> %s\n" "$NAME" "$V" "$TARGET"
echo "提示：SKILL.md 里的路径固定指向 $ROOT；迁移仓库后需重跑本脚本。"
