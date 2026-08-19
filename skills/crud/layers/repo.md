# Layer: Repository — `internal/domain/<entity>/repo/db/`

Доступ к PostgreSQL через mobone/squirrel/pgx.

## Файлы

| Файл | Назначение |
|---|---|
| `repo.go` | `Repo` struct, `New()`, CRUD-методы |
| `custom.go` | `getConditions`, `allowedSortFields`, кастомные запросы |
| `model/select.go` | модель чтения (value-типы) + `EncodeSelect` |
| `model/upsert.go` | модель записи (pointer-типы) + `DecodeUpsert` |
| `model/children.go` | вложенные модели jsonb-полей + их `encode/decode` (jsonb, подход 1 — см. ниже) |

> DTOs (`EncodeSelect`, `DecodeUpsert`) живут в своих файлах — отдельного `dto.go` нет.

---

## model/select.go — модель чтения + DTO

- Поля **value-типы** (не указатели)
- Nullable колонки в БД → `sql.NullString` / `sql.NullTime`
- `EncodeSelect` — конвертер Select → domain.Main (сигнатура совместима с `lo.Map`)

```go
package model

import (
    "time"

    domainModel "github.com/<module>/internal/domain/<entity>/model"
)

type Select struct {
    Id         string
    CreatedAt  time.Time
    ModifiedAt time.Time
    Active     bool
    Name       string
}

func (m *Select) ListColumnMap() map[string]any {
    return map[string]any{
        "id":          &m.Id,
        "created_at":  &m.CreatedAt,
        "modified_at": &m.ModifiedAt,
        "active":      &m.Active,
        "name":        &m.Name,
    }
}

func (m *Select) PKColumnMap() map[string]any {
    return map[string]any{"id": m.Id}
}

func (m *Select) DefaultSortColumns() []string {
    return []string{"created_at DESC"}
}

// DTO

func EncodeSelect(v *Select, _ int) *domainModel.Main {
    return &domainModel.Main{
        Id:         v.Id,
        CreatedAt:  v.CreatedAt,
        ModifiedAt: v.ModifiedAt,
        Active:     v.Active,
        Name:       v.Name,
    }
}
```

---

## model/upsert.go — модель записи + DTO

- `PKId string` — публичный, не указатель; устанавливается в `repo.go` перед Update/Delete
- `NewId <type>` — публичный; сюда `ModelStore.Create` пишет id новой записи через `ReturningColumnMap` (правило для всех сущностей с id; тип как у PK: `int64` для bigserial, `string` для text/uuid)
- `CreateColumnMap` — **не включает** `id` (только бизнес-поля)
- `UpdateColumnMap` — делегирует в `CreateColumnMap`
- `DecodeUpsert` — конвертер domain.Edit → Upsert

```go
package model

import (
    "time"

    domainModel "github.com/<module>/internal/domain/<entity>/model"
)

type Upsert struct {
    PKId  string
    NewId string // id новой записи, заполняется в Create через RETURNING (int64 для bigserial)

    ModifiedAt *time.Time
    Active     *bool
    Name       *string
}

func (m *Upsert) CreateColumnMap() map[string]any {
    result := make(map[string]any{}, 10)
    if m.ModifiedAt != nil { result["modified_at"] = *m.ModifiedAt }
    if m.Active != nil     { result["active"] = *m.Active }
    if m.Name != nil       { result["name"] = *m.Name }
    return result
}

func (m *Upsert) UpdateColumnMap() map[string]any {
    return m.CreateColumnMap()
}

func (m *Upsert) PKColumnMap() map[string]any {
    return map[string]any{"id": m.PKId}
}

// ReturningColumnMap — Create использует RETURNING id, чтобы вернуть id новой записи
func (m *Upsert) ReturningColumnMap() map[string]any {
    return map[string]any{"id": &m.NewId}
}

// DTO

func DecodeUpsert(v *domainModel.Edit) *Upsert {
    return &Upsert{
        ModifiedAt: v.ModifiedAt,
        Active:     v.Active,
        Name:       v.Name,
    }
}
```

---

## jsonb-поля — два подхода (спроси перед реализацией)

jsonb-колонки (вложенные структуры/массивы) можно мапить двумя способами. Какой подойдёт —
зависит от проекта и сущности, поэтому **перед реализацией спроси у пользователя, какой подход
использовать** (по умолчанию ориентируйся на то, как уже сделано у соседних сущностей проекта).
Доменная `Main`/`Edit` в обоих случаях оперируют обычными Go-структурами/срезами **без json-тегов**.

| Подход | Когда | Чтение/запись |
|---|---|---|
| 1. Структурный (`children.go`) | mobone/pgx умеет сканить jsonb прямо в структуру | `&m.Field` в ColumnMap, без ручного marshal |
| 2. Байтовый (`[]byte`) | нужен полный контроль над (де)сериализацией | `[]byte` + `json.Unmarshal`/`json.Marshal` |

---

### Подход 1 — model/children.go (структурный)

repo-копию вложенного типа (ту же структуру, но с json-тегами) держим **в отдельном файле
`children.go`** рядом с `select.go`/`upsert.go` — не объявляем эти типы в `select.go`/`upsert.go`.

- mobone/pgx читает и пишет jsonb напрямую в repo-структуру: в `ListColumnMap` отдаём `&m.Field`,
  в `CreateColumnMap` — саму структуру/слайс (без ручного `json.Marshal`/`Unmarshal`).
- У каждой вложенной модели — свои `encode<Name>` / `decode<Name>` в этом же `children.go`.
- Для **слайсовых** jsonb-полей делай одиночные конвертеры с сигнатурой `func(v X, _ int) Y`,
  чтобы вызывать их прямо через `lo.Map` / `lo.FilterMap` в `EncodeSelect`/`DecodeUpsert`.
- Для **одиночных** jsonb-полей — обычные nil-safe `encode`/`decode`.
- В `select.go`/`upsert.go` остаются только вызовы, без объявления типов и ручных циклов.

```go
// model/children.go
package model

import (
    "github.com/samber/lo"

    domainModel "github.com/<module>/internal/domain/<entity>/model"
)

// item — repo-копия domainModel.Item с json-тегами для (де)сериализации jsonb-массива.
type item struct {
    ProductId string `json:"product_id"`
    Title     string `json:"title"`
}

func encodeItem(v item, _ int) *domainModel.Item {
    return &domainModel.Item{ProductId: v.ProductId, Title: v.Title}
}

func decodeItem(v *domainModel.Item, _ int) item {
    return item{ProductId: v.ProductId, Title: v.Title}
}
```

Использование в `EncodeSelect`/`DecodeUpsert`: `lo.Map(v.Items, encodeItem)` и
`lo.Map(v.Items, decodeItem)`. В `CreateColumnMap` проверку заполнения слайса делай через
`len(m.Field) > 0` (а не `!= nil`: `lo.Map` возвращает непустой пустой слайс).

Для **одиночного** (не слайсового) jsonb-поля конвертеры обычные, nil-safe:

```go
// coordinates — одиночное jsonb-поле: nil-safe encode/decode (без сигнатуры под lo.Map).
type coordinates struct {
    Lat float64 `json:"lat"`
    Lon float64 `json:"lon"`
}

func encodeCoordinates(v coordinates) domainModel.Coordinates {
    return domainModel.Coordinates{Lat: v.Lat, Lon: v.Lon}
}

func decodeCoordinates(v *domainModel.Coordinates) *coordinates {
    if v == nil {
        return nil
    }
    return &coordinates{Lat: v.Lat, Lon: v.Lon}
}
```

Вызов: `Coordinates: encodeCoordinates(v.Coordinates)` в `EncodeSelect` и
`Coordinates: decodeCoordinates(v.Coordinates)` в `DecodeUpsert`.

---

### Подход 2 — байтовый (ручная (де)сериализация)

Колонку читаем как `[]byte`, а repo-локальную DTO с json-тегами и (де)сериализацию держим
рядом с `select.go`/`upsert.go`. Подходит, когда нужен полный контроль над форматом хранения.

```go
// model/select.go (или отдельный model/json.go)

// repo-локальная DTO: только она знает про формат хранения
type metaJSON struct {
    Color string   `json:"color"`
    Tags  []string `json:"tags"`
}

type Select struct {
    Id   string
    Meta []byte // jsonb-колонка читаем как []byte
}

func (m *Select) ListColumnMap() map[string]any {
    return map[string]any{"id": &m.Id, "meta": &m.Meta}
}

func EncodeSelect(v *Select, _ int) *domainModel.Main {
    out := &domainModel.Main{Id: v.Id}
    if len(v.Meta) > 0 {
        var meta metaJSON
        _ = json.Unmarshal(v.Meta, &meta)
        out.Color = meta.Color // доменные поля — без тегов
        out.Tags = meta.Tags
    }
    return out
}
```

При записи `DecodeUpsert` симметрично собирает `metaJSON`, делает `json.Marshal` и кладёт `[]byte`
(или `string`) в `CreateColumnMap` под ключ колонки.

---

## repo.go — Repo, конструктор, CRUD

```go
package db

import (
    "context"
    "fmt"

    "github.com/<module>/internal/domain/<entity>/model"
   
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/mechta-market/mobone/v2"
    "github.com/samber/lo"

    commonRepoPg "github.com/<module>/internal/domain/common/repo/pg"
    moboneTools "github.com/mechta-market/mobone/v2/tools"
    repoModel "github.com/<module>/internal/domain/<entity>/repo/db/model"
)

type Repo struct {
    *commonRepoPg.Base
    ModelStore *mobone.ModelStore
}

func New(con *pgxpool.Pool) *Repo {
    base := commonRepoPg.NewBase(con)
    return &Repo{
        Base: base,
        ModelStore: &mobone.ModelStore{
            Con:       base.Con,
            QB:        base.QB,
            TableName: "<entity>", // имя таблицы всегда в единственном числе, без plural
        },
    }
}

func (r *Repo) List(ctx context.Context, pars *model.ListReq) ([]*model.Main, int64, error) {
    conditions, conditionExps := r.getConditions(pars)
    sort := moboneTools.ConstructSortColumns(allowedSortFields, pars.Sort)
    items := make([]*repoModel.Select, 0)

    totalCount, err := r.ModelStore.List(ctx, mobone.ListParams{
        Conditions:           conditions,
        ConditionExpressions: conditionExps,
        Page:                 pars.Page,
        PageSize:             pars.PageSize,
        WithTotalCount:       pars.WithTotalCount,
        OnlyCount:            pars.OnlyCount,
        Sort:                 sort,
    }, func(add bool) mobone.ListModelI {
        item := &repoModel.Select{}
        if add {
            items = append(items, item)
        }
        return item
    })
    if err != nil {
        return nil, 0, fmt.Errorf("ModelStore.List: %w", err)
    }
    return lo.Map(items, repoModel.EncodeSelect), totalCount, nil
}

func (r *Repo) Get(ctx context.Context, id string) (*model.Main, bool, error) {
    m := &repoModel.Select{Id: id}
    found, err := r.ModelStore.Get(ctx, m)
    if err != nil {
        return nil, false, fmt.Errorf("ModelStore.Get: %w", err)
    }
    if !found {
        return nil, false, nil
    }
    return repoModel.EncodeSelect(m, 0), true, nil
}

func (r *Repo) Create(ctx context.Context, obj *model.Edit) (string, error) {
    m := repoModel.DecodeUpsert(obj)
    if err := r.ModelStore.Create(ctx, m); err != nil {
        return "", fmt.Errorf("ModelStore.Create: %w", err)
    }
    return m.NewId, nil // id новой записи (правило для всех сущностей с id)
}

func (r *Repo) Update(ctx context.Context, id string, obj *model.Edit) error {
    m := repoModel.DecodeUpsert(obj)
    m.PKId = id
    if err := r.ModelStore.Update(ctx, m); err != nil {
        return fmt.Errorf("ModelStore.Update: %w", err)
    }
    return nil
}

func (r *Repo) Delete(ctx context.Context, id string) error {
    m := &repoModel.Upsert{PKId: id}
    if err := r.ModelStore.Delete(ctx, m); err != nil {
        return fmt.Errorf("ModelStore.Delete: %w", err)
    }
    return nil
}
```

---

## custom.go — фильтры, сортировка, сложные запросы

```go
package db

import (
    sq "github.com/Masterminds/squirrel"
    "github.com/<module>/internal/domain/<entity>/model"
)

var allowedSortFields = map[string]string{
    "id":          "id",
    "created_at":  "created_at",
    "modified_at": "modified_at",
    "name":        "name",
}

func (r *Repo) getConditions(pars *model.ListReq) (map[string]any, map[string][]any) {
    conditions := make(map[string]any, 10)
    conditionExps := make(map[string][]any, 10)

    if pars == nil {
        return conditions, conditionExps
    }

    // Точное совпадение:
    // if pars.Active != nil { conditions["active"] = *pars.Active }

    // ILIKE поиск:
    // if pars.Name != nil { conditionExps["name ILIKE ?"] = []any{"%" + *pars.Name + "%"} }

    // IN по массиву:
    // if pars.IDs != nil { condition["id"] = pars.IDs }

    return conditions, conditionExps
}

// Bulk операция (squirrel)
func (r *Repo) DeleteByFilter(ctx context.Context, field string) error {
    query, args, err := r.QB.
        Delete("<table_name>").
        Where(sq.Eq{"<column>": field}).
        ToSql()
    if err != nil {
        return fmt.Errorf("DeleteByFilter build query: %w", err)
    }
    if _, err = r.Con.Exec(ctx, query, args...); err != nil {
        return fmt.Errorf("DeleteByFilter: %w", err)
    }
    return nil
}
```

---

## Трассировка (опционально)

Если проект использует OpenTracing, оборачивай каждый публичный метод:

```go
func (r *Repo) MethodName(ctx context.Context, ...) (_ RetType, finalError error) {
    tracingSpan, ctx := opentracing.StartSpanFromContext(ctx, "<entity>.repo.DB.MethodName")
    defer tracingSpan.Finish()
    defer func() {
        if finalError != nil {
            tracingSpan.SetTag("error", true)
            tracingSpan.LogKV("error", finalError.Error())
        }
    }()
    // ...
}
```
