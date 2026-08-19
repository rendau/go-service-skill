# Layer: Domain Service — `internal/domain/<entity>/service/`

Бизнес-логика и инварианты. Единственный слой с доступом к репозиторию.

## Файлы

| Файл | Назначение |
|---|---|
| `service/interfaces.go` | публичный `RepoDbI` интерфейс |
| `service/service.go` | `Service` struct + методы |

## Правила
- `RepoDbI` интерфейс — **публичный** (uppercase), объявляется в `service/interfaces.go`
- `Service` принимает `repoDb RepoDbI` через конструктор `New`
- `Create` сбрасывает `ModifiedAt = nil` — DB-default (напр. `DEFAULT NOW()`) устанавливает значение
- **`Create` возвращает id новой записи** (`(idType, error)`) — правило для всех сущностей с id; тип id как у PK (`int64`/`string`)
- `Update` принимает `id string` и устанавливает `ModifiedAt = new(time.Now())`
- `Get` с `errNE=true` возвращает `errs.ObjectNotFound` если не найдено
- Все ошибки оборачиваются: `fmt.Errorf("repoDb.<Method>: %w", err)`

## service/interfaces.go

```go
package service

import (
    "context"
    "github.com/<module>/internal/domain/<entity>/model"
)

type RepoDbI interface {
    List(ctx context.Context, pars *model.ListReq) ([]*model.Main, int64, error)
    Get(ctx context.Context, id string) (*model.Main, bool, error)
    Create(ctx context.Context, obj *model.Edit) (string, error)
    Update(ctx context.Context, id string, obj *model.Edit) error
    Delete(ctx context.Context, id string) error
}
```

## service/service.go

```go
package service

import (
    "context"
    "fmt"
    "time"

    "github.com/samber/lo"

    "github.com/<module>/internal/domain/<entity>/model"
    "github.com/<module>/internal/errs"
)

type Service struct {
    repoDb RepoDbI
}

func New(repoDb RepoDbI) *Service {
    return &Service{repoDb: repoDb}
}

func (s *Service) List(ctx context.Context, pars *model.ListReq) ([]*model.Main, int64, error) {
    items, tCount, err := s.repoDb.List(ctx, pars)
    if err != nil {
        return nil, 0, fmt.Errorf("repoDb.List: %w", err)
    }
    return items, tCount, nil
}

func (s *Service) Get(ctx context.Context, id string, errNE bool) (*model.Main, bool, error) {
    result, found, err := s.repoDb.Get(ctx, id)
    if err != nil {
        return nil, false, fmt.Errorf("repoDb.Get: %w", err)
    }
    if !found {
        if errNE {
            return nil, false, errs.ObjectNotFound
        }
        return nil, false, nil
    }
    return result, found, nil
}

func (s *Service) Create(ctx context.Context, obj *model.Edit) (string, error) {
    obj.ModifiedAt = nil // DB-default устанавливает значение

    newId, err := s.repoDb.Create(ctx, obj)
    if err != nil {
        return "", fmt.Errorf("repoDb.Create: %w", err)
    }
    return newId, nil // id новой записи (правило для всех сущностей с id)
}

func (s *Service) Update(ctx context.Context, id string, obj *model.Edit) error {
    obj.ModifiedAt = new(time.Now())

    if err := s.repoDb.Update(ctx, id, obj); err != nil {
        return fmt.Errorf("repoDb.Update: %w", err)
    }
    return nil
}

func (s *Service) Delete(ctx context.Context, id string) error {
    if err := s.repoDb.Delete(ctx, id); err != nil {
        return fmt.Errorf("repoDb.Delete: %w", err)
    }
    return nil
}
```
