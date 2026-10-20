# Layer: Usecase — `internal/usecase/<entity>/`

Оркестрация, валидация, авторизация. Входная точка от transport-слоя.

## Файлы

| Файл | Назначение |
|---|---|
| `interfaces.go` | публичный `ServiceI` — интерфейс зависимости (domain service) |
| `usecase.go` | `Usecase` struct, `New()`, бизнес-методы |

## Правила
- `ServiceI` — **публичный**, объявляется в `interfaces.go`. Это интерфейс того, от чего зависит
  usecase; интерфейс самого usecase не нужен — handler подключает `*Usecase` напрямую
- Включай в `ServiceI` **только методы, которые реально используются** в usecase
- `Update` и `Delete` проверяют пустой id → `errs.IdRequired` (`id == 0` для `int64`, `id == ""` для `string`)
- **Обязательность полей проверяет usecase**: в proto все поля Create/Update `optional`.
  Приватный метод `validateEdit(obj, forCreate bool) error`: при `forCreate` обязательные поля
  должны быть заданы (`!= nil`), при Update проверяются только переданные
- Кейсы PK 3, 4 (id только из запроса): `Create` требует `obj.Id`
- Ошибки валидации — `errs.Err`; с описанием поля — `errs.ErrFull{Err: errs.InvalidRequest, Desc: ..., Fields: ...}`
- `List` проверяет размер страницы: `util.RequirePageSize(pars.ListParams, 0)` (`internal/util`)
- Auth/permissions — в mutable методах (`// TODO: check auth/permissions`)
- Ошибки сервиса оборачиваются: `fmt.Errorf("svc.<Method>: %w", err)`

> Create без единого поля упадёт в squirrel (`insert statements must have at least one set of
> values`). Обычно это закрывает проверка обязательных полей в `validateEdit`.

## interfaces.go

```go
package <entity>

import (
	"context"

	"github.com/<module>/internal/domain/<entity>/model"
)

type ServiceI interface {
	List(ctx context.Context, pars *model.ListReq) ([]*model.Main, int64, error)
	Get(ctx context.Context, id <idType>, errNE bool) (*model.Main, bool, error)
	Create(ctx context.Context, obj *model.Edit) (<idType>, error)
	Update(ctx context.Context, id <idType>, obj *model.Edit) error
	Delete(ctx context.Context, id <idType>) error
}
```

## usecase.go

```go
package <entity>

import (
	"context"
	"fmt"

	"github.com/<module>/internal/domain/<entity>/model"
	"github.com/<module>/internal/errs"
	"github.com/<module>/internal/util"
)

type Usecase struct {
	svc ServiceI
}

func New(svc ServiceI) *Usecase {
	return &Usecase{svc: svc}
}

func (u *Usecase) validateEdit(obj *model.Edit, forCreate bool) error {
	// кейсы PK 3, 4 — id обязателен при Create:
	// if forCreate && (obj.Id == nil || *obj.Id == <zeroId>) {
	// 	return errs.ErrFull{Err: errs.InvalidRequest, Desc: "id is required", Fields: map[string]string{"id": "required"}}
	// }
	if forCreate || obj.Name != nil {
		if obj.Name == nil || *obj.Name == "" {
			return errs.ErrFull{Err: errs.InvalidRequest, Desc: "name is required", Fields: map[string]string{"name": "required"}}
		}
	}
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

func (u *Usecase) Get(ctx context.Context, id <idType>) (*model.Main, error) {
	result, _, err := u.svc.Get(ctx, id, true)
	if err != nil {
		return nil, fmt.Errorf("svc.Get: %w", err)
	}
	return result, nil
}

func (u *Usecase) Create(ctx context.Context, obj *model.Edit) (<idType>, error) {
	// TODO: check auth/permissions
	if err := u.validateEdit(obj, true); err != nil {
		return <zeroId>, err
	}
	newId, err := u.svc.Create(ctx, obj)
	if err != nil {
		return <zeroId>, fmt.Errorf("svc.Create: %w", err)
	}
	return newId, nil
}

func (u *Usecase) Update(ctx context.Context, id <idType>, obj *model.Edit) error {
	if id == <zeroId> {
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

func (u *Usecase) Delete(ctx context.Context, id <idType>) error {
	if id == <zeroId> {
		return errs.IdRequired
	}
	// TODO: check auth/permissions
	if err := u.svc.Delete(ctx, id); err != nil {
		return fmt.Errorf("svc.Delete: %w", err)
	}
	return nil
}
```
