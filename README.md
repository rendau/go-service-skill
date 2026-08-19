# go-service-skill

Общие скиллы Claude Code для Go-сервисов Mechta (Clean Architecture + DDD на базе
[`gotemplate`](https://github.com/mechta-market/gotemplate)).

| Скилл | Про что |
|---|---|
| [`crud`](skills/crud/SKILL.md) | Полный стек новой сущности: proto → domain model → domain service → repo (mobone/squirrel/pgx) → usecase → gRPC handler + DTO |
| [`golang-service`](skills/golang-service/SKILL.md) | Конвенция модулей сервисного слоя `internal/service/<module>`: фасад, порты зависимостей, транспортные модели, HTTP-клиенты внешних систем |

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
и запустите скрипт ещё раз.

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
