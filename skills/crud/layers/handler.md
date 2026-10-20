# Layer: gRPC Handler + DTO — `internal/handler/grpc/`

Transport-слой. Принимает protobuf, вызывает usecase, возвращает protobuf. Handler тонкий:
только конвертация proto↔domain и вызов usecase.

## Файлы

| Файл | Назначение |
|---|---|
| `<entity>.go` | handler struct `<Entity>` + CRUD методы |
| `dto/<entity>.go` | конвертеры proto↔domain сущности |
| `dto/common.go` | есть в gotemplate: `DecodeListParams`, `JsonObjToGrpcStruct`, `GrpcStructToJsonObj` |

Handler-ы и dto всех сущностей лежат в одних и тех же пакетах — поэтому имена типов, конструкторов
и dto-функций с префиксом `<Entity>`. Методы handler-а — имена RPC без префикса (`List`, `Get`, …):
у каждой сущности свой struct.

## Правила
- Handler — struct `<Entity>`, конструктор `New<Entity>(uc *usecase.Usecase)`
- Handler подключает usecase **прямым экземпляром** `*usecase.Usecase`, без интерфейса
- Embed `proto.Unsafe<Entity>ServiceServer` — обязательно (protoc-gen-go-grpc генерирует
  `Unsafe` + имя service: `service <Entity>Service` → `Unsafe<Entity>ServiceServer`)
- **Не объединяй сущности в один handler-struct**: методы `List` двух сервисов на одном struct не скомпилируются
- Ошибки из usecase возвращаются как есть (interceptor обрабатывает `errs.*`)
- gRPC DTO **не протекают** в usecase и domain слои
- Поля запроса читай через getter-ы (`req.GetId()`, `v.GetListParams()`) — они nil-safe
- `Decode*` — proto → domain: `optional`-поля передаются указателями как есть (`Name: v.Name`);
  фильтр по списку — `lo.EmptyableToPtr(v.GetIds())` (пустой список из запроса = фильтра нет)
- `Encode*` — domain → proto, сигнатура совместима с `lo.Map`: `func(v *model.Main, _ int) *proto.<Entity>Main`
- `Get` возвращает `*proto.<Entity>Main` напрямую
- `Create` возвращает `&proto.<Entity>CreateRep{Id: newId}`
- `Update` передаёт текущий id отдельным параметром: `h.usecase.Update(ctx, req.GetId(), dto.Decode<Entity>UpdateReq(req))`
- **Максимально используй `lo`** вместо ручных циклов: `lo.Map(items, dto.Encode<Entity>Main)`,
  `lo.Filter`, `lo.KeyBy`, `lo.SliceToMap` и т.п. Паттерны — в skill `golang-samber-lo`
- **Не заводи временную переменную ради адреса** — `new(expr)`, а не `lo.ToPtr(...)` и не `tmp := x; &tmp`

## <entity>.go

```go
package grpc

import (
	"context"

	"github.com/samber/lo"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/<module>/internal/handler/grpc/dto"
	usecase "github.com/<module>/internal/usecase/<entity>"
	"github.com/<module>/pkg/proto/common"
	proto "github.com/<module>/pkg/proto/<svc_name>_v1"
)

type <Entity> struct {
	proto.Unsafe<Entity>ServiceServer
	usecase *usecase.Usecase
}

func New<Entity>(uc *usecase.Usecase) *<Entity> {
	return &<Entity>{usecase: uc}
}

func (h *<Entity>) List(ctx context.Context, req *proto.<Entity>ListReq) (*proto.<Entity>ListRep, error) {
	items, tCount, err := h.usecase.List(ctx, dto.Decode<Entity>ListReq(req))
	if err != nil {
		return nil, err
	}
	return &proto.<Entity>ListRep{
		PaginationInfo: &common.PaginationInfoSt{
			Page:       req.GetListParams().GetPage(),
			PageSize:   req.GetListParams().GetPageSize(),
			TotalCount: tCount,
		},
		Results: lo.Map(items, dto.Encode<Entity>Main),
	}, nil
}

func (h *<Entity>) Get(ctx context.Context, req *proto.<Entity>GetReq) (*proto.<Entity>Main, error) {
	item, err := h.usecase.Get(ctx, req.GetId())
	if err != nil {
		return nil, err
	}
	return dto.Encode<Entity>Main(item, 0), nil
}

func (h *<Entity>) Create(ctx context.Context, req *proto.<Entity>CreateReq) (*proto.<Entity>CreateRep, error) {
	newId, err := h.usecase.Create(ctx, dto.Decode<Entity>CreateReq(req))
	if err != nil {
		return nil, err
	}
	return &proto.<Entity>CreateRep{Id: newId}, nil
}

func (h *<Entity>) Update(ctx context.Context, req *proto.<Entity>UpdateReq) (*emptypb.Empty, error) {
	if err := h.usecase.Update(ctx, req.GetId(), dto.Decode<Entity>UpdateReq(req)); err != nil {
		return nil, err
	}
	return &emptypb.Empty{}, nil
}

func (h *<Entity>) Delete(ctx context.Context, req *proto.<Entity>GetReq) (*emptypb.Empty, error) {
	if err := h.usecase.Delete(ctx, req.GetId()); err != nil {
		return nil, err
	}
	return &emptypb.Empty{}, nil
}
```

## dto/<entity>.go

```go
package dto

import (
	"github.com/samber/lo"
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
		Name:       v.Name,
		Active:     v.Active,
	}
}

// proto → domain

func Decode<Entity>ListReq(v *proto.<Entity>ListReq) *domainModel.ListReq {
	return &domainModel.ListReq{
		ListParams: DecodeListParams(v.GetListParams()),
		Active:     v.Active,
		Name:       v.Name,
		IDs:        lo.EmptyableToPtr(v.GetIds()),
	}
}

func Decode<Entity>CreateReq(v *proto.<Entity>CreateReq) *domainModel.Edit {
	return &domainModel.Edit{
		// Id: v.Id, ← кейсы PK 3–5
		Name:   v.Name,
		Active: v.Active,
	}
}

func Decode<Entity>UpdateReq(v *proto.<Entity>UpdateReq) *domainModel.Edit {
	return &domainModel.Edit{
		// Id: v.Id, ← только при смене PK через PUT
		Name:   v.Name,
		Active: v.Active,
	}
}
```

## Смена PK через PUT

Если в proto путь `PUT /<entity>/{req_id}` и в `<Entity>UpdateReq` есть `req_id` и `optional id`
(см. `proto.md`), то текущий id — `req.GetReqId()`, а новый уходит в `Edit.Id`:

```go
func (h *<Entity>) Update(ctx context.Context, req *proto.<Entity>UpdateReq) (*emptypb.Empty, error) {
	if err := h.usecase.Update(ctx, req.GetReqId(), dto.Decode<Entity>UpdateReq(req)); err != nil {
		return nil, err
	}
	return &emptypb.Empty{}, nil
}

func Decode<Entity>UpdateReq(v *proto.<Entity>UpdateReq) *domainModel.Edit {
	return &domainModel.Edit{
		Id:     v.Id, // новый id (nil — не меняется)
		Name:   v.Name,
		Active: v.Active,
	}
}
```
