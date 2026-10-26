# go-service-skill

Общие скиллы Claude Code для Go-сервисов Mechta (Clean Architecture + DDD на базе
[`gotemplate`](https://github.com/rendau/gotemplate)).

| Скилл | Про что |
|---|---|
| [`crud`](skills/crud/SKILL.md) | Полный стек новой сущности: proto → domain model → domain service → repo (mobone/squirrel/pgx) → usecase → gRPC handler + DTO |
| [`golang-service`](skills/golang-service/SKILL.md) | Конвенция модулей сервисного слоя `internal/service/<module>`: фасад, порты зависимостей, транспортные модели, HTTP-клиенты внешних систем |

## Смежные скиллы

Оба скилла этого репозитория ссылаются на два внешних скилла — без них Claude не увидит правил
repo-слоя и работы с `samber/lo`. `install.sh` ставит их сам.

| Скилл | Про что | Откуда |
|---|---|---|
| `mobone` | Repo-слой на `mobone.ModelStore` — то, что `crud` использует в `repo/db/` | [`rendau/mobone`](https://github.com/rendau/mobone), папка `.claude/skills/mobone` внутри репозитория библиотеки |
| `golang-samber-lo` | Функциональные хелперы `samber/lo` — `lo.Map`/`lo.Filter` в конвертерах DTO ↔ domain | [`samber/cc-skills-golang`](https://github.com/samber/cc-skills-golang), папка `skills/golang-samber-lo` |

Из каждого репозитория скачивается только папка нужного скилла — без истории и без остальных
файлов (`git clone --depth=1 --filter=blob:none` + sparse-checkout). Из набора
`cc-skills-golang` в `~/.claude/skills` попадает один `golang-samber-lo` (без служебной папки
`evals/`), остальные скиллы samber не скачиваются и не занимают контекст агента.

## Установка

```bash
git clone https://github.com/rendau/go-service-skill.git ~/projects/go-service-skill
cd ~/projects/go-service-skill
./install.sh
```

Что делает `install.sh`:

- скиллы этого репозитория (`skills/*`) подключает симлинками в `~/.claude/skills/` — они
  доступны во всех проектах и обновляются вместе с репозиторием;
- смежные скиллы скачивает в `.external/` внутри репозитория (папка в `.gitignore`) и тоже
  подключает симлинками;
- если смежный скилл у вас уже стоит своей копией (симлинк на свой клон `mobone` или обычная
  папка) — оставляет её как есть;
- если по имени скилла этого репозитория лежит обычная папка (старая локальная копия) — не
  трогает её и просит удалить или переименовать;
- убирает симлинки на скиллы, которые из репозитория удалили.

После установки перезапустите Claude Code. Если что-то не поставилось, скрипт пишет строку
с `!!` и завершается с ошибкой.

Если каталог скиллов у вас в нестандартном месте:

```bash
CLAUDE_SKILLS_DIR=/путь/к/skills ./install.sh
```

### Только для одного проекта

Вместо глобальной установки можно подключить скиллы к конкретному репозиторию:

```bash
CLAUDE_SKILLS_DIR=/путь/к/проекту/.claude/skills ~/projects/go-service-skill/install.sh
```

## Обновление

```bash
cd ~/projects/go-service-skill && git pull && ./install.sh
```

`git pull` обновляет скиллы этого репозитория (симлинки уже указывают на него),
`./install.sh` — подтягивает свежие версии смежных скиллов и подключает новые скиллы, если они
появились. Затем перезапустите Claude Code.

## Как вносить изменения

Скиллы правятся прямо в этом репозитории (`skills/<name>/SKILL.md` и вложенные файлы),
через ветку и PR:

```bash
git checkout -b feature/my-change
# правки в skills/...
git commit -am "crud: уточнить правила фильтрации"
git push -u origin feature/my-change
```

Соглашения по содержимому:

- `SKILL.md` — фронтматтер `name` + `description`, дальше сам гайд. `name` обязан совпадать
  с именем папки.
- В `description` перечисляйте триггерные слова — по ним Claude решает, подключать ли скилл.
- Крупные разделы выносите в подпапки (`layers/`, `references/`) и ссылайтесь на них
  относительными путями из `SKILL.md` — так основной файл остаётся компактным.
- Правило должно быть проверяемым и с примером кода. Общие рассуждения без примера в скилл
  не идут.

## Структура репозитория

```
skills/
  crud/
    SKILL.md
    layers/            # proto, model, domain, repo, usecase, handler
    prompt_example.txt # пример запроса, который запускает скилл
  golang-service/
    SKILL.md
    references/        # http-client
install.sh
.external/             # смежные скиллы, скачивает install.sh (в git не попадает)
```

Чтобы добавить или поменять смежный скилл, правьте список `EXTERNALS` в начале `install.sh`:
имя скилла, git-репозиторий, путь к папке скилла в нём и подпапки, которые скачивать не нужно.
