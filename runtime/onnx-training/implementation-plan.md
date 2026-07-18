# План реализации on-prem runtime для обучения ONNX-моделей

## 1. Коротко о задаче

Нужно сделать отдельный локальный серверный runtime для Neuralese, который умеет принимать ONNX bundle, запускать обучение модели, отправлять клиенту прогресс обучения в реальном времени и возвращать обученный snapshot обратно пользователю.

Главное ограничение: в этом runtime нужен только training. Inference в этой задаче не нужен.

Этот модуль должен быть независимым и встраиваемым. Его должно быть возможно запустить:

- на школьном компьютере или сервере в IT-кабинете;
- на локальном on-prem железе без зависимости от облака;
- внутри основного Neuralese backend как отдельный training-модуль.

У API должно быть два режима работы:

- `local_school` - локальный режим для школы, где runtime ставится на один компьютер или сервер и работает автономно;
- `cloud_node` - режим worker-ноды Neuralese Cloud, где runtime подключается к центральному backend, получает training jobs и должен нормально работать с очередями, health checks и load balancing.

Сама логика обучения в обоих режимах одна и та же. Отличается только внешний слой: как runtime регистрируется, как принимает задания, как отдает состояние и кто управляет распределением нагрузки.

## 2. Что должен делать runtime

Базовый сценарий:

1. Клиент отправляет серверу `.zip` bundle.
2. Сервер проверяет bundle и создает training job.
3. Сервер запускает обучение ONNX-модели.
4. Клиент подключается к WebSocket и получает состояние обучения:
   - job создан;
   - обучение началось;
   - epoch 1/10;
   - loss;
   - accuracy;
   - оставшееся количество эпох;
   - завершение или ошибка.
5. Пользователь может остановить обучение через WebSocket или HTTP endpoint.
6. Если обучение дошло до конца, сервер собирает snapshot.
7. Клиент скачивает snapshot с обученной моделью и метриками.

## 3. Что входит в ONNX bundle

Минимальный формат входного файла:

```text
bundle.zip
  manifest.json
  model.onnx
  data/train.npz
```

Опционально:

```text
data/val.npz
metadata/classes.json
```

Пример `manifest.json`:

```json
{
  "bundle_version": 1,
  "model_name": "digits-cnn",
  "task": "classification",
  "loss": "cross_entropy",
  "optimizer": "adamw",
  "learning_rate": 0.001,
  "epochs": 5,
  "batch_size": 64,
  "trainable_parameters": ["conv1.weight", "conv1.bias", "dense.weight", "dense.bias"],
  "input_name": "input",
  "label_name": "target",
  "output_names": ["logits"]
}
```

В `data/train.npz` должны быть массивы:

```text
x
y
```

`x` - входные данные.

`y` - правильные ответы.

## 4. Что входит в результат обучения

После завершения сервер должен собрать snapshot:

```text
snapshot.zip
  manifest.json
  inference.onnx
  metrics.jsonl
  checkpoint/
```

Где:

- `manifest.json` содержит итоговый статус, параметры обучения и информацию о модели;
- `inference.onnx` является обученной ONNX-моделью;
- `metrics.jsonl` содержит историю метрик по эпохам;
- `checkpoint/` содержит checkpoint, если ONNX Runtime смог его сохранить.

Даже если checkpoint сохранить не получилось, результат все равно считается полезным, если есть обученная модель и метрики.

## 5. Главная архитектурная идея

Нельзя делать один большой серверный файл, где перемешаны API, обучение, WebSocket и dashboard.

Нужно разделить проект на несколько независимых частей:

```text
onprem_runtime/
  core/
  api/
  dashboard/
  examples/
```

### `core`

Это главная часть. В ней находится логика обучения.

`core` не должен зависеть от FastAPI, WebSocket или dashboard.

Он должен уметь:

- принимать bundle;
- валидировать его;
- создавать training job;
- запускать trainer;
- хранить состояние job;
- отправлять события прогресса;
- обрабатывать stop;
- собирать snapshot.

Именно `core` должен быть встраиваемым модулем.

### `api`

Это тонкая серверная обертка поверх `core`.

Она отвечает за:

- HTTP upload bundle;
- WebSocket progress stream;
- остановку job;
- скачивание snapshot;
- выдачу статистики для dashboard.

API должен поддерживать два deployment profile:

1. `local_school`
   - принимает bundle напрямую от локального клиента;
   - хранит jobs и snapshots на локальном диске;
   - открывает dashboard для учителя или сисадмина;
   - не требует подключения к Neuralese Cloud для базовой работы;
   - может использовать публичные датасеты из локального cache или уже настроенные локальные датасеты школы.

2. `cloud_node`
   - работает как training worker внутри Neuralese Cloud;
   - не является главным источником правды по jobs;
   - принимает задания от центрального scheduler/backend;
   - регулярно отдает health/status;
   - должен уметь запускаться в нескольких экземплярах за load balancer;
   - snapshots и metrics после завершения отправляются обратно в центральное хранилище;
   - локальный dashboard можно отключить или оставить только как internal debug screen.

В обоих режимах `api` не должен содержать training logic. Он только вызывает `TrainingEngine` и адаптирует его под нужный способ запуска.

### `dashboard`

Минимальная веб-страница для учителя или сисадмина школы.

Она нужна не как полноценный продуктовый UI, а как простой контрольный экран:

- сколько jobs сейчас идет;
- какие jobs завершились;
- текущий loss и accuracy;
- CPU/RAM;
- кнопка остановки;
- кнопка скачивания результата.

### `examples`

Тестовые скрипты для локальной проверки.

Например, генератор маленького dummy bundle, чтобы можно было проверить runtime без Godot-клиента.

## 6. Предлагаемая структура файлов

```text
onprem_runtime/
  __init__.py
  requirements.txt
  README.md

  core/
    __init__.py
    bundle.py
    config.py
    dataset_compression.py
    datasets.py
    dataset_sync.py
    engine.py
    events.py
    jobs.py
    metrics.py
    ort_trainer.py
    snapshot.py

  api/
    __init__.py
    app.py
    dataset_routes.py
    profiles.py
    schemas.py

  dashboard/
    index.html
    styles.css
    app.js

  examples/
    make_dummy_bundle.py

tests/
  onprem_runtime/
    test_bundle.py
    test_dataset_compression_engine.py
    test_datasets.py
    test_dataset_sync.py
    test_events.py
    test_jobs.py
    test_profiles.py
    test_snapshot.py
```

## 7. Ответственность основных файлов

### `core/config.py`

Описывает настройки обучения:

- имя модели;
- количество epochs;
- batch size;
- optimizer;
- learning rate;
- loss;
- список trainable parameters;
- имена input/output.

### `core/bundle.py`

Отвечает за чтение и проверку bundle.

Проверяет:

- что файл является zip-архивом;
- что внутри есть `manifest.json`;
- что внутри есть `model.onnx`;
- что внутри есть `data/train.npz` или корректный `dataset_ref`;
- что в загруженном dataset есть `x` и `y`;
- что параметры обучения валидные.

### `core/datasets.py`

Отвечает за получение данных для обучения.

Главная идея: training engine не должен знать, откуда физически пришел dataset. Он должен работать через общий интерфейс `DatasetProvider`.

Нужны три варианта:

- `UploadedDatasetProvider` - если `train.npz` лежит прямо внутри bundle;
- `PublicDatasetProvider` - если выбран публичный датасет вроде MNIST, Iris, Titanic;
- `LocalDatasetProvider` - если датасет уже есть в локальном движке школы или пользователя.

Публичные датасеты можно хранить в cache на сервере. Если dataset уже есть и checksum совпадает, runtime не скачивает его заново.

Локальные датасеты не нужно постоянно пересылать вместе с bundle. В manifest достаточно передать `dataset_ref`, а provider уже найдет данные через существующий local dataset engine.

### `core/dataset_compression.py`

Повторяет compression contract текущего Godot dataset engine.

Этот файл нужен для unit tests и будущего incremental sync:

- выбирает размер blocks: `256`, `512`, `1024` rows;
- кодирует числовые колонки в 8/16/32-bit;
- кодирует float как `0..255`;
- кодирует text как UTF-8 + `NUL`;
- сохраняет image bytes как raw bytes;
- выбирает raw/RLE block;
- считает SHA-256 hash каждого encoded block.

Главная цель: runtime должен понимать тот же block format, что и клиент, чтобы сравнивать hashes и просить только изменившиеся blocks.

Из `neuralese-api` нужно переиспользовать текущий dataset flow:

- публичные датасеты отдаются через `GET /datasets`, список сейчас: `mnist`, `titanic`, `iris`, `car_track`;
- backend вызывает `record.ds_route.get_pub(...)` для публичного catalog;
- при запуске backend вызывается `record.ds_route.init_import()`;
- training flow использует `record.ds_route.has_dataset(...)`, `read_dataset(...)`, `has_test_dataset(...)`;
- локальный dataset передается не целиком, а блоками через WebSocket перед стартом training;
- сервер сравнивает `block_hashes` клиента с локальным cache и просит только недостающие или изменившиеся блоки;
- тяжелая декомпрессия локального dataset уже вынесена в Rust extension `worker/ds_decomp`.

Это значит, что в новом runtime не нужно придумывать второй dataset engine. Нужно сделать adapter слой поверх существующей схемы.

### `core/dataset_sync.py`

Реализует incremental sync локальных датасетов.

Текущий backend flow устроен так:

1. Клиент отправляет metadata:
   - `header`;
   - `dataset_id`;
   - `hash_algo`;
   - `block_hashes`.
2. Runtime смотрит свой cache по ключу:
   - `user_id`;
   - `dataset_id`;
   - side: `inputs` или `outputs`;
   - column index;
   - block index.
3. Runtime возвращает клиенту `need` map: какие блоки реально нужны.
4. Клиент отправляет только эти блоки.
5. Runtime обновляет локальный cache.
6. Runtime собирает packet:

```python
{
  "header": header,
  "data": [cached_inputs, cached_outputs]
}
```

7. Runtime декомпрессит packet через Rust decompressor и получает dataset rows.

Формат frame для блока нужно сохранить совместимым:

```text
2 bytes header length
JSON header: {"side":"inputs","col":0,"blk":3}
binary payload
```

Это эффективно, потому что при повторном обучении или маленьком изменении локального dataset клиент не отправляет весь dataset заново. Передаются только изменившиеся blocks, примерно как delta sync в git.

Для on-prem runtime это нужно оформить как отдельную часть, не внутри training loop.

Минимальный публичный интерфейс:

```python
class DatasetSyncCache:
    def prepare_sync(user_id, dataset_id, header, block_hashes, hash_algo) -> dict:
        ...

    def apply_frames(user_id, dataset_id, frames, client_hashes) -> SyncedDataset:
        ...
```

`SyncedDataset` потом передается в `LocalDatasetProvider`.

### `api/dataset_routes.py`

Тонкий API слой для dataset sync.

Нужные endpoints:

```text
GET /api/datasets
WS  /ws/datasets/sync
```

`GET /api/datasets` возвращает публичные датасеты и локально доступные datasets.

`WS /ws/datasets/sync` повторяет текущую схему из `neuralese-api`:

1. клиент отправляет dataset metadata + hashes;
2. runtime отправляет `need`;
3. клиент отправляет только нужные binary frames;
4. клиент отправляет `__end__`;
5. runtime возвращает summary: rows, preview, fingerprint.

Training job после этого может ссылаться на dataset через `dataset_ref`, а не грузить данные повторно.

### `core/events.py`

Описывает формат событий, которые сервер отправляет клиенту.

Примеры событий:

```json
{
  "job_id": "job_123",
  "phase": "epoch",
  "data": {
    "epoch": 3,
    "epochs": 10,
    "train_loss": 0.42,
    "val_acc": 0.86
  }
}
```

### `core/jobs.py`

Хранит состояние training jobs:

- `queued`;
- `running`;
- `stopping`;
- `stopped`;
- `completed`;
- `failed`.

Также хранит:

- время создания;
- последние метрики;
- путь к snapshot;
- stop flag.

### `core/engine.py`

Главный публичный интерфейс runtime.

Он должен предоставлять методы:

```python
submit_bundle(...)
stop(job_id)
get_job(job_id)
list_jobs()
subscribe(job_id)
```

Через этот файл runtime можно будет встроить в другой сервер без FastAPI.

### `core/ort_trainer.py`

Непосредственно обучает модель через ONNX Runtime Training.

Он делает:

- загружает `model.onnx`;
- генерирует training artifacts;
- запускает обучение по эпохам;
- считает loss/accuracy;
- после каждой эпохи отправляет event;
- проверяет stop flag;
- сохраняет обученную ONNX-модель.

### `core/metrics.py`

Пишет метрики в `metrics.jsonl`.

Одна строка - одно состояние эпохи:

```json
{"epoch":1,"train_loss":0.91,"val_acc":0.52}
{"epoch":2,"train_loss":0.61,"val_acc":0.71}
```

### `core/snapshot.py`

Собирает результат обучения в `snapshot.zip`.

### `api/app.py`

FastAPI-сервер.

Основные endpoints:

```text
POST /api/jobs
GET  /api/jobs
POST /api/jobs/{job_id}/stop
GET  /api/jobs/{job_id}/snapshot
GET  /api/stats
WS   /ws/jobs/{job_id}
```

### `api/profiles.py`

Описывает режим запуска API.

Минимальные настройки:

```python
class RuntimeProfile:
    mode: str  # "local_school" или "cloud_node"
    storage_dir: str
    enable_dashboard: bool
    enable_direct_upload: bool
    enable_cloud_registration: bool
    max_parallel_jobs: int
```

В `local_school` включены direct upload и dashboard.

В `cloud_node` основной вход должен идти через cloud scheduler. Для этого позже можно добавить отдельный adapter, но core training engine от этого меняться не должен.

### `dashboard/index.html`, `styles.css`, `app.js`

Минимальный dashboard в стиле Neuralese UI.

Должен быть темным, аккуратным и функциональным.

## 8. API-контракт

### Режимы запуска API

Runtime должен запускаться с явным profile:

```bash
NEURALESE_RUNTIME_MODE=local_school python -m uvicorn onprem_runtime.api.app:app --host 0.0.0.0 --port 8010
```

или:

```bash
NEURALESE_RUNTIME_MODE=cloud_node python -m uvicorn onprem_runtime.api.app:app --host 0.0.0.0 --port 8010
```

Разница между режимами:

| Возможность | `local_school` | `cloud_node` |
|---|---:|---:|
| Upload bundle через dashboard/API | да | опционально или выключено |
| Локальный dashboard | да | опционально |
| Автономная работа без облака | да | нет |
| Регистрация в центральном backend | нет | да |
| Load balancing | обычно не нужен | нужен |
| Хранение snapshot | локальный диск | cloud/object storage |
| Источник jobs | локальный клиент | cloud scheduler |

Для первой версии нужно реализовать `local_school` полностью, а для `cloud_node` заложить чистые интерфейсы: profile config, health endpoint, ограничение `max_parallel_jobs`, независимый `TrainingEngine`, который можно подключить к cloud scheduler без переписывания training loop.

### Создать training job

```text
POST /api/jobs
```

Request:

```text
multipart/form-data
bundle=<bundle.zip>
```

Response:

```json
{
  "job_id": "job_abcd1234",
  "state": "queued"
}
```

В `cloud_node` этот endpoint можно оставить закрытым для internal traffic или выключить через profile. Задания в этом режиме должны приходить от cloud scheduler, чтобы несколько runtime-нод могли работать за load balancer.

### Dataset reference в manifest

Bundle может не содержать сам dataset, если данные уже доступны runtime.

Публичный dataset:

```json
{
  "dataset_ref": {
    "type": "public",
    "id": "mnist",
    "version": "1",
    "split": "train",
    "checksum": "sha256:..."
  }
}
```

Локальный dataset:

```json
{
  "dataset_ref": {
    "type": "local",
    "id": "school-dataset-42",
    "fingerprint": "sha256:...",
    "schema": {
      "input": "x",
      "label": "y"
    }
  }
}
```

Если `fingerprint` или `checksum` совпадает с локальным cache, runtime использует существующие данные. Если публичного dataset нет в cache, `PublicDatasetProvider` подгружает его с backend/storage. Если локального dataset нет, runtime возвращает понятную ошибку: `dataset_not_found`.

### Incremental sync локального dataset

Локальный dataset не должен входить в ONNX bundle целиком.

Схема:

1. Клиент сначала синхронизирует dataset с runtime через `WS /ws/datasets/sync`.
2. Runtime сравнивает hashes blocks с локальным cache.
3. Runtime отвечает, какие blocks нужны.
4. Клиент отправляет только нужные blocks.
5. Runtime декомпрессит dataset через Rust decompressor.
6. Runtime сохраняет cache entry и возвращает `fingerprint`.
7. Training bundle содержит только ссылку:

```json
{
  "dataset_ref": {
    "type": "local",
    "id": "school-dataset-42",
    "fingerprint": "sha256:abc...",
    "synced": true
  }
}
```

Если dataset уже синхронизирован и fingerprint совпадает, шаги 3-5 почти ничего не передают. Это главный способ экономить время и трафик на локальных датасетах.

В `local_school` режиме runtime держит этот cache локально.

В `cloud_node` режиме нельзя просто отправлять local dataset на случайную ноду за load balancer. Нужен data-aware scheduling:

- scheduler должен знать, на каких нодах есть нужный `dataset_fingerprint`;
- если dataset есть на одной ноде, job лучше отправлять туда;
- если dataset отсутствует, нода должна подтянуть blocks из центрального storage/cache;
- public datasets можно запускать на любой ноде, потому что они подтягиваются по id/version/checksum.

### Получить список jobs

```text
GET /api/jobs
```

Response:

```json
[
  {
    "job_id": "job_abcd1234",
    "name": "digits-cnn",
    "state": "running",
    "created_at": 1780000000.0,
    "updated_at": 1780000012.0,
    "latest": {
      "epoch": 2,
      "epochs": 10,
      "train_loss": 0.52,
      "val_acc": 0.81
    },
    "snapshot_ready": false
  }
]
```

### Остановить job

```text
POST /api/jobs/{job_id}/stop
```

Response:

```json
{
  "ok": true
}
```

### Скачать snapshot

```text
GET /api/jobs/{job_id}/snapshot
```

Response:

```text
snapshot.zip
```

### Получить runtime stats

```text
GET /api/stats
```

Response:

```json
{
  "cpu_percent": 34,
  "memory_percent": 61,
  "active_jobs": 2,
  "total_jobs": 14
}
```

### WebSocket progress stream

```text
WS /ws/jobs/{job_id}
```

Сервер отправляет:

```json
{
  "job_id": "job_abcd1234",
  "phase": "epoch",
  "data": {
    "epoch": 4,
    "epochs": 10,
    "train_loss": 0.39,
    "val_loss": 0.44,
    "val_acc": 0.88,
    "epoch_seconds": 1.27
  }
}
```

Клиент может отправить:

```json
{
  "type": "stop"
}
```

После этого runtime должен остановить обучение при ближайшей безопасной точке.

## 9. Этапы реализации

### Этап 1. Подготовить Python-пакет

Создать базовую структуру:

```text
onprem_runtime/
tests/onprem_runtime/
```

Добавить:

- `requirements.txt`;
- `README.md`;
- пустые `__init__.py`;
- первый простой тест на формат event.

Цель этапа: проект должен импортироваться и запускать тесты.

Проверка:

```bash
python3 -m pytest tests/onprem_runtime -v
```

### Этап 2. Реализовать bundle parser

Сделать `core/bundle.py`, `core/config.py` и базовый формат `dataset_ref`.

Нужно научиться:

- открывать `.zip`;
- проверять обязательные файлы;
- читать `manifest.json`;
- читать `train.npz`, если dataset приложен к bundle;
- читать `dataset_ref`, если dataset не приложен к bundle;
- читать `val.npz`, если он есть;
- возвращать удобный объект `ExtractedBundle`.

Тесты:

- успешный bundle читается;
- bundle без `manifest.json` падает;
- bundle без `model.onnx` падает;
- bundle без `data/train.npz` и без `dataset_ref` падает;
- `train.npz` без `x/y` падает.

### Этап 2.1. Реализовать DatasetProvider слой

Сделать `core/datasets.py`.

Минимально нужны:

- общий интерфейс `DatasetProvider`;
- `UploadedDatasetProvider`;
- `NeuralesePublicDatasetProvider`;
- `IncrementalLocalDatasetProvider`.

На первой версии `UploadedDatasetProvider` должен работать полностью. `NeuralesePublicDatasetProvider` должен быть adapter под существующий public dataset engine из `neuralese-api`: `record.ds_route.get_pub`, `has_dataset`, `read_dataset`, `has_test_dataset`.

`IncrementalLocalDatasetProvider` должен брать dataset из local sync cache, а не из bundle.

Проверка:

```bash
python3 -m pytest tests/onprem_runtime/test_datasets.py -v
```

Ожидаемо:

- uploaded dataset читается из bundle;
- public dataset использует cache, если файл уже есть;
- public dataset adapter вызывает backend dataset engine через отдельный wrapper;
- local dataset возвращает `dataset_not_found`, если fingerprint не синхронизирован;
- training engine получает данные через provider, а не напрямую через bundle parser.

### Этап 2.2. Реализовать incremental dataset sync

Сделать:

```text
core/dataset_compression.py
core/dataset_sync.py
api/dataset_routes.py
tests/onprem_runtime/test_dataset_compression_engine.py
tests/onprem_runtime/test_dataset_sync.py
```

Нужно повторить рабочую схему из `neuralese-api`:

- покрыть unit tests для compression engine;
- принять `header`, `dataset_id`, `hash_algo`, `block_hashes`;
- сравнить hashes с cache;
- вернуть `need` map;
- принять только нужные binary frames;
- обновить cache;
- собрать packet `[inputs, outputs]`;
- декомпрессить через Rust `ds_decompressor`, если extension установлен;
- иметь Python fallback/error path, если extension не установлен.

Проверка:

```bash
python3 -m pytest tests/onprem_runtime/test_dataset_compression_engine.py -v
python3 -m pytest tests/onprem_runtime/test_dataset_sync.py -v
```

Ожидаемо:

- compression engine совпадает с byte-level contract клиента;
- SHA-256 hashes считаются от encoded block bytes;
- при пустом cache runtime просит все blocks;
- при совпадающих hashes runtime не просит blocks;
- при изменении одного block runtime просит только этот block;
- после применения frame cache содержит новый payload и hash;
- provider может получить dataset по `dataset_id + fingerprint`.

### Этап 3. Реализовать events и job state

Сделать:

- `core/events.py`;
- `core/jobs.py`;
- базовые состояния job.

Важно, чтобы все события имели единый JSON-формат.

Минимальные phases:

```text
queued
started
epoch
stopping
stopped
completed
failed
```

### Этап 4. Реализовать embeddable engine

Сделать `core/engine.py`.

Он должен быть главным способом пользоваться runtime из Python-кода.

Пример использования:

```python
engine = TrainingEngine(root_dir=".neuralese_onprem", trainer=OrtBundleTrainer())
job = await engine.submit_bundle("bundle.zip")
engine.stop(job.job_id)
```

На этом этапе можно использовать fake trainer, чтобы проверить job lifecycle без настоящего ONNX Runtime.

### Этап 5. Реализовать ONNX Runtime trainer

Сделать `core/ort_trainer.py`.

Основной flow:

1. Загрузить ONNX-модель.
2. Взять список `trainable_parameters` из manifest.
3. Сгенерировать ONNX Runtime training artifacts.
4. Загрузить dataset.
5. Запустить training loop.
6. После каждой epoch считать метрики.
7. Отправлять progress event.
8. Проверять stop flag.
9. В конце сохранить обученную ONNX-модель.

На этом этапе можно частично опираться на существующий код:

```text
local_runtime/neuralese_local/train_task.py
```

Но лучше не копировать его как есть. Нужно вынести чистую логику под новый bundle-based API.

### Этап 6. Реализовать snapshot packer

Сделать `core/snapshot.py`.

Он должен собирать:

```text
snapshot.zip
  manifest.json
  inference.onnx
  metrics.jsonl
  checkpoint/
```

Тесты:

- snapshot создается;
- внутри есть `manifest.json`;
- внутри есть `inference.onnx`;
- внутри есть `metrics.jsonl`;
- checkpoint добавляется, если директория существует.

### Этап 7. Реализовать FastAPI server

Сделать:

```text
api/app.py
api/profiles.py
api/schemas.py
```

Endpoints:

```text
POST /api/jobs
GET  /api/jobs
POST /api/jobs/{job_id}/stop
GET  /api/jobs/{job_id}/snapshot
GET  /api/stats
WS   /ws/jobs/{job_id}
```

Важно: API не должен содержать training logic. Он только вызывает `TrainingEngine`.

Добавить поддержку двух profile:

- `local_school`;
- `cloud_node`.

Для `local_school` включить upload, dashboard и локальное хранение snapshot.

Для `cloud_node` добавить базовые элементы, нужные для будущего cloud deployment:

- `GET /api/health`;
- `GET /api/capacity`;
- `GET /api/datasets/cache`;
- настройку `max_parallel_jobs`;
- возможность выключить публичный dashboard;
- возможность выключить direct upload, если jobs приходят только от scheduler.

`GET /api/capacity` должен возвращать не только CPU/RAM/active jobs, но и краткую информацию для scheduler:

```json
{
  "mode": "cloud_node",
  "active_jobs": 1,
  "max_parallel_jobs": 2,
  "available_slots": 1,
  "cached_public_datasets": ["mnist:1", "iris:1"],
  "cached_local_fingerprints": ["sha256:abc..."]
}
```

Так runtime можно будет использовать и как школьный локальный сервис, и как worker-ноду в Neuralese Cloud. Для cloud load balancing важно не только количество свободных слотов, но и data locality: job с локальным dataset лучше отправлять на ноду, где уже есть нужный fingerprint.

### Этап 8. Реализовать минимальный dashboard

Сделать:

```text
dashboard/index.html
dashboard/styles.css
dashboard/app.js
```

Минимальные блоки:

- заголовок `Neuralese Runtime`;
- upload bundle;
- CPU;
- RAM;
- active jobs;
- total jobs;
- список jobs;
- current loss;
- current accuracy;
- stop button;
- download snapshot button.

Дизайн:

- темный фон;
- тонкие границы;
- компактные карточки;
- без маркетингового hero;
- функционально и похоже на инструмент, а не landing page.

### Этап 9. Добавить dummy bundle generator

Сделать:

```text
examples/make_dummy_bundle.py
```

Он должен создавать маленький тестовый bundle:

```text
dummy_bundle.zip
  manifest.json
  model.onnx
  data/train.npz
  data/val.npz
```

Зачем это нужно:

- быстро проверять runtime без Godot;
- делать локальный smoke test;
- показывать, что API реально принимает bundle и запускает training.

### Этап 10. Проверить end-to-end flow

Порядок проверки:

```bash
python3 -m venv .venv-onprem
. .venv-onprem/bin/activate
python -m pip install -r onprem_runtime/requirements.txt
python -m pytest tests/onprem_runtime -v
python onprem_runtime/examples/make_dummy_bundle.py
python -m uvicorn onprem_runtime.api.app:app --host 127.0.0.1 --port 8010
```

В другом терминале:

```bash
curl -F "bundle=@dummy_bundle.zip" http://127.0.0.1:8010/api/jobs
```

Потом открыть:

```text
http://127.0.0.1:8010/
```

Нужно проверить:

- bundle загружается;
- job появляется в dashboard;
- loss/accuracy обновляются;
- stop работает;
- после завершения появляется download;
- snapshot скачивается.

## 10. Минимальный dashboard: что показывать

Для школьного сисадмина или учителя достаточно таких метрик:

### Runtime status

- CPU usage;
- RAM usage;
- количество активных jobs;
- общее количество jobs;
- uptime, если успеем.

### Training jobs

Для каждой job:

- имя модели;
- job id;
- статус;
- текущая epoch;
- train loss;
- validation loss;
- validation accuracy;
- время последней эпохи;
- кнопка Stop;
- кнопка Download.

### Почему этого достаточно

Учителю или сисадмину не нужна сложная MLOps-панель. Ему важно видеть:

- сервер живой или нет;
- сколько учеников сейчас тренируют модели;
- не зависла ли какая-то тренировка;
- можно ли остановить проблемную job;
- можно ли скачать результат.

## 11. Что не делаем в первой версии

В MVP не делаем:

- inference endpoint;
- авторизацию;
- роли пользователей;
- красивую аналитику;
- графики на canvas;
- GPU scheduler;
- Section Reuse;
- Fused SuperGraph;
- сложную очередь задач;
- distributed workers.

Это можно добавить позже, если базовый runtime будет работать стабильно.

## 12. Главные технические риски

### ONNX Runtime Training поддерживает не все модели

Некоторые ONNX operations могут не поддерживаться training API.

Что делаем:

- не скрываем ошибку;
- отправляем `failed` event;
- показываем текст ошибки в dashboard.

### Нужно правильно передавать trainable parameters

ONNX Runtime должен знать, какие initializer names можно обучать.

Если Neuralese exporter даст неправильные имена, обучение не стартует.

Что делаем:

- явно проверяем `trainable_parameters`;
- если список пустой, падаем с понятной ошибкой.

### Stop не всегда мгновенный

Если batch долго считается, остановка произойдет после завершения текущего batch.

Это нормально для MVP.

### Bundle format должен быть стабильным

Если формат bundle будет часто меняться, runtime станет трудно поддерживать.

Поэтому лучше сразу зафиксировать `bundle_version`.

## 13. Оптимизация бурды

В первой версии не нужно сразу делать сложные вещи вроде Section Reuse, Fused SuperGraph или distributed training. Но есть несколько простых оптимизаций, которые почти точно дадут пользу и не усложнят архитектуру.

### 1. Кэшировать ONNX Runtime training artifacts

Перед обучением ONNX Runtime генерирует training artifacts:

```text
training_model.onnx
eval_model.onnx
optimizer_model.onnx
checkpoint
```

Если генерировать их на каждый request, одинаковые или похожие модели будут тратить время впустую.

Что делаем:

- считаем hash от `model.onnx`, `loss`, `optimizer`, `trainable_parameters`;
- если такой hash уже был, берем artifacts из cache;
- если нет, генерируем artifacts и сохраняем в cache.

Пример:

```text
cache_key = sha256(model.onnx + loss + optimizer + trainable_parameters)
```

Это особенно полезно для школы, потому что ученики часто тренируют одинаковые архитектуры в рамках одного урока.

### 2. Не делать full validation после каждой epoch

Считать `accuracy` на всем validation dataset после каждой epoch может быть дорого.

Лучше:

- `train_loss` отправлять каждую epoch;
- `val_loss` и `val_acc` считать раз в несколько epochs;
- на больших dataset считать validation на sample, например 1024-2048 примеров;
- полную validation делать только в конце.

Пример настройки:

```python
EVAL_INTERVAL = 5
EVAL_MAX_SAMPLES = 2048
```

Так dashboard все равно будет показывать понятный прогресс, но runtime не будет тратить лишнее время на постоянную проверку.

### 3. Не экспортировать модель после каждой epoch

Экспорт `inference.onnx` и запись на диск могут тормозить.

В MVP лучше:

- писать `metrics.jsonl` после каждой epoch;
- экспортировать `inference.onnx` только:
  - в конце обучения;
  - или раз в несколько epochs, если нужен intermediate checkpoint;
  - или при graceful stop.

Dashboard не нуждается в модели каждую секунду. Ему нужны метрики.

### 4. Ограничить количество параллельных jobs

Если запустить слишком много тренировок одновременно, они начнут мешать друг другу и все станет медленнее.

Нужна простая очередь:

```text
queued -> running -> completed / stopped / failed
```

И настройка:

```text
MAX_PARALLEL_JOBS=2
```

Для слабого школьного компьютера можно ставить `1`.

Для нормального CPU-сервера можно ставить `2-4`.

Это простая оптимизация, но она сильно влияет на реальную скорость и стабильность.

### 5. Настроить ONNX Runtime SessionOptions

Для CPU надо явно задать разумные настройки ONNX Runtime:

```python
import onnxruntime as ort

session_options = ort.SessionOptions()
session_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
session_options.intra_op_num_threads = 4
session_options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
```

Что это дает:

- включает graph optimizations;
- ограничивает количество CPU threads;
- помогает избежать ситуации, когда несколько jobs забивают весь CPU.

Потом можно сделать эти значения через env:

```text
ORT_INTRA_OP_THREADS=4
ORT_INTER_OP_THREADS=1
ORT_EXECUTION_MODE=sequential
```

Важно: эти значения нужно подбирать под железо. На школьном ПК слишком много потоков может сделать хуже.

### 6. Подготовить dataset один раз до training loop

Внутри batch loop нельзя каждый раз делать тяжелые преобразования.

До начала обучения нужно привести данные к нормальному виду:

```python
x = np.ascontiguousarray(x, dtype=np.float32)
y = y.astype(np.int64)
```

И уже потом использовать эти массивы в training loop.

Также лучше использовать `.npz` или `.npy`, а не JSON для больших dataset.

Для больших dataset можно позже добавить:

```python
np.load(path, mmap_mode="r")
```

### 7. Логировать время по стадиям

Перед серьезной оптимизацией нужно понять, что именно тормозит.

Нужно писать timings:

```text
bundle_extract_ms
artifact_generation_ms
dataset_load_ms
epoch_train_ms
eval_ms
export_ms
snapshot_ms
```

Эти значения можно показывать только в debug logs или в dashboard как advanced info.

Это поможет быстро понять, где bottleneck:

- ONNX Runtime;
- dataset load;
- validation;
- export;
- disk I/O;
- очередь jobs.

### 8. Что оставить на потом

Эти оптимизации потенциально сильные, но для первой версии слишком сложные:

- GPU trainer backend;
- I/O Binding для GPU;
- Section Reuse;
- Fused SuperGraph;
- grouping одинаковых jobs;
- distributed workers.

Их лучше делать только после того, как базовый runtime стабильно тренирует модели и понятно, где реально узкое место.

## 14. Итоговая схема

```text
Neuralese client / dashboard
        |
        | upload bundle
        | websocket progress
        v
onprem_runtime.api
        |
        v
onprem_runtime.core
        |
        v
OrtBundleTrainer
        |
        v
ONNX Runtime Training
        |
        v
snapshot.zip
```

## 15. Критерии готовности

Задачу можно считать сделанной, если:

- сервер принимает `.zip` bundle;
- создает training job;
- стримит progress через WebSocket;
- показывает loss/accuracy;
- умеет останавливать job;
- после завершения возвращает snapshot;
- dashboard показывает jobs и системную статистику;
- training engine можно использовать отдельно от FastAPI;
- есть тесты на bundle, events, jobs и snapshot;
- есть dummy bundle для локальной проверки.
