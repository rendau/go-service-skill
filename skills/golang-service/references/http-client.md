# HTTP-транспорт клиентов внешних систем

Модули-клиенты внешних HTTP-API **не используют общий http-хелпер/обёртку** — каждый модуль строит
запросы на стандартном `net/http` через **свой приватный метод `sendRequest`** (на `*Service` или
`*repo`).

## `sendRequest` — единственная точка отправки

Этот метод берёт на себя:
- сборку URI (`base + path`);
- сериализацию `reqObj` в JSON;
- авторизацию (Bearer-заголовок или ключ в query — как требует API);
- общие заголовки/query-параметры;
- проверку статус-кода (не-2xx → ошибка с обёрткой `errs.ServiceNA`);
- десериализацию тела ответа в `repObj`;
- при необходимости — «конверт»-структуру: распаковывает ответ из конверта или, наоборот,
  заворачивает запрос в него.

Сигнатура подгоняется под нужды модуля (`pars`, `headers`, флаг логирования и т.п. добавляются
только если нужны). Типичная форма:

```go
func (s *Service) sendRequest(
	ctx context.Context,
	method, path string,
	reqObj, repObj any,
) ([]byte, error)
```

- Публичные методы модуля **только** готовят `reqObj`/`pars` и зовут `sendRequest`; ручной работы с
  `http.Request`/`json.Marshal`/чтением тела в них нет.
- Абсолютные URL (готовые подписанные ссылки на результат) `sendRequest` использует как есть — без
  дописывания base/ключа/query.

## Несколько провайдеров

Если модуль ходит в **несколько провайдеров/upstream'ов** (разные base URL/токены) — делается
**отдельный метод на провайдера** (`send<Provider>Request`), а общая транспортная механика выносится
в приватный `doRequest`.

## Настройка `http.Client`

`http.Client` в конструкторе настраивается **явно** (не дефолтный): общий `Timeout`, а в
`&http.Transport{}` — `DialContext` с `net.Dialer{Timeout}`, `TLSHandshakeTimeout`,
`TLSClientConfig{InsecureSkipVerify}` и `MaxIdleConnsPerHost`. Конкретные значения — по ситуации
модуля (`InsecureSkipVerify` — только там, где это осознанно нужно).

```go
&http.Client{
	Timeout: 15 * time.Second,
	Transport: &http.Transport{
		DialContext:         (&net.Dialer{Timeout: 2 * time.Second}).DialContext,
		TLSHandshakeTimeout: 2 * time.Second,
		TLSClientConfig:     &tls.Config{InsecureSkipVerify: true},
		MaxIdleConnsPerHost: 20,
	},
}
```
