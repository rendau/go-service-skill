#!/usr/bin/env bash
# Устанавливает скиллы этого репозитория в ~/.claude/skills через симлинки.
# Повторный запуск безопасен: существующие симлинки обновляются.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

mkdir -p "$TARGET_DIR"

for skill_path in "$REPO_DIR"/skills/*/; do
  skill_name="$(basename "$skill_path")"
  link="$TARGET_DIR/$skill_name"

  if [ -L "$link" ]; then
    rm "$link"
  elif [ -e "$link" ]; then
    echo "!! $link существует и не является симлинком — пропускаю."
    echo "   Удалите или переименуйте его вручную и запустите скрипт снова."
    continue
  fi

  ln -s "${skill_path%/}" "$link"
  echo "ok  $skill_name -> ${skill_path%/}"
done

echo
echo "Готово. Перезапустите Claude Code, чтобы скиллы подхватились."
