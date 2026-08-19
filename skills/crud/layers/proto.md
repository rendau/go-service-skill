# Layer: Proto — `api/proto/<svc_name>_v1/<entity>.proto`

gRPC + HTTP-gateway контракт для CRUD-сущности. После редактирования запускай `make generate-proto`.

## Соглашения

| Что | Правило |
|---|---|
| Файл | `api/proto/<svc_name>_v1/<entity>.proto` |
| Package | `<svc_name>_v1` |
| go_package | `/<svc_name>_v1` |
| HTTP URL | snake_case множественного числа: `/entities` |
| Поля Update | `optional` для partial update (proto3 optional) |
| Timestamps | `google.protobuf.Timestamp` |
| List params | `common.ListParamsSt` из `common/common.proto` |
| Pagination | `common.PaginationInfoSt` из `common/common.proto` |

## Шаблон

```proto
syntax = "proto3";

package <svc_name>_v1;

import "google/api/annotations.proto";
import "google/protobuf/empty.proto";
import "google/protobuf/timestamp.proto";
import "common/common.proto";

option go_package = "/<svc_name>_v1";

// REST-пути всегда в единственном числе, без plural: `/<entity>`, `/<entity>/{id}`.
service <Entity>Service {
  rpc List<Entity>s(List<Entity>sRequest) returns (List<Entity>sResponse) {
    option (google.api.http) = {
      get: "/<entity>"
    };
  }

  rpc Get<Entity>(Get<Entity>Request) returns (Get<Entity>Response) {
    option (google.api.http) = {
      get: "/<entity>/{id}"
    };
  }

  // Create возвращает id созданной записи (правило для всех сущностей с id)
  rpc Create<Entity>(Create<Entity>Request) returns (Create<Entity>Response) {
    option (google.api.http) = {
      post: "/<entity>"
      body: "*"
    };
  }

  rpc Update<Entity>(Update<Entity>Request) returns (google.protobuf.Empty) {
    option (google.api.http) = {
      put: "/<entity>/{id}"
      body: "*"
    };
  }

  rpc Delete<Entity>(Delete<Entity>Request) returns (google.protobuf.Empty) {
    option (google.api.http) = {
      delete: "/<entity>/{id}"
    };
  }
}

// ── Messages ────────────────────────────────────────────

message <Entity>Main {
  string id = 1;
  string name = 2;
  google.protobuf.Timestamp created_at = 3;
  google.protobuf.Timestamp updated_at = 4;
}

// List

message List<Entity>sRequest {
  common.ListParamsSt list_params = 1;
  optional string name = 2;        // фильтр (опционально)
  repeated string ids = 3;         // фильтр по массиву id (опционально)
}

message List<Entity>sResponse {
  common.PaginationInfoSt pagination_info = 1;
  repeated <Entity>Main results = 2;
}

// Get

message Get<Entity>Request {
  string id = 1;
}

message Get<Entity>Response {
  <Entity>Main <entity> = 1;
}

// Create

message Create<Entity>Request {
  string name = 1;
  // другие обязательные поля
}

// Create возвращает id новой записи. Тип id соответствует PK сущности:
//   int64  — для bigserial; string — для text/uuid.
message Create<Entity>Response {
  string id = 1; // или int64 id = 1; для bigserial
}

// Update — все изменяемые поля optional для partial update

message Update<Entity>Request {
  string id = 1;
  optional string name = 2;
  // другие изменяемые поля
}

// Delete

message Delete<Entity>Request {
  string id = 1;
}
```

## После создания proto

```bash
make generate-proto
```

Это создаёт/обновляет файлы в `pkg/proto/<svc_name>_v1/`:
- `<entity>.pb.go` — сообщения
- `<entity>_grpc.pb.go` — интерфейс сервиса
- `<entity>.pb.gw.go` — HTTP-gateway роутинг

## Регистрация нового Service в Makefile

Если добавляешь **новый** `.proto` файл в существующий пакет — ничего менять не надо,
`make generate-proto` подхватит все файлы из `api/proto/<svc_name>_v1/`.

Если добавляешь **новый пакет** (новый `<svc_name>_v1`) — проверь Makefile:
```makefile
SERVICE_NAME = <svc_name>_v1   # должен совпадать с именем папки в api/proto/
```

## Привязка к Go-коду

В handler `<entity>.go` импортируй сгенерированный пакет:

```go
import (
    proto "github.com/<module>/pkg/proto/<svc_name>_v1"
    commonProto "github.com/<module>/pkg/proto/common"
)
```

Регистрация в `internal/app/app.go`:

```go
proto.Register<Entity>ServiceServer(grpcServer, <entity>Handler)
```

## Маппинг DTO в handler

| proto тип | Go тип |
|---|---|
| `string` | `string` |
| `optional string` | `*string` (можно nil) |
| `google.protobuf.Timestamp` | `*timestamppb.Timestamp` → `time.Time` через `.AsTime()` |
| `common.ListParamsSt` | декодируй через `dto.DecodeListParams(v.ListParams)` |
| `repeated string` | `[]string` |

Конвертация timestamp в dto:

```go
// proto → domain
obj.CreatedAt = v.CreatedAt.AsTime()

// domain → proto
CreatedAt: timestamppb.New(v.CreatedAt),
```
