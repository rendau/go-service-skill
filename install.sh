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

# --- смежные скиллы, на которые опираются crud и golang-service ------------------
# Они живут в других репозиториях, поэтому ставятся отдельно. Здесь только проверка.
missing=()

check_external() {
  local name="$1"
  local link="$TARGET_DIR/$name"

  if [ -L "$link" ] && [ ! -e "$link" ]; then
    echo "!!  $name — битый симлинк ($(readlink "$link"))"
    missing+=("$name")
  elif [ ! -e "$link" ]; then
    echo "!!  $name — не установлен"
    missing+=("$name")
  else
    echo "ok  $name (уже установлен)"
  fi
}

echo
echo "Смежные скиллы:"
check_external mobone
check_external golang-samber-lo

if [ ${#missing[@]} -gt 0 ]; then
  cat <<EOF

ВНИМАНИЕ: скиллы crud и golang-service ссылаются на mobone и golang-samber-lo.
Без них Claude не увидит правил repo-слоя (mobone.ModelStore) и работы с samber/lo.

  # mobone — скилл лежит в самом репозитории библиотеки
  git clone https://github.com/rendau/mobone.git ~/projects/mobone
  ln -s ~/projects/mobone/.claude/skills/mobone $TARGET_DIR/mobone

  # golang-samber-lo — из набора скиллов samber/cc-skills-golang
  git clone https://github.com/samber/cc-skills-golang.git ~/projects/cc-skills-golang
  ln -s ~/projects/cc-skills-golang/skills/golang-samber-lo $TARGET_DIR/golang-samber-lo
EOF
fi

echo
echo "Готово. Перезапустите Claude Code, чтобы скиллы подхватились."
