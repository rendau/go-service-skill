---
name: crud
description: >
  Go CRUD полный стек (proto → model → domain service → repo → usecase → handler) для проектов на
  Clean Architecture + DDD с mobone/squirrel/pgx + gRPC/grpc-gateway.
  Используй этот скилл ВСЕГДА когда задача касается: создания новой сущности, написания CRUD-метода
  (List, Get, Create, Update, Delete), добавления доменной сущности, написания repo/db/model
  (select.go, upsert.go), работы с mobone.ModelStore, фильтрации через getConditions,
  bulk-операций через squirrel, трассировки методов репозитория, wrapping ошибок, usecase-слоя,
  gRPC handler + DTO, proto-контракта сущности (api/proto/).
  Триггерные слова: repo, repository, репозиторий, CRUD, mobone, ModelStore, ListReq, Select,
  Upsert, getConditions, squirrel, repo.go, upsert.go, select.go, domain service, RepoDbI,
  usecase, handler, DTO, proto, entity, сущность, grpc, gateway, api/proto.
---

# CRUD — полный стек новой сущности

Детальные паттерны по слоям — в отдельных файлах:
- `layers/proto.md` — Proto Contract (api/proto/)
- `layers/model.md` — Domain Model
- `layers/domain.md` — Domain Service
- `layers/repo.md` — Repository (repo/db/)
- `layers/usecase.md` — Usecase
- `layers/handler.md` — gRPC Handler + DTO

Плейсхолдеры в шаблонах: `<Entity>` — имя сущности в PascalCase (`Category`), `<entity>` — в нижнем
регистре (`category`), `<idType>` — тип PK (`int64` или `string`, одинаково в Go и proto),
`<zeroId>` — его zero value (`0` или `""`), `<module>` — `owner/repo` Go-модуля,
`<svc_name>` — имя сервиса (`<svc_name>_v1` — proto-пакет).

---

## Библиотеки

| Назначение | Библиотека |
|---|---|
| Основной CRUD поверх pgx | `github.com/rendau/mobone/v2` |
| Сложные/кастомные запросы | `github.com/Masterminds/squirrel` |
| Прямой доступ к БД | `github.com/jackc/pgx/v5` |
| Хелперы (маппинг, указатели) | `github.com/samber/lo` |

Go 1.26+: указатель на значение — `new(expr)` (`new(time.Now())`).

---

## Перед реализацией — уточни

### 1. Транспорт: нужен ли gRPC, нужен ли HTTP

Не каждому сервису нужны оба. Определи по проекту, а если по коду не ясно — спроси программиста.

Где смотреть: `internal/app/app.go` (есть ли `NewGrpcServer` с регистрациями, есть ли HTTP-gateway
`GrpcGatewayCreateHandler` с `Register...Handler`), соседние `.proto` (есть ли `google.api.http`),
кто клиенты сервиса (фронт ходит по REST, другие сервисы — по gRPC).

| Нужно | proto | `app.go` |
|---|---|---|
| gRPC + HTTP (по умолчанию в gotemplate) | `option (google.api.http)` у каждого RPC | `Register<Entity>ServiceServer` **и** `Register<Entity>ServiceHandler` |
| только gRPC | без `google.api.http` и без `import "google/api/annotations.proto"` — тогда `<entity>.pb.gw.go` не генерируется, а в swagger нет путей | только `Register<Entity>ServiceServer` |
| только HTTP | как gRPC + HTTP: в gotemplate HTTP-gateway проксирует запросы в gRPC-сервер по `localhost`, поэтому регистрация в gRPC-сервере нужна всё равно | обе регистрации; закрыть ли gRPC-порт снаружи — вопрос деплоя |

### 2. PK: кто задаёт id

По умолчанию id генерирует БД: `bigserial`. Если в задаче не сказано иначе, но по смыслу сущности
подходит другой вариант (код-справочник, внешний идентификатор, импорт) — **спроси программиста и
предложи подходящий кейс**:

| Кейс | Колонка | `<idType>` | `id` в `<Entity>CreateReq` | `Edit.Id` / `Upsert.Id` | usecase при Create |
|---|---|---|---|---|---|
| 1. По умолчанию: генерирует БД | `id bigserial primary key` | `int64` | нет | нет | — |
| 2. uuid генерирует БД | `id uuid primary key default gen_random_uuid()` | `string` | нет | нет | — |
| 3. text из запроса | `id text primary key` | `string` | `optional string id` | есть | требует id |
| 4. int без sequence, из запроса | `id bigint primary key` | `int64` | `optional int64 id` | есть | требует id |
| 5. из запроса или DB-default | `uuid ... default gen_random_uuid()` (или с sequence) | по колонке | `optional <idType> id` | есть | не требует |

Механика кейсов 3–5 одна: `id` из запроса → `Edit.Id` → попадает в `CreateColumnMap`, если не `nil`;
`RETURNING id` возвращает либо переданный, либо сгенерированный id. Различаются колонка и валидация.

> Кейс 5 с `bigserial`: если клиент передал `id=100`, sequence не сдвигается, и когда автонумерация
> дойдёт до 100, обычный Create упадёт на duplicate key. Для такого PK после ручной вставки нужен
> `setval`, либо выбирай uuid.

### 3. PK: меняется ли через Update

По умолчанию — **нет**: путь `PUT /<entity>/{id}`, `Decode<Entity>UpdateReq` не заполняет `Edit.Id`.
Если смена id нужна, путь становится `PUT /<entity>/{req_id}` (текущий id — механика бэка), а новое
значение приходит в body в привычном фронту поле `id` (см. `layers/proto.md`, «Смена PK через PUT»).

---

## Общие правила (для всех сущностей)

### Имена

| Где | Имя |
|---|---|
| proto service | `<Entity>Service` — **свой сервис на каждую сущность** |
| RPC | `List`, `Get`, `Create`, `Update`, `Delete` — без префикса сущности |
| proto message | **с префиксом**: `<Entity>Main`, `<Entity>ListReq`, `<Entity>ListRep`, `<Entity>GetReq`, `<Entity>CreateReq`, `<Entity>CreateRep`, `<Entity>UpdateReq` |
| handler | struct `<Entity>`, конструктор `New<Entity>`, методы = имена RPC |
| dto | `Encode<Entity>Main`, `Decode<Entity>ListReq`, `Decode<Entity>CreateReq`, `Decode<Entity>UpdateReq` |

Все `.proto` сервиса лежат в одном пакете `<svc_name>_v1`, а все handler-ы и dto — в пакетах
`internal/handler/grpc` и `.../dto`, поэтому сообщения, типы и функции — с префиксом. RPC без
префикса уникальны внутри своего `service` и своего handler-struct. Отсюда запрет:
**не объединяй сущности в один `service` или в один handler-struct** — `rpc List` двух сущностей в
одном сервисе protoc не примет (`"List" is already defined`), а два метода `List` у одного struct не
скомпилируются (`method List already declared`).

### Сообщения запросов и ответов

- `Get` возвращает `<Entity>Main` напрямую
- `Delete` для простого случая принимает `<Entity>GetReq`. Отдельный `<Entity>DeleteReq` заводится,
  когда у удаления появляются свои поля (флаг, причина)
- `Update` и `Delete` возвращают `google.protobuf.Empty`. Отдельный `<Entity>UpdateRep` /
  `<Entity>DeleteRep` заводится, когда нужно что-то вернуть
- `Create` возвращает `<Entity>CreateRep { id }` — id новой записи на всех слоях

### Partial create и partial update

- **Все** поля `<Entity>CreateReq` и `<Entity>UpdateReq` — `optional`. Не передали — поле не попадает в
  INSERT/UPDATE: при Create срабатывает DB-default, при Update значение не меняется
- В dto поля передаются указателями как есть (`Name: v.Name`), без `new(v.GetName())`
- Обязательность полей проверяет **usecase** (`validateEdit(obj, forCreate)`), а не proto

### Остальное

- Служебные колонки — `created_at`, `modified_at` (`CreatedAt`, `ModifiedAt` во всех слоях)
- REST-пути в единственном числе: `/<entity>`, `/<entity>/{id}`; update — `put`
- Имя таблицы в единственном числе, то же значение в `TableName` репозитория
- Зависимости: usecase и domain service объявляют интерфейсы своих зависимостей (`ServiceI`,
  `RepoDbI`); handler использует `*usecase.Usecase` напрямую, без интерфейса
- Update/Delete несуществующей записи ошибку не возвращают (mobone не проверяет число затронутых
  строк). Если сущности нужно `object_not_found` — считай затронутые строки в кастомном запросе

---

## Структура файлов

```
api/proto/<svc_name>_v1/
└── <entity>.proto            → proto    (layers/proto.md)

internal/domain/<entity>/
├── model/model.go            → model    (layers/model.md)
├── service/                  → domain   (layers/domain.md)
│   ├── interfaces.go
│   └── service.go
└── repo/db/                  → repo     (layers/repo.md)
    ├── repo.go
    ├── custom.go
    └── model/
        ├── select.go         ← Select + EncodeSelect
        ├── upsert.go         ← Upsert + DecodeUpsert
        └── children.go       ← (опц.) вложенные jsonb-модели

internal/usecase/<entity>/
├── interfaces.go             → usecase  (layers/usecase.md)
└── usecase.go

internal/handler/grpc/
├── <entity>.go               → handler  (layers/handler.md)
└── dto/
    ├── common.go             ← есть в gotemplate: DecodeListParams, хелперы Struct
    └── <entity>.go

migrations/
├── NNNNNN_<name>.up.sql
└── NNNNNN_<name>.down.sql
```

> **Порядок реализации:** proto → model → domain → repo → usecase → handler → app wiring → migration

---

## Регистрация в `internal/app/app.go`

Алиасы внутренних пакетов-конструкторов — полный путь в camelCase + суффикс `P` (CLAUDE.md проекта).
Каждая сущность — блок с комментарием-меткой.

```go
import (
	domain<Entity>RepoDbP "github.com/<module>/internal/domain/<entity>/repo/db"
	domain<Entity>ServiceP "github.com/<module>/internal/domain/<entity>/service"
	handlerGrpcP "github.com/<module>/internal/handler/grpc"
	usecase<Entity>P "github.com/<module>/internal/usecase/<entity>"
	"github.com/<module>/pkg/proto/<svc_name>_v1"
)

	// <entity>
	<entity>Repo := domain<Entity>RepoDbP.New(a.pgpool)
	<entity>Service := domain<Entity>ServiceP.New(<entity>Repo)
	<entity>Usecase := usecase<Entity>P.New(<entity>Service)
	<entity>Handler := handlerGrpcP.New<Entity>(<entity>Usecase)

	// grpc server
	{
		a.grpcServer = NewGrpcServer("main", func(server *grpc.Server) {
			<svc_name>_v1.Register<Entity>ServiceServer(server, <entity>Handler)
		})
	}

	// http-gw server — только если сервису нужен HTTP: в срез handlers
			handlers := []func(context.Context, *runtime.ServeMux, *grpc.ClientConn) error{
				<svc_name>_v1.Register<Entity>ServiceHandler,
			}
```

---

## Чеклист новой сущности

### Перед началом
- [ ] Транспорт: gRPC, HTTP или оба (раздел «Транспорт»)
- [ ] PK: кейс 1–5; меняется ли id через PUT (разделы про PK)

### Proto Contract (`layers/proto.md`)
- [ ] `api/proto/<svc_name>_v1/<entity>.proto` — `service <Entity>Service`, RPC `List/Get/Create/Update/Delete`
- [ ] Сообщения с префиксом `<Entity>`; Get → `<Entity>Main`; Delete → `<Entity>GetReq`; Update/Delete → `Empty`
- [ ] `<Entity>CreateRep { id }`; все поля `CreateReq`/`UpdateReq` — `optional`
- [ ] HTTP-аннотации — если нужен HTTP; пути в единственном числе; update — `put`
- [ ] `make generate-proto`

### Domain Model (`layers/model.md`)
- [ ] `model/model.go` — `Main` (value), `Edit` (pointer, `CreatedAt`, `Id` — по кейсу PK), `ListReq` с embed `commonModel.ListParams`

### Domain Service (`layers/domain.md`)
- [ ] `service/interfaces.go` — публичный `RepoDbI`
- [ ] `service/service.go` — `Service`, `New()`, List/Get/Create/Update/Delete с `<idType>`
- [ ] `Create` сбрасывает `ModifiedAt = nil` (DB-default), `Update` ставит `ModifiedAt = new(time.Now())`

### Repository (`layers/repo.md`)
- [ ] `repo/db/model/select.go` — `Select` (`ListColumnMap`, `PKColumnMap`, `DefaultSortColumns`) + `EncodeSelect`
- [ ] `repo/db/model/upsert.go` — `Upsert` (`PKId`, `NewId`, `CreateColumnMap`, `UpdateColumnMap`, `PKColumnMap`, `ReturningColumnMap`) + `DecodeUpsert`
- [ ] `repo/db/repo.go` — `Repo`, `New`, CRUD
- [ ] `repo/db/custom.go` — `allowedSortFields`, `getConditions`, кастомные запросы
- [ ] Wrapping ошибок: `fmt.Errorf("ModelStore.<Method>: %w", err)`

### Usecase (`layers/usecase.md`)
- [ ] `usecase/<entity>/interfaces.go` — публичный `ServiceI` (зависимость usecase)
- [ ] `usecase/<entity>/usecase.go` — `Usecase`, `New()`, `validateEdit` с обязательными полями, проверка пустого id, auth placeholder

### Handler (`layers/handler.md`)
- [ ] `handler/grpc/<entity>.go` — struct `<Entity>` с embed `<svc_name>_v1.Unsafe<Entity>ServiceServer` и `*usecase.Usecase`
- [ ] `handler/grpc/dto/<entity>.go` — `Encode<Entity>Main`, `Decode<Entity>ListReq/CreateReq/UpdateReq`

### Infrastructure
- [ ] SQL миграция в `migrations/` (`.up.sql` / `.down.sql`); таблица в единственном числе; `created_at`/`modified_at timestamptz not null default now()`; в `down` все `DROP ... CASCADE` в обратном порядке
- [ ] Wiring в `internal/app/app.go` (gRPC server; gateway — если нужен HTTP)
- [ ] `make generate-proto` → `go mod tidy` (после первой сущности в свежем проекте — подтянет mobone) → `gofmt -w .` → `go vet ./...` → `go test ./...` → `go run ./cmd/.`
