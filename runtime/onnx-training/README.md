# Neuralese On-Prem ONNX Training Runtime

## Коротко

Сделан первый рабочий MVP on-prem runtime для обучения ONNX-моделей.

Runtime принимает ONNX bundle, запускает обучение, стримит состояние через WebSocket и после завершения возвращает `snapshot.zip` с обученной моделью и метриками.

Это не отдельный inference-сервер. В этой задаче реализован именно training flow.

Для записи видео и быстрой проверки смотри [DEMO.md](DEMO.md).

## Что уже работает

- прием `.zip` ONNX bundle через API;
- валидация `manifest.json`, `model.onnx` и dataset-части;
- запуск training job;
- WebSocket progress stream;
- метрики по эпохам: loss, accuracy, epoch progress;
- остановка job через WebSocket;
- сборка strict `snapshot.zip`;
- скачивание snapshot после завершения;
- uploaded datasets внутри bundle;
- public dataset refs на стороне сервера;
- local dataset refs через incremental sync;
- persistent dataset sync cache после рестарта runtime;
- два режима запуска: `local_school` и `cloud_node`;
- optional auth token для HTTP API и WebSocket routes;
- понятные API errors с `code/message/action`;
- UI notice в dashboard для ошибок upload/refresh/stop/download;
- минимальный dashboard для школы;
- Docker deployment;
- systemd deployment docs для Linux-сервера без Docker;
- GitHub Actions CI для проверки `code-snapshot`;
- smoke test для local и Docker запуска;
- cleanup старых jobs/snapshots;
- тесты на основной runtime flow.

## Главный сценарий

```text
client / dashboard
  |
  | POST /api/jobs
  v
ONNX bundle upload
  |
  v
TrainingEngine
  |
  | WebSocket events
  v
queued -> started -> epoch -> completed
  |
  v
snapshot.zip
```

Пользователь отправляет bundle, подключается к WebSocket, видит прогресс обучения и в конце скачивает snapshot.

## Формат входного bundle

Минимально:

```text
bundle.zip
  manifest.json
  model.onnx
  data/train.npz
```

`train.npz` должен содержать:

```text
x
y
```

Также bundle может не хранить dataset внутри, а ссылаться на dataset через `dataset_ref`.

Пример public dataset:

```json
{
  "dataset_ref": {
    "type": "public",
    "id": "iris"
  }
}
```

Пример local dataset:

```json
{
  "dataset_ref": {
    "type": "local",
    "id": "school-dataset",
    "fingerprint": "sha256:..."
  }
}
```

## Формат результата

После успешного обучения сервер отдает:

```text
snapshot.zip
  manifest.json
  inference.onnx
  metrics.jsonl
  checkpoint/
```

Обязательные части успешного результата:

- `manifest.json`;
- `inference.onnx`;
- `metrics.jsonl`.

`checkpoint/` сохраняется, если ONNX Runtime Training смог его создать. Сам snapshot считается валидным только если есть обученная модель и метрики.

## Архитектура

Код разделен на независимые части:

```text
onprem_runtime/
  core/
  api/
  dashboard/
  deployment/
  examples/
```

`core` содержит training engine, bundle parsing, dataset resolving, sync cache, snapshot сборку и trainer adapter.

`api` содержит только HTTP/WebSocket слой поверх `core`.

`dashboard` содержит минимальный школьный UI.

`deployment` содержит Dockerfile, compose, env example, systemd service docs и smoke script.

`examples` содержит генератор dummy bundle для локальной проверки.

## Два режима API

### `local_school`

Режим для школы или локального on-prem запуска.

В этом режиме runtime:

- принимает bundle напрямую;
- хранит jobs и snapshots на локальном диске;
- показывает dashboard;
- может работать без Neuralese Cloud;
- использует локальные public datasets и synced local datasets.

### `cloud_node`

Режим worker-ноды для Neuralese Cloud.

В этом режиме runtime:

- использует тот же training core;
- может запускаться в нескольких экземплярах;
- имеет health/capacity endpoints;
- может отключать dashboard/direct upload;
- подходит как основа под scheduler/load balancing.

## API endpoints

Основные endpoints:

```text
POST /api/jobs
WS   /ws/jobs/{job_id}
GET  /api/jobs/{job_id}/snapshot
POST /api/jobs/cleanup?max_age_seconds=604800
GET  /api/health
GET  /api/capacity
GET  /api/datasets
WS   /ws/datasets/sync
GET  /
```

`GET /` отдает dashboard.

`/ws/datasets/sync` используется для incremental sync локальных датасетов.

Если задан `NEURALESE_AUTH_TOKEN`, protected HTTP routes требуют:

```text
Authorization: Bearer <token>
```

или:

```text
X-Neuralese-Token: <token>
```

Protected WebSocket routes принимают:

```text
?token=<token>
```

`/api/health` и dashboard static files остаются публичными, чтобы node можно было проверять health-check'ами и открывать UI.

## Как запустить локально на Linux x86-64

```bash
cd runtime/onnx-training/code-snapshot
python3 -m venv .venv
source .venv/bin/activate
pip install -r onprem_runtime/requirements.txt
python -m onprem_runtime --mode local_school --host 127.0.0.1 --port 8010
```

На macOS используйте Docker-инструкцию ниже: `onnxruntime-training-cpu==1.19.2` в этой конфигурации доступен как Linux `amd64` wheel.

Запуск с token:

```bash
python -m onprem_runtime \
  --mode local_school \
  --host 127.0.0.1 \
  --port 8010 \
  --auth-token school-secret
```

Dashboard:

```text
http://127.0.0.1:8010/
```

Создать demo bundle:

```bash
python -m onprem_runtime.examples.make_dummy_bundle /tmp/neuralese_dummy_bundle.zip --epochs 2
```

Потом bundle можно загрузить через dashboard или через `POST /api/jobs`.
Если server запущен с token, вставь token в поле `API token` в dashboard.

## Как проверить smoke test

Без Docker:

```bash
python onprem_runtime/deployment/smoke_test.py --launcher local --port 8125
```

С token:

```bash
python onprem_runtime/deployment/smoke_test.py \
  --launcher local \
  --port 8125 \
  --auth-token school-secret
```

Через Docker:

```bash
python onprem_runtime/deployment/smoke_test.py --launcher docker --port 8129 --timeout 360
```

Smoke test делает полный flow:

1. поднимает runtime;
2. создает dummy ONNX bundle;
3. отправляет bundle в API;
4. слушает WebSocket events;
5. ждет `completed`;
6. скачивает snapshot;
7. проверяет `manifest.json`, `inference.onnx` и `metrics.jsonl`.

## Docker

Docker-файлы лежат здесь:

```text
onprem_runtime/deployment/
```

Локальный запуск:

```bash
cd onprem_runtime/deployment
docker compose -f docker-compose.local.yml up --build
```

Compose закреплен на:

```text
platform: linux/amd64
```

Причина: используемый `onnxruntime-training-cpu==1.19.2` доступен как Linux amd64 wheel.

На Mac Docker проверялся через:

```text
docker
docker-compose
docker-buildx
colima
```

## Dataset flow

Есть три варианта dataset:

- `uploaded` - dataset лежит прямо внутри bundle;
- `public` - dataset хранится на сервере и подгружается по `dataset_ref`;
- `local` - dataset синхронизируется блоками через incremental sync и потом используется по fingerprint.

Для local datasets сделан persistent cache:

```text
<NEURALESE_STORAGE_DIR>/dataset_sync
```

Это нужно, чтобы после рестарта runtime не пересылать заново все блоки локального датасета.

## Cleanup

Добавлен cleanup endpoint:

```bash
curl -X POST "http://127.0.0.1:8010/api/jobs/cleanup?max_age_seconds=604800"
```

Он удаляет:

- старые completed/failed/stopped jobs;
- orphan workspaces после рестарта runtime.

Running/queued jobs cleanup не трогает.

## Dashboard

Минимальный dashboard показывает:

- runtime mode;
- backend;
- active jobs;
- total jobs;
- CPU/RAM;
- capacity slots;
- dataset cache;
- список jobs;
- loss/accuracy;
- snapshot status;
- error message для failed jobs;
- API token field для защищенного runtime;
- stop/download actions.

Dashboard сделан как простой рабочий экран для учителя или сисадмина, без landing-page логики.

Если API возвращает ошибку, ответ содержит человекочитаемый блок:

```json
{
  "detail": "Upload must be a .zip ONNX training bundle",
  "error": {
    "code": "invalid_bundle_type",
    "message": "Upload must be a .zip ONNX training bundle",
    "action": "Select a .zip bundle generated by Neuralese and upload it again."
  }
}
```

Dashboard показывает такие ошибки сверху как notice, чтобы на демо было понятно, что именно пошло не так и что делать дальше.

## Linux systemd

Для Linux-сервера без Docker добавлены:

```text
onprem_runtime/deployment/systemd/neuralese-onprem.service
onprem_runtime/deployment/systemd/neuralese-onprem.env.example
onprem_runtime/deployment/systemd/README.md
```

Основные команды:

```bash
sudo systemctl enable --now neuralese-onprem
journalctl -u neuralese-onprem -f
```

Это сценарий для школьной машины, где runtime должен стартовать как обычный сервис после перезагрузки.

## GitHub Actions CI

В исходном компоненте добавлен workflow:

```text
.github/workflows/onprem-runtime-tests.yml
```

В консолидированном репозитории тот же тест запускается из корневого `.github/workflows/component-tests.yml`, потому что GitHub Actions не обнаруживает workflow внутри вложенного snapshot.

Он ставит Python 3.11, устанавливает зависимости из `code-snapshot/onprem_runtime/requirements.txt` и запускает:

```bash
python -m pytest code-snapshot/tests/onprem_runtime -v
```

## Проверка

Основная команда:

```bash
cd runtime/onnx-training/code-snapshot
source .venv/bin/activate
python -m pytest tests/onprem_runtime -v
```

Текущий результат:

```text
95 passed
```

Также был прогнан Docker smoke test на Mac через Colima: контейнер собрался, training job дошел до `completed`, snapshot скачался и прошел проверку.

## Что осталось на следующий этап

Главное ограничение текущего MVP: поддержан первый понятный classification flow.

Дальше нужно расширять compatibility layer:

- regression;
- multilabel classification;
- разные loss functions;
- разные input/output shapes;
- модели с несколькими inputs/outputs;
- более строгие dataset contracts;
- upload/job limits;
- cloud scheduler integration.

Это не требует переписывать архитектуру. Основной runtime уже разделен так, чтобы новые trainer adapters и validators добавлялись отдельно.

## Что можно показать как прогресс

Можно показать рабочий vertical slice:

```text
upload bundle -> train -> WebSocket progress -> snapshot download
```

И отдельно:

- Docker deployment;
- systemd deployment;
- GitHub Actions CI;
- dashboard;
- local/cloud mode profiles;
- dataset refs;
- incremental dataset sync;
- persistent sync cache;
- cleanup старых jobs;
- test suite.

Это уже не просто план, а рабочая основа on-prem training runtime, которую можно дальше расширять под больше типов ONNX-моделей и production-требования.
