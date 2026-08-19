---
name: crud
description: >
  Go CRUD полный стек (proto → model → domain service → repo → usecase → handler) для проектов на
  Clean Architecture + DDD с mobone/squirrel/pgx + gRPC/grpc-gateway.
  Используй этот скилл ВСЕГДА когда задача касается: создания новой сущности, написания CRUD-метода
  (List, Get, Create, Update, Delete), добавления доменной сущности, написания repo/pg/model
  (select.go, upsert.go, dto.go), работы с mobone.ModelStore, фильтрации через getConditions,
  bulk-операций через squirrel, трассировки методов репозитория, wrapping ошибок, usecase-слоя,
  gRPC handler + DTO, proto-контракта сущности (api/proto/).
  Триггерные слова: repo, repository, репозиторий, CRUD, mobone, ModelStore, ListReq, Select,
  Upsert, getConditions, squirrel, pg.go, dto.go, upsert.go, select.go, domain service, RepoI,
  usecase, handler, DTO, proto, entity, сущность, grpc, gateway, api/proto.
---

# CRUD — полный стек новой сущности

Детальные паттерны по слоям — в отдельных файлах:
- `layers/proto.md` — Proto Contract (api/proto/)
- `layers/model.md` — Domain Model
- `layers/domain.md` — Domain Service
- `layers/repo.md` — Repository (repo/pg/)
- `layers/usecase.md` — Usecase
- `layers/handler.md` — gRPC Handler + DTO

---

## Библиотеки

| Назначение | Библиотека |
|---|---|
| Основной CRUD поверх pgx | `github.com/mechta-market/mobone/v2` |
| Сложные/кастомные запросы | `github.com/Masterminds/squirrel` |
| Прямой доступ к БД | `github.com/jackc/pgx/v5` |
| Хелперы (маппинг, указатели) | `github.com/samber/lo` |

---

## Общие правила (для всех сущностей)

- **`Create` возвращает id новой записи** на всех слоях (repo → domain service → usecase → handler).
  Действует для любой сущности, имеющей `id`. Тип id соответствует PK: `int64` для `bigserial`,
  `string` для `text`/`uuid`.
  - proto: `Create<Entity>` возвращает `<Entity>CreateRep { id }` (не `google.protobuf.Empty`);
  - repo `Upsert`: поле `NewId <type>` + `ReturningColumnMap() → {"id": &m.NewId}` (использует `RETURNING id`);
  - repo/domain/usecase: `Create(ctx, obj) (<idType>, error)`;
  - handler: возвращает `&proto.<Entity>CreateRep{Id: newId}`.

---

## Структура файлов

```
api/proto/<svc_name>_v1/
└── <entity>.proto        → слой: proto      (см. layers/proto.md)

internal/domain/<entity>/
├── model/model.go        → слой: model      (см. layers/model.md)
└── service/              → слой: domain     (см. layers/domain.md)
│   ├── interfaces.go
│   └── service.go
└── repo/db/              → слой: repo       (см. layers/repo.md)
    ├── repo.go
    ├── custom.go
    └── model/
        ├── select.go     ← содержит EncodeSelect()
        └── upsert.go     ← содержит DecodeUpsert()

internal/usecase/<entity>/
├── interfaces.go         → слой: usecase    (см. layers/usecase.md)
└── usecase.go

internal/handler/grpc/
├── <entity>.go           → слой: handler    (см. layers/handler.md)
└── dto/<entity>.go
```

> **Порядок реализации:** proto → model → domain → repo → usecase → handler → app wiring

---

## Регистрация в `internal/app/app.go`

```go
<entity>Repo    := <entity>Db.New(pgPool)
<entity>Svc     := <entity>Service.New(<entity>Repo)
<entity>Usecase := <entity>Usc.New(<entity>Svc)
<entity>Handler := grpcHandler.New<Entity>(<entity>Usecase)

<proto_pkg>.Register<Entity>ServiceServer(grpcServer, <entity>Handler)
```

---

## Чеклист новой сущности

### Proto Contract (`layers/proto.md`)
- [ ] `api/proto/<svc_name>_v1/<entity>.proto` — сервис + все CRUD сообщения
- [ ] `Create<Entity>` возвращает `<Entity>CreateRep { id }` (не `Empty`) — для сущностей с id
- [ ] `optional` поля в `Update<Entity>Request` для partial update
- [ ] HTTP-аннотации через `google.api.http` для каждого RPC; REST-пути всегда в единственном числе, без plural (`/entity`, `/entity/{id}`)
- [ ] `make generate-proto` — сгенерировать `pkg/proto/<svc_name>_v1/`

### Domain Model (`layers/model.md`)
- [ ] `model/model.go` — `Main` (value), `Edit` (pointer), `ListReq` с embed `commonModel.ListParams`

### Domain Service (`layers/domain.md`)
- [ ] `service/interfaces.go` — публичный `RepoDbI` интерфейс
- [ ] `service/service.go` — `Service`, `New()`, Get/List/Create/Update/Delete
- [ ] `Create` возвращает id новой записи (`(idType, error)`) — для сущностей с id
- [ ] `Create` сбрасывает `ModifiedAt = nil` (DB-default), `Update` устанавливает `ModifiedAt = time.Now()`

### Repository (`layers/repo.md`)
- [ ] `repo/db/model/select.go` — `Select` с `ListColumnMap`, `PKColumnMap`, `DefaultSortColumns` + `EncodeSelect`
- [ ] `repo/db/model/upsert.go` — `Upsert` с `PKId`, `NewId`, `CreateColumnMap`, `UpdateColumnMap`, `PKColumnMap`, `ReturningColumnMap` (возвращает `{"id": &m.NewId}`) + `DecodeUpsert`
- [ ] `repo/db/repo.go` — `Repo`, конструктор `New`, CRUD-методы; `TableName` в единственном числе, без plural
- [ ] `repo/db/custom.go` — `getConditions`, `allowedSortFields`, кастомные методы
- [ ] Wrapping ошибок: `fmt.Errorf("ModelStore.<Method>: %w", err)`

### Usecase (`layers/usecase.md`)
- [ ] `usecase/<entity>/interfaces.go` — публичный `<Entity>I` интерфейс
- [ ] `usecase/<entity>/usecase.go` — `Usecase`, `New()`, validate(), auth placeholder в mutable методах; `Create` возвращает id

### Handler (`layers/handler.md`)
- [ ] `handler/grpc/<entity>.go` — embed `<proto_pkg>.Unsafe<Entity>ServiceServer`, все CRUD методы; `Create` возвращает `<Entity>CreateRep{Id: newId}`
- [ ] `handler/grpc/dto/<entity>.go` — `Decode*` (proto→domain), `Encode*` (domain→proto)

### Infrastructure
- [ ] SQL миграция в `migrations/` (`.up.sql` / `.down.sql`); имя таблицы в единственном числе, без plural; в `down` все `DROP` с `CASCADE`, в обратном порядке
- [ ] Wiring в `internal/app/app.go`