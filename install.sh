#!/usr/bin/env bash
# Устанавливает скиллы в ~/.claude/skills через симлинки.
#   - свои скиллы (skills/*) — симлинк на папку этого репозитория: обновляются через git pull;
#   - смежные скиллы из чужих репозиториев (mobone, golang-samber-lo) — скачиваются в .external/
#     только нужной папкой (shallow + sparse, без истории и остальных файлов репозитория) и тоже
#     подключаются симлинком. Повторный запуск подтягивает их свежую версию.
# Повторный запуск безопасен: существующие симлинки обновляются, чужие папки не трогаются.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
EXTERNAL_DIR="$REPO_DIR/.external"

# имя скилла | git-репозиторий | папка скилла в репозитории | что из папки не скачивать
EXTERNALS=(
  "mobone|https://github.com/rendau/mobone.git|.claude/skills/mobone|"
  "golang-samber-lo|https://github.com/samber/cc-skills-golang.git|skills/golang-samber-lo|evals"
)

mkdir -p "$TARGET_DIR"
failed=0

# link_skill <имя> <папка скилла>: ставит симлинк, если на его месте нет обычной папки.
link_skill() {
  local name="$1" src="$2" link="$TARGET_DIR/$1"

  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "!!  $name: $link существует и не является симлинком — пропускаю."
    echo "    Удалите или переименуйте его вручную и запустите скрипт снова."
    return 1
  fi

  ln -sfn "$src" "$link"
  echo "ok  $name -> $src"
}

# fetch_external <имя> <url> <путь> <исключения>: скачивает или обновляет одну папку репозитория.
fetch_external() {
  local name="$1" url="$2" path="$3" excludes="$4" dir="$EXTERNAL_DIR/$1"
  local patterns=("/$path/") ex

  for ex in $excludes; do
    patterns+=("!/$path/$ex/")
  done

  # только собственный .git папки: иначе git -C поднимется в этот репозиторий и сбросит его
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    mkdir -p "$EXTERNAL_DIR"
    git clone --quiet --depth=1 --filter=blob:none --no-checkout "$url" "$dir" || return 1
    git -C "$dir" sparse-checkout set --no-cone "${patterns[@]}"
    git -C "$dir" checkout --quiet
  else
    git -C "$dir" remote set-url origin "$url"
    git -C "$dir" sparse-checkout set --no-cone "${patterns[@]}"
    if git -C "$dir" fetch --quiet --depth=1 origin HEAD; then
      git -C "$dir" reset --quiet --hard FETCH_HEAD
    else
      echo "!!  $name: не удалось обновить из $url — оставляю скачанную ранее версию."
    fi
  fi

  [ -f "$dir/$path/SKILL.md" ]
}

echo "Скиллы репозитория:"
for skill_path in "$REPO_DIR"/skills/*/; do
  link_skill "$(basename "$skill_path")" "${skill_path%/}" || failed=1
done

# симлинки на скиллы, которые из репозитория удалили или переименовали
for link in "$TARGET_DIR"/*; do
  if [ -L "$link" ] && [ ! -e "$link" ] && [[ "$(readlink "$link")" == "$REPO_DIR"/* ]]; then
    rm "$link"
    echo "--  $(basename "$link") — удалён из репозитория, симлинк убран"
  fi
done

echo
echo "Смежные скиллы (на них ссылаются crud и golang-service):"
for entry in "${EXTERNALS[@]}"; do
  IFS='|' read -r name url path excludes <<<"$entry"
  link="$TARGET_DIR/$name"
  managed="$EXTERNAL_DIR/$name/$path"

  # скилл уже подключён симлинком на другую рабочую копию (например, свой клон mobone) — не трогаем
  if [ -L "$link" ] && [ -e "$link" ] && [ "$(readlink "$link")" != "$managed" ]; then
    echo "ok  $name -> $(readlink "$link") (своя копия, не трогаю)"
    continue
  fi
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "ok  $name — обычная папка в $TARGET_DIR (своя копия, не трогаю)"
    continue
  fi

  if fetch_external "$name" "$url" "$path" "$excludes"; then
    link_skill "$name" "$managed" || failed=1
  else
    echo "!!  $name: не удалось скачать $path из $url — без него Claude не увидит его правил."
    failed=1
  fi
done

echo
if [ "$failed" -ne 0 ]; then
  echo "Установлено не всё — см. строки с !! выше, исправьте и запустите скрипт снова."
  exit 1
fi
echo "Готово. Перезапустите Claude Code, чтобы скиллы подхватились."
