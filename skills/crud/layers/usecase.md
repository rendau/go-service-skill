# Layer: Usecase — `internal/usecase/<entity>/`

Оркестрация, валидация, авторизация. Входная точка от transport-слоя.

## Файлы

| Файл | Назначение |
|---|---|
| `interfaces.go` | публичный `ServiceI` интерфейс зависимости |
| `usecase.go` | `Usecase` struct, `New()`, бизнес-методы |

## Правила
- `ServiceI` интерфейс — **публичный** (uppercase), объявляется в `interfaces.go`
- Включай в интерфейс **только методы, которые реально используются** в usecase
- `Update` и `Delete` проверяют `id == ""` → `errs.IdRequired`
- Валидация — приватный метод `validateEdit(obj, forCreate bool) error`
- Auth/permissions — добавляется в mutable методы (`// TODO: check auth/permissions`)
- Ошибки: `fmt.Errorf("svc.<Method>: %w", err)`

## interfaces.go

```go
package <entity>

import (
    "context"
    "github.com/<module>/internal/domain/<entity>/model"
)

type ServiceI interface {
    List(ctx context.Context, pars *model.ListReq) ([]*model.Main, int64, error)
    Get(ctx context.Context, id string, errNE bool) (*model.Main, bool, error)
    Create(ctx context.Context, obj *model.Edit) (string, error)
    Update(ctx context.Context, id string, obj *model.Edit) error
    Delete(ctx context.Context, id string) error
}
```

## usecase.go

```go
package <entity>

import (
    "context"
    "fmt"

    "github.com/<module>/internal/domain/common/util"
    "github.com/<module>/internal/domain/<entity>/model"
    "github.com/<module>/internal/errs"
)

type Usecase struct {
    svc ServiceI
}

func New(svc ServiceI) *Usecase {
    return &Usecase{svc: svc}
}

func (u *Usecase) validateEdit(obj *model.Edit, forCreate bool) error {
    // валидация полей, возвращай errs.* при невалидных данных
    return nil
}

func (u *Usecase) List(ctx context.Context, pars *model.ListReq) ([]*model.Main, int64, error) {
    if err := util.RequirePageSize(pars.ListParams, 0); err != nil {
        return nil, 0, err
    }
    items, tCount, err := u.svc.List(ctx, pars)
    if err != nil {
        return nil, 0, fmt.Errorf("svc.List: %w", err)
    }
    return items, tCount, nil
}

func (u *Usecase) Get(ctx context.Context, id string) (*model.Main, error) {
    result, _, err := u.svc.Get(ctx, id, true)
    if err != nil {
        return nil, fmt.Errorf("svc.Get: %w", err)
    }
    return result, nil
}

func (u *Usecase) Create(ctx context.Context, obj *model.Edit) (string, error) {
    // TODO: check auth/permissions
    if err := u.validateEdit(obj, true); err != nil {
        return "", err
    }
    newId, err := u.svc.Create(ctx, obj)
    if err != nil {
        return "", fmt.Errorf("svc.Create: %w", err)
    }
    return newId, nil // id новой записи (правило для всех сущностей с id)
}

func (u *Usecase) Update(ctx context.Context, id string, obj *model.Edit) error {
    if id == "" {
        return errs.IdRequired
    }
    // TODO: check auth/permissions
    if err := u.validateEdit(obj, false); err != nil {
        return err
    }
    if err := u.svc.Update(ctx, id, obj); err != nil {
        return fmt.Errorf("svc.Update: %w", err)
    }
    return nil
}

func (u *Usecase) Delete(ctx context.Context, id string) error {
    if id == "" {
        return errs.IdRequired
    }
    // TODO: check auth/permissions
    if err := u.svc.Delete(ctx, id); err != nil {
        return fmt.Errorf("svc.Delete: %w", err)
    }
    return nil
}
```
