# Layer: gRPC Handler + DTO — `internal/handler/grpc/`

Transport-слой. Принимает protobuf, вызывает usecase, возвращает protobuf.

## Файлы

| Файл | Назначение |
|---|---|
| `<entity>.go` | gRPC handler struct + CRUD методы |
| `dto/<entity>.go` | конвертеры proto↔domain |

## Правила
- Handler embed-ит `<proto_pkg>.Unsafe<Entity>Server` — обязательно (имя из proto: `service <Entity>Service` → `Unsafe<Entity>Server`)
- Ошибки из usecase возвращаются напрямую (interceptor обрабатывает `errs.*`)
- gRPC DTO **не протекают** в usecase и domain слои
- `Decode*` — proto → domain (входящие запросы)
- `Encode*` — domain → proto (исходящие ответы), сигнатура совместима с `lo.Map`: `func(v *model.Main, _ int) *proto.<Entity>Main`
- `Get` возвращает `*proto.<Entity>Main` напрямую (не в wrapper-сообщении)
- `Create` возвращает `*proto.<Entity>CreateRep{Id: newId}` с id новой записи (правило для всех сущностей с id), а не `emptypb.Empty`
- `Update` передаёт `id` отдельным параметром в usecase: `h.usecase.Update(ctx, req.Id, dto.Decode...)`
- В `handler` и `dto` **максимально используй `lo`** вместо ручных циклов: маппинг срезов
  через `lo.Map(items, dto.Encode<Entity>Main)`, а также `lo.Filter`, `lo.GroupBy`, `lo.KeyBy`,
  `lo.SliceToMap`, `lo.FromPtr` и т.п. Никаких `for`-циклов с ручным `append`
  для конвертации proto↔domain. Паттерны — в skill `golang-samber-lo`.
- **Не заводи временную переменную только ради того, чтобы взять её адрес** — указатель на
  значение/литерал/выражение получай через `new(...)` (`new(expr)`), а не через `lo.ToPtr(...)`
  и не через `tmp := expr; &tmp`.

## <entity>.go

```go
package grpc

import (
    "context"

    "github.com/<module>/pkg/proto/common"
    
    "github.com/samber/lo"
    "google.golang.org/protobuf/types/known/emptypb"

    "github.com/<module>/internal/handler/grpc/dto"
    usecase "github.com/<module>/internal/usecase/<entity>"
    proto "github.com/<module>/pkg/proto/<svc_name>_v1"
)

type <Entity> struct {
    proto.Unsafe<Entity>Server
    usecase *usecase.Usecase
}

func New<Entity>(uc *usecase.Usecase) *<Entity> {
    return &<Entity>{usecase: uc}
}

func (h *<Entity>) List(ctx context.Context, req *proto.<Entity>ListReq) (*proto.<Entity>ListRep, error) {
    if req.ListParams == nil {
        req.ListParams = &common.ListParamsSt{}
    }

    items, tCount, err := h.usecase.List(ctx, dto.Decode<Entity>ListReq(req))
    if err != nil {
        return nil, err
    }

    return &proto.<Entity>ListRep{
        PaginationInfo: &common.PaginationInfoSt{
            Page:       req.ListParams.Page,
            PageSize:   req.ListParams.PageSize,
            TotalCount: tCount,
        },
        Results: lo.Map(items, dto.Encode<Entity>Main),
    }, nil
}

func (h *<Entity>) Get(ctx context.Context, req *proto.<Entity>GetReq) (*proto.<Entity>Main, error) {
    item, err := h.usecase.Get(ctx, req.Id)
    if err != nil {
        return nil, err
    }
    return dto.Encode<Entity>Main(item, 0), nil
}

// Create возвращает id новой записи (правило для всех сущностей с id)
func (h *<Entity>) Create(ctx context.Context, req *proto.<Entity>CreateReq) (*proto.<Entity>CreateRep, error) {
    newId, err := h.usecase.Create(ctx, dto.Decode<Entity>CreateReq(req))
    if err != nil {
        return nil, err
    }
    return &proto.<Entity>CreateRep{Id: newId}, nil
}

func (h *<Entity>) Update(ctx context.Context, req *proto.<Entity>UpdateReq) (*emptypb.Empty, error) {
    if err := h.usecase.Update(ctx, req.Id, dto.Decode<Entity>UpdateReq(req)); err != nil {
        return nil, err
    }
    return &emptypb.Empty{}, nil
}

func (h *<Entity>) Delete(ctx context.Context, req *proto.<Entity>GetReq) (*emptypb.Empty, error) {
    if err := h.usecase.Delete(ctx, req.Id); err != nil {
        return nil, err
    }
    return &emptypb.Empty{}, nil
}
```

## dto/<entity>.go

```go
package dto

import (
    "google.golang.org/protobuf/types/known/timestamppb"

    domainModel "github.com/<module>/internal/domain/<entity>/model"
    proto "github.com/<module>/pkg/proto/<svc_name>_v1"
)

// domain → proto

func Encode<Entity>Main(v *domainModel.Main, _ int) *proto.<Entity>Main {
    if v == nil {
        return nil
    }
    return &proto.<Entity>Main{
        Id:         v.Id,
        CreatedAt:  timestamppb.New(v.CreatedAt),
        ModifiedAt: timestamppb.New(v.ModifiedAt),
        Active:     v.Active,
        Name:       v.Name,
    }
}

// proto → domain

func Decode<Entity>ListReq(v *proto.<Entity>ListReq) *domainModel.ListReq {
    if v == nil {
        return nil
    }
    return &domainModel.ListReq{
        ListParams: DecodeListParams(v.ListParams),
        // фильтры по необходимости:
        // Active: v.Active,
    }
}

func Decode<Entity>CreateReq(v *proto.<Entity>CreateReq) *domainModel.Edit {
    if v == nil {
        return nil
    }
    return &domainModel.Edit{
        Active: v.Active,
        Name:   v.Name,
    }
}

func Decode<Entity>UpdateReq(v *proto.<Entity>UpdateReq) *domainModel.Edit {
    if v == nil {
        return nil
    }
    return &domainModel.Edit{
        Active: v.Active,
        Name:   v.Name,
    }
}
```

> **Примечание:** `req.Id` при Update передаётся напрямую в `h.usecase.Update(ctx, req.Id, ...)`, поэтому в `Decode<Entity>UpdateReq` поле `Id` не заполняется.
