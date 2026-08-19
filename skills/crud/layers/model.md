# Layer: Domain Model — `internal/domain/<entity>/model/model.go`

Доменные структуры данных. Не зависят ни от каких других слоёв.

## Правила
- `Main` — сущность для чтения, **все поля value-типы** (не указатели)
- `Edit` — мутация, **все поля pointer-типы** (partial update)
- `ListReq` — параметры фильтрации/пагинации, embed `commonModel.ListParams`
- Nullable поля в БД → `string` с пустым значением по умолчанию (или отдельный тип если нужно различать NULL)
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
    Id        string
    Name      string
    CreatedAt time.Time
    UpdatedAt time.Time
}

// Edit — мутация (все поля pointer-типы для partial update)
type Edit struct {
    Id        *string
    Name      *string
    CreatedAt *time.Time
    UpdatedAt *time.Time
}

// ListReq — параметры выборки
type ListReq struct {
    commonModel.ListParams

    // фильтры по необходимости
    Name *string
    IDs  *[]string
}
```

## Связанные структуры (по необходимости)

```go
// Вложенные сущности для Get-ответа (если нужно)
type <SubEntity> struct {
    Id   string
    Name string
    // ...
}
```
