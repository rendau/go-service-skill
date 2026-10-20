# Layer: Domain Model — `internal/domain/<entity>/model/model.go`

Доменные структуры данных. Не зависят ни от каких других слоёв.

## Правила
- `Main` — сущность для чтения, **все поля value-типы** (не указатели)
- `Edit` — мутация, **все поля pointer-типы** (partial create и partial update: `nil` = не передано)
- `Edit.Id` — только для кейсов PK 3–5 (id приходит из запроса) и при смене PK через PUT
  (см. «PK» в `SKILL.md`). В Update текущий id всегда передаётся отдельным параметром
- `Edit.CreatedAt` — есть всегда, обычно `nil` (ставит DB-default). Нужен, когда понадобится
  записать исходную дату создания (импорт) — без доработок слоёв
- `ListReq` — параметры фильтрации/пагинации, embed `commonModel.ListParams`; одиночные фильтры —
  указатели; фильтр по списку — **указатель на срез** (`IDs *[]<idType>`): `nil` — фильтра нет,
  пустой срез — «ничего не найдено». Так внутренний вызов с пустым списком (например, id из
  пустой корзины) не превратится в выборку всех записей
- Служебные поля: `CreatedAt`, `ModifiedAt` (колонки `created_at`, `modified_at`)
- Nullable колонка → value-тип с zero value в `Main` (`BrandId string`, пустая строка = NULL);
  отдельный тип — только если надо различать NULL и zero value
- **Никаких тегов сериализации** (`json:"..."`, `yaml:"..."`) на полях доменной модели — она не
  знает ни про транспорт, ни про формат хранения. Если поле хранится в БД как JSON, теги `json`
  живут на отдельной модели-DTO в repo-слое (см. `repo.md`), а не здесь.

## Шаблон

```go
package model

import (
	"time"

	commonModel "github.com/<module>/internal/domain/common/model"
)

// Main — доменная сущность (все поля value-типы)
type Main struct {
	Id         <idType>
	CreatedAt  time.Time
	ModifiedAt time.Time
	Name       string
	Active     bool
}

// Edit — мутация (все поля pointer-типы для partial create/update)
type Edit struct {
	// Id *<idType> — только если id приходит из запроса (кейсы PK 3–5) или меняется через PUT
	CreatedAt  *time.Time // обычно nil (DB-default); для импорта с исходной датой
	ModifiedAt *time.Time
	Name       *string
	Active     *bool
}

// ListReq — параметры выборки
type ListReq struct {
	commonModel.ListParams

	// фильтры по необходимости
	Active *bool
	Name   *string
	IDs    *[]<idType>
}
```

## Связанные структуры (по необходимости)

```go
// Вложенные сущности (jsonb-поля, Get-ответ) — тоже без тегов
type <SubEntity> struct {
	Id   string
	Name string
}
```
