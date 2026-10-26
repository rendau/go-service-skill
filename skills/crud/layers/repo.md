# Layer: Repository — `internal/domain/<entity>/repo/db/`

Доступ к PostgreSQL через mobone/squirrel/pgx. Справочник API `ModelStore` — в skill `mobone`.

## Файлы

| Файл | Назначение |
|---|---|
| `repo.go` | `Repo` struct, `New()`, CRUD-методы |
| `custom.go` | `allowedSortFields`, `getConditions`, кастомные запросы |
| `model/select.go` | модель чтения (value-типы) + `EncodeSelect` |
| `model/upsert.go` | модель записи (pointer-типы) + `DecodeUpsert` |
| `model/children.go` | вложенные модели jsonb-полей + их `encode/decode` (jsonb, подход 1 — см. ниже) |

> DTOs (`EncodeSelect`, `DecodeUpsert`) живут в своих файлах — отдельного `dto.go` нет.

---

## model/select.go — модель чтения + DTO

- Поля **value-типы** (не указатели); `Id` — `<idType>`
- Nullable колонки → `sql.NullString` / `sql.NullTime` / `sql.NullInt64`; в `EncodeSelect` берём
  `.String` / `.Time` / `.Int64` (NULL → zero value в домене)
- `EncodeSelect` — конвертер Select → domain.Main (сигнатура совместима с `lo.Map`)

```go
package model

import (
	"time"

	domainModel "github.com/<module>/internal/domain/<entity>/model"
)

type Select struct {
	Id         <idType>
	CreatedAt  time.Time
	ModifiedAt time.Time
	Name       string
	Active     bool
}

func (m *Select) ListColumnMap() map[string]any {
	return map[string]any{
		"id":          &m.Id,
		"created_at":  &m.CreatedAt,
		"modified_at": &m.ModifiedAt,
		"name":        &m.Name,
		"active":      &m.Active,
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
		Name:       v.Name,
		Active:     v.Active,
	}
}
```

---

## model/upsert.go — модель записи + DTO

- `PKId <idType>` — публичный, не указатель; ставится в `repo.go` перед Update/Delete (текущий id)
- `NewId <idType>` — сюда `ModelStore.Create` пишет id новой записи через `ReturningColumnMap`.
  `ReturningColumnMap` обязателен: он входит в `mobone.CreateModelI`
- `CreateColumnMap` — только переданные (`!= nil`) поля: не переданное не попадает в INSERT и
  получает DB-default. `created_at` пишется, только если передан (импорт)
- `Id *<idType>` — только для кейсов PK 3–5 и смены PK; если передан, пишется в `id`
- `UpdateColumnMap` — делегирует в `CreateColumnMap`. Поэтому PK меняется через Update, только
  если в `Edit.Id` передали новое значение; по умолчанию `Decode<Entity>UpdateReq` его не заполняет
- Nullable колонка: пустое значение пишем как NULL, иначе упадёт FK/unique (`nullIfEmpty`)
- `DecodeUpsert` — конвертер domain.Edit → Upsert

```go
package model

import (
	"time"

	domainModel "github.com/<module>/internal/domain/<entity>/model"
)

type Upsert struct {
	PKId  <idType>
	NewId <idType> // id новой записи, заполняется в Create через RETURNING

	// Id *<idType> — кейсы PK 3–5 и смена PK через PUT
	CreatedAt  *time.Time
	ModifiedAt *time.Time
	Name       *string
	Active     *bool
}

func (m *Upsert) CreateColumnMap() map[string]any {
	result := make(map[string]any, 4)
	// if m.Id != nil { result["id"] = *m.Id } ← кейсы PK 3–5 и смена PK
	if m.CreatedAt != nil {
		result["created_at"] = *m.CreatedAt
	}
	if m.ModifiedAt != nil {
		result["modified_at"] = *m.ModifiedAt
	}
	if m.Name != nil {
		result["name"] = *m.Name
	}
	if m.Active != nil {
		result["active"] = *m.Active
	}
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
		// Id: v.Id,
		CreatedAt:  v.CreatedAt,
		ModifiedAt: v.ModifiedAt,
		Name:       v.Name,
		Active:     v.Active,
	}
}
```

Nullable-колонка (например FK `brand_id text references brand(id)`, домен `BrandId string`):

```go
// select.go
BrandId sql.NullString // ListColumnMap: "brand_id": &m.BrandId; EncodeSelect: v.BrandId.String

// upsert.go
if m.BrandId != nil {
	result["brand_id"] = nullIfEmpty(*m.BrandId)
}

// nullIfEmpty — пустая строка в nullable-колонку пишется как NULL.
func nullIfEmpty(v string) *string {
	if v == "" {
		return nil
	}
	return &v
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

Использование в `EncodeSelect`/`DecodeUpsert` (там импортируется `lo`): `lo.Map(v.Items, encodeItem)` и
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

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rendau/mobone/v2"
	moboneTools "github.com/rendau/mobone/v2/tools"
	"github.com/samber/lo"

	commonRepoPg "github.com/<module>/internal/domain/common/repo/pg"
	"github.com/<module>/internal/domain/<entity>/model"
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
	items := make([]*repoModel.Select, 0)

	totalCount, err := r.ModelStore.List(ctx, mobone.ListParams{
		Conditions:           conditions,
		ConditionExpressions: conditionExps,
		Page:                 pars.Page,
		PageSize:             pars.PageSize,
		WithTotalCount:       pars.WithTotalCount,
		OnlyCount:            pars.OnlyCount,
		Sort:                 moboneTools.ConstructSortColumns(allowedSortFields, pars.Sort),
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

func (r *Repo) Get(ctx context.Context, id <idType>) (*model.Main, bool, error) {
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

func (r *Repo) Create(ctx context.Context, obj *model.Edit) (<idType>, error) {
	m := repoModel.DecodeUpsert(obj)
	if err := r.ModelStore.Create(ctx, m); err != nil {
		return <zeroId>, fmt.Errorf("ModelStore.Create: %w", err)
	}
	return m.NewId, nil
}

func (r *Repo) Update(ctx context.Context, id <idType>, obj *model.Edit) error {
	m := repoModel.DecodeUpsert(obj)
	m.PKId = id
	if err := r.ModelStore.Update(ctx, m); err != nil {
		return fmt.Errorf("ModelStore.Update: %w", err)
	}
	return nil
}

func (r *Repo) Delete(ctx context.Context, id <idType>) error {
	if err := r.ModelStore.Delete(ctx, &repoModel.Upsert{PKId: id}); err != nil {
		return fmt.Errorf("ModelStore.Delete: %w", err)
	}
	return nil
}
```

---

## custom.go — фильтры, сортировка, сложные запросы

- `allowedSortFields` — белый список для `ConstructSortColumns` (`sort: ["-name"]` → `name desc`);
  пустой `Sort` → `DefaultSortColumns()`
- `conditions` — точное совпадение и `IN`, `conditionExps` — выражения
- Фильтр по списку ставь только если `pars.IDs != nil`: squirrel превращает **и пустой, и nil**
  срез в `WHERE (1=0)`. Пустой срез под указателем — осознанное «ничего не найдено»

```go
package db

import (
	"context"
	"fmt"

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

	// точное совпадение
	if pars.Active != nil {
		conditions["active"] = *pars.Active
	}
	// ILIKE поиск
	if pars.Name != nil {
		conditionExps["name ILIKE ?"] = []any{"%" + *pars.Name + "%"}
	}
	// IN по массиву
	if pars.IDs != nil {
		conditions["id"] = *pars.IDs
	}

	return conditions, conditionExps
}

// Bulk операция (squirrel) — по необходимости
func (r *Repo) DeleteByFilter(ctx context.Context, value string) error {
	query, args, err := r.QB.
		Delete("<entity>").
		Where(sq.Eq{"<column>": value}).
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

> `context`, `fmt` и `sq` нужны только с кастомными запросами — без `DeleteByFilter` убери их
> из импортов.

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
