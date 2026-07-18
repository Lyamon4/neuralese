# Demo Guide

Этот guide нужен, чтобы быстро показать рабочий flow on-prem ONNX training runtime на видео.

Главная демонстрация:

```text
clone repo -> install deps -> run tests -> start server -> open dashboard -> create demo bundle -> upload -> watch training -> download snapshot
```

## Что должно получиться в конце

После загрузки demo bundle в dashboard должна появиться training job.

Она проходит фазы:

```text
queued -> started -> epoch -> completed
```

После `completed` можно скачать `snapshot.zip`.

Внутри snapshot ожидаются:

```text
manifest.json
inference.onnx
metrics.jsonl
checkpoint/
```

## Короткий текст для видео

Можно сказать примерно так:

```text
Это on-prem runtime для обучения ONNX-моделей. Он запускается локально, принимает ONNX bundle, тренирует модель, стримит progress через WebSocket и после завершения возвращает snapshot с обученной inference.onnx моделью и метриками.

Архитектура разделена на core, API, dashboard, deployment и tests. Core не зависит от FastAPI, поэтому training engine можно встраивать как в школьный локальный сервер, так и в cloud-node.
```

В конце:

```text
Это MVP vertical slice: upload bundle, training, WebSocket progress, stop/download snapshot, dashboard, dataset refs, incremental dataset sync, Docker deployment, systemd docs, auth token, понятные UI/API ошибки, GitHub Actions CI и tests. Ограничение текущего этапа: поддержан первый classification flow; расширение на больше типов ONNX-моделей идет следующим compatibility этапом.
```

## Windows demo

Лучше всего использовать PowerShell.

### 1. Установить инструменты

```powershell
winget install --id Git.Git -e
winget install --id GitHub.cli -e
winget install --id Python.Python.3.11 -e
```

После установки закрой PowerShell и открой заново.

Проверь:

```powershell
git --version
gh --version
py -3.11 --version
```

### 2. Войти в GitHub

Repo private, поэтому на новом компьютере надо быть залогиненным в GitHub account, у которого есть доступ.

```powershell
gh auth login
```

Выбирай:

```text
GitHub.com
HTTPS
Login with a web browser
```

Проверка:

```powershell
gh auth status
```

### 3. Склонировать repo

```powershell
cd $HOME\Desktop
gh repo clone Lyamon4/neuralese-onnx
cd neuralese-onnx\code-snapshot
```

Проверь, что ты в правильной папке:

```powershell
dir
```

Должны быть:

```text
onprem_runtime
tests
```

Если этих папок нет, значит ты не в `code-snapshot`.

### 4. Создать Python окружение

```powershell
py -3.11 -m venv .venv-onprem
```

Если PowerShell запрещает scripts:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Активировать:

```powershell
.\.venv-onprem\Scripts\Activate.ps1
```

После активации слева должно появиться:

```text
(.venv-onprem)
```

### 5. Установить зависимости

```powershell
python -m pip install --upgrade pip
pip install -r onprem_runtime\requirements.txt
```

### 6. Запустить тесты

```powershell
python -m pytest tests\onprem_runtime -v
```

Ожидаемый результат:

```text
95 passed
```

Для видео достаточно показать конец вывода с `95 passed`.

### 7. Запустить сервер

В этом же PowerShell:

```powershell
python -m onprem_runtime --mode local_school --host 127.0.0.1 --port 8010
```

Окно не закрывать.

Ожидаемый вывод:

```text
Uvicorn running on http://127.0.0.1:8010
```

Открой в браузере:

```text
http://127.0.0.1:8010/
```

### 8. Создать demo bundle

Открой второй PowerShell.

Перейди в ту же папку:

```powershell
cd $HOME\Desktop\neuralese-onnx\code-snapshot
.\.venv-onprem\Scripts\Activate.ps1
```

Создай bundle:

```powershell
python -m onprem_runtime.examples.make_dummy_bundle $env:TEMP\neuralese_demo_bundle.zip --epochs 3
```

Файл появится здесь:

```text
C:\Users\<YOUR_USER>\AppData\Local\Temp\neuralese_demo_bundle.zip
```

Открыть папку с файлом:

```powershell
explorer $env:TEMP
```

### 9. Загрузить bundle через dashboard

В dashboard нажми:

```text
Upload bundle
```

Выбери:

```text
neuralese_demo_bundle.zip
```

Покажи на видео:

- job появилась в списке;
- state меняется;
- loss/accuracy отображаются;
- после завершения появляется snapshot ready;
- можно скачать snapshot.

Можно отдельно быстро показать ошибку: выбрать не `.zip` файл в upload. Dashboard должен показать notice с понятным текстом и действием, а API вернет JSON с `error.code`, `error.message` и `error.action`.

### 10. Если хочешь отправить bundle без UI

Во втором PowerShell:

```powershell
curl.exe -F "bundle=@$env:TEMP\neuralese_demo_bundle.zip" http://127.0.0.1:8010/api/jobs
```

Потом dashboard сам подтянет job при refresh.

## Demo с auth token

Если нужно показать, что API защищается token'ом, запускай сервер так:

```powershell
python -m onprem_runtime --mode local_school --host 127.0.0.1 --port 8010 --auth-token school-secret
```

В dashboard вставь:

```text
school-secret
```

в поле:

```text
API token
```

После этого upload/stop/download будут работать с token.

Через curl:

```powershell
curl.exe -H "Authorization: Bearer school-secret" -F "bundle=@$env:TEMP\neuralese_demo_bundle.zip" http://127.0.0.1:8010/api/jobs
```

Smoke test с auth:

```powershell
python onprem_runtime\deployment\smoke_test.py --launcher local --port 8125 --epochs 2 --auth-token school-secret
```

## Mac / Linux demo

```bash
git clone https://github.com/Lyamon4/neuralese-onnx.git
cd neuralese-onnx/code-snapshot

python3.11 -m venv .venv-onprem
source .venv-onprem/bin/activate

python -m pip install --upgrade pip
pip install -r onprem_runtime/requirements.txt

python -m pytest tests/onprem_runtime -v
```

Ожидаемый результат:

```text
95 passed
```

Запуск сервера:

```bash
python -m onprem_runtime --mode local_school --host 127.0.0.1 --port 8010
```

Открыть:

```text
http://127.0.0.1:8010/
```

Во втором терминале:

```bash
cd neuralese-onnx/code-snapshot
source .venv-onprem/bin/activate
python -m onprem_runtime.examples.make_dummy_bundle /tmp/neuralese_demo_bundle.zip --epochs 3
```

Загрузить `/tmp/neuralese_demo_bundle.zip` через dashboard.

## Быстрая автоматическая проверка без UI

Эта команда сама поднимает runtime, создает bundle, отправляет его в API, слушает WebSocket, скачивает snapshot и проверяет файлы внутри:

Windows:

```powershell
python onprem_runtime\deployment\smoke_test.py --launcher local --port 8125 --epochs 2
```

Mac / Linux:

```bash
python onprem_runtime/deployment/smoke_test.py --launcher local --port 8125 --epochs 2
```

Ожидаемые события:

```text
queued
started
epoch
completed
```

В конце smoke test печатает JSON с:

```text
job_id
snapshot_path
final_event
manifest
```

## Docker demo

Docker demo лучше показывать на Mac/Linux или Windows с Docker Desktop/WSL2.

Команда:

```bash
python onprem_runtime/deployment/smoke_test.py --launcher docker --port 8129 --timeout 360 --epochs 1
```

Что показывает:

- Docker image собирается;
- runtime стартует в контейнере;
- bundle upload проходит через API;
- WebSocket events доходят до `completed`;
- snapshot скачивается и проверяется.

Compose закреплен на:

```text
platform: linux/amd64
```

Причина: используемый `onnxruntime-training-cpu==1.19.2` доступен как Linux amd64 wheel.

## Что открыть в GitHub во время видео

Repo:

```text
https://github.com/Lyamon4/neuralese-onnx
```

Показать:

```text
README.md
DEMO.md
implementation-plan.md
что сделал.md
code-snapshot/onprem_runtime
code-snapshot/tests/onprem_runtime
```

Можно сказать:

```text
В repo лежит не только код, но и implementation plan, отчет что сделано, demo guide, тесты и deployment package.
```

## Troubleshooting

### `No module named onprem_runtime`

Ты не в той папке.

Нужно быть здесь:

```text
neuralese-onnx\code-snapshot
```

Проверка:

```powershell
dir
```

Должны быть `onprem_runtime` и `tests`.

### `Activate.ps1` not recognized

Venv не создан или ты не в той папке.

```powershell
cd $HOME\Desktop\neuralese-onnx\code-snapshot
py -3.11 -m venv .venv-onprem
.\.venv-onprem\Scripts\Activate.ps1
```

### `running scripts is disabled`

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv-onprem\Scripts\Activate.ps1
```

### `No suitable Python runtime found`

Python 3.11 не установлен.

```powershell
winget install --id Python.Python.3.11 -e
```

Потом закрыть и открыть PowerShell заново.

### Порт 8010 занят

Останови старый сервер через `Ctrl+C` или запусти на другом порту:

```powershell
python -m onprem_runtime --mode local_school --host 127.0.0.1 --port 8011
```

Открыть:

```text
http://127.0.0.1:8011/
```

### `401 missing or invalid auth token`

Server запущен с token.

Вставь token в dashboard поле `API token` или используй header:

```text
Authorization: Bearer <token>
```

### Тесты показывают старый результат

Обнови repo:

```powershell
cd $HOME\Desktop\neuralese-onnx
git pull
cd code-snapshot
python -m pytest tests\onprem_runtime -v
```
