# go-service-skill

Общие скиллы Claude Code для Go-сервисов Mechta (Clean Architecture + DDD на базе
[`gotemplate`](https://github.com/mechta-market/gotemplate)).

| Скилл | Про что |
|---|---|
| [`crud`](skills/crud/SKILL.md) | Полный стек новой сущности: proto → domain model → domain service → repo (mobone/squirrel/pgx) → usecase → gRPC handler + DTO |
| [`golang-service`](skills/golang-service/SKILL.md) | Конвенция модулей сервисного слоя `internal/service/<module>`: фасад, порты зависимостей, транспортные модели, HTTP-клиенты внешних систем |

## Смежные скиллы

Оба скилла этого репозитория ссылаются на два внешних скилла — поставьте и их, иначе Claude
не увидит правил repo-слоя и работы с `samber/lo`.

| Скилл | Про что | Откуда |
|---|---|---|
| `mobone` | Repo-слой на `mobone.ModelStore` — то, что `crud` использует в `repo/pg/` | [`mechta-market/mobone`](https://github.com/mechta-market/mobone), скилл лежит внутри репозитория библиотеки в `.claude/skills/mobone` |
| `golang-samber-lo` | Функциональные хелперы `samber/lo` — `lo.Map`/`lo.Filter` в конвертерах DTO ↔ domain | [`samber/cc-skills-golang`](https://github.com/samber/cc-skills-golang), скилл в `skills/golang-samber-lo` |

```bash
git clone git@github.com:mechta-market/mobone.git ~/projects/mobone
ln -s ~/projects/mobone/.claude/skills/mobone ~/.claude/skills/mobone

git clone https://github.com/samber/cc-skills-golang.git ~/projects/cc-skills-golang
ln -s ~/projects/cc-skills-golang/skills/golang-samber-lo ~/.claude/skills/golang-samber-lo
```

`install.sh` эти скиллы не ставит (они не наши), но проверяет их наличие и печатает
эти же команды, если чего-то не хватает.

## Установка

```bash
git clone git@github.com:mechta-market/go-service-skill.git ~/projects/go-service-skill
cd ~/projects/go-service-skill
./install.sh
```

`install.sh` создаёт симлинки на `skills/*` в `~/.claude/skills/`, поэтому скиллы доступны
во всех проектах. После установки перезапустите Claude Code.

Если каталог скиллов у вас в нестандартном месте:

```bash
CLAUDE_SKILLS_DIR=/путь/к/skills ./install.sh
```

Скрипт идемпотентен: повторный запуск обновляет симлинки. Если по имени скилла уже лежит
обычная папка (старая локальная копия), скрипт её не тронет — удалите или переименуйте её сами
и запустите скрипт ещё раз. В конце скрипт проверяет [смежные скиллы](#смежные-скиллы)
`mobone` и `golang-samber-lo` и подсказывает команды установки, если их нет.

### Только для одного проекта

Вместо глобальной установки можно подключить скиллы к конкретному репозиторию:

```bash
ln -s ~/projects/go-service-skill/skills/crud .claude/skills/crud
ln -s ~/projects/go-service-skill/skills/golang-service .claude/skills/golang-service
```

## Обновление

```bash
cd ~/projects/go-service-skill && git pull
```

Симлинки уже указывают на репозиторий — после `git pull` и перезапуска Claude Code
у вас актуальная версия. Заново запускать `install.sh` нужно только если в репозитории
появился новый скилл.

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
```
