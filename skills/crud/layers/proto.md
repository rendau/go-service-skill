# Layer: Proto — `api/proto/<svc_name>_v1/<entity>.proto`

gRPC + HTTP-gateway контракт для CRUD-сущности. После редактирования запускай `make generate-proto`.

## Соглашения

| Что | Правило |
|---|---|
| Файл | `api/proto/<svc_name>_v1/<entity>.proto` — по файлу на сущность |
| Package | `<svc_name>_v1` (общий для всех сущностей сервиса) |
| go_package | `/<svc_name>_v1` |
| Service | `<Entity>Service` — свой сервис на каждую сущность |
| RPC | `List`, `Get`, `Create`, `Update`, `Delete` |
| Messages | с префиксом: `<Entity>Main`, `<Entity>ListReq`, `<Entity>ListRep`, `<Entity>GetReq`, `<Entity>CreateReq`, `<Entity>CreateRep`, `<Entity>UpdateReq` |
| Get | возвращает `<Entity>Main` напрямую |
| Delete | принимает `<Entity>GetReq`; `<Entity>DeleteReq` — когда появятся свои поля |
| Update / Delete | возвращают `google.protobuf.Empty`; `<Entity>UpdateRep` / `<Entity>DeleteRep` — когда нужно что-то вернуть |
| Поля Create / Update | **все** `optional` (partial create и partial update) |
| HTTP | только если сервису нужен HTTP (см. «Транспорт» в `SKILL.md`) |
| HTTP URL | единственное число, без plural: `/<entity>`, `/<entity>/{id}` |
| HTTP update | `put` (не `patch`) |
| Timestamps | `google.protobuf.Timestamp` |
| List params / Pagination | `common.ListParamsSt` / `common.PaginationInfoSt` из `common/common.proto` |

## Шаблон (кейс PK 1, gRPC + HTTP)

```proto
syntax = "proto3";

package <svc_name>_v1;

import "google/api/annotations.proto";
import "google/protobuf/empty.proto";
import "google/protobuf/timestamp.proto";
import "common/common.proto";

option go_package = "/<svc_name>_v1";

service <Entity>Service {
  rpc List(<Entity>ListReq) returns (<Entity>ListRep) {
    option (google.api.http) = {
      get: "/<entity>"
    };
  }

  rpc Get(<Entity>GetReq) returns (<Entity>Main) {
    option (google.api.http) = {
      get: "/<entity>/{id}"
    };
  }

  // Create возвращает id созданной записи
  rpc Create(<Entity>CreateReq) returns (<Entity>CreateRep) {
    option (google.api.http) = {
      post: "/<entity>"
      body: "*"
    };
  }

  rpc Update(<Entity>UpdateReq) returns (google.protobuf.Empty) {
    option (google.api.http) = {
      put: "/<entity>/{id}"
      body: "*"
    };
  }

  rpc Delete(<Entity>GetReq) returns (google.protobuf.Empty) {
    option (google.api.http) = {
      delete: "/<entity>/{id}"
    };
  }
}

message <Entity>Main {
  <idType> id = 1;
  google.protobuf.Timestamp created_at = 2;
  google.protobuf.Timestamp modified_at = 3;
  string name = 4;
  bool active = 5;
}

// List

message <Entity>ListReq {
  common.ListParamsSt list_params = 1;
  optional bool active = 2;      // фильтр (опционально)
  optional string name = 3;      // фильтр ILIKE (опционально)
  repeated <idType> ids = 4;     // фильтр по массиву id (опционально)
}

message <Entity>ListRep {
  common.PaginationInfoSt pagination_info = 1;
  repeated <Entity>Main results = 2;
}

// Get (и Delete)

message <Entity>GetReq {
  <idType> id = 1;
}

// Create — все поля optional: не передали → DB-default; обязательность проверяет usecase

message <Entity>CreateReq {
  optional string name = 1;
  optional bool active = 2;
}

message <Entity>CreateRep {
  <idType> id = 1;
}

// Update — все изменяемые поля optional для partial update

message <Entity>UpdateReq {
  <idType> id = 1;
  optional string name = 2;
  optional bool active = 3;
}
```

## Только gRPC

Убери `import "google/api/annotations.proto";` и все блоки `option (google.api.http)`:

```proto
service <Entity>Service {
  rpc List(<Entity>ListReq) returns (<Entity>ListRep);
  rpc Get(<Entity>GetReq) returns (<Entity>Main);
  rpc Create(<Entity>CreateReq) returns (<Entity>CreateRep);
  rpc Update(<Entity>UpdateReq) returns (google.protobuf.Empty);
  rpc Delete(<Entity>GetReq) returns (google.protobuf.Empty);
}
```

`make generate-proto` тогда не создаёт `<entity>.pb.gw.go`, и `Register<Entity>ServiceHandler` нет.

## id в Create (кейсы PK 3–5)

Добавь в `<Entity>CreateReq` поле `id` (свободный номер — в конце):

```proto
message <Entity>CreateReq {
  optional string name = 1;
  optional bool active = 2;
  optional <idType> id = 3;  // из запроса; обязательность (кейсы 3, 4) проверяет usecase
}
```

## Смена PK через PUT

По умолчанию id через Update не меняется. Если меняться должен: в пути `{req_id}` — текущий id
(механика бэка, фронт о нём не знает), а новое значение приходит в body в привычном поле `id`.

```proto
  rpc Update(<Entity>UpdateReq) returns (google.protobuf.Empty) {
    option (google.api.http) = {
      put: "/<entity>/{req_id}"
      body: "*"
    };
  }

message <Entity>UpdateReq {
  <idType> req_id = 1;          // текущий id — из пути
  optional <idType> id = 2;     // новое значение id — из body
  optional string name = 3;
  optional bool active = 4;
}
```

Почему не `{id}` в пути и `id` в body: gateway сначала разбирает body, потом перезаписывает поле
значением из пути, и новый id из body теряется.

Если на PK ссылаются другие таблицы, у их FK нужен `on update cascade`, иначе Postgres откажет в смене.

## После создания proto

```bash
make generate-proto
```

Это создаёт/обновляет файлы в `pkg/proto/<svc_name>_v1/` и `docs/api.swagger.json`:
- `<entity>.pb.go` — сообщения
- `<entity>_grpc.pb.go` — `<Entity>ServiceServer`, `Unsafe<Entity>ServiceServer`, `Register<Entity>ServiceServer`
- `<entity>.pb.gw.go` — HTTP-gateway `Register<Entity>ServiceHandler` (только при HTTP-аннотациях)

Новый `.proto` в существующем пакете подхватывается автоматически. Для **нового пакета**
проверь `SERVICE_NAME = <svc_name>_v1` в Makefile — должен совпадать с папкой в `api/proto/`.

## Привязка к Go-коду

```go
import (
	"github.com/<module>/pkg/proto/common"
	proto "github.com/<module>/pkg/proto/<svc_name>_v1" // в handler и dto
)
```

Регистрация в `internal/app/app.go` — см. `SKILL.md`.

## Маппинг proto → Go

| proto | Go (сгенерированный) | В domain |
|---|---|---|
| `optional string` / `optional bool` / `optional int64` | `*string` / `*bool` / `*int64` | `v.X` как есть |
| `string` / `int64` (id в `GetReq`) | `string` / `int64` | `v.GetId()` |
| `repeated <idType>` | `[]<idType>` (пустой список приходит как `nil`) | `lo.EmptyableToPtr(v.GetIds())` → `*[]<idType>` |
| `google.protobuf.Timestamp` | `*timestamppb.Timestamp` | `.AsTime()` ↔ `timestamppb.New(t)` |
| `common.ListParamsSt` | `*common.ListParamsSt` | `dto.DecodeListParams(v.GetListParams())` |
| `google.protobuf.Struct` | `*structpb.Struct` | `dto.GrpcStructToJsonObj(v)` ↔ `dto.JsonObjToGrpcStruct(b)` (`[]byte` JSON) |

> В JSON gateway отдаёт `int64` строкой (`"id":"1"`) — это стандарт protojson.
