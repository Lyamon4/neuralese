

from routes.auth_bp import bp_auth
from routes.classroom_bp import bp_classroom
from routes.project_bp import bp_project
from api.common.services import set_db
import record.ds_route as lset


from sanic import Sanic
from sanic.log import logger
import threading, os, asyncio
from dotenv import load_dotenv
import storage
from common.utils import kief
import json

import worker.worker_pebble as wp
import worker.worker_tasks as wt


load_dotenv()
app = Sanic("neuralese_api")

import os
os.environ["batch_size"] = "32"

database: storage.Database = None

@app.before_server_start
async def bind_loop(app, loop):
	db = storage.Database("api/userdata.db")
	app.ctx.database = db
	wp.bind_loop_callsoon(loop.call_soon_threadsafe)
	setup_caches(app)

	def _warmup():
		try:
		    wt.init_whisper()
		except Exception as e:
		    logger.error(f"Whisper warmup failed: {e}")
	lset.init_import()

	threading.Thread(target=_warmup, daemon=True).start()


from routes.trio_bp import bp_trio
from routes.chat_bp import bp_chat
from routes.audio_bp import bp_audio
from routes.trio_bp import bp_trio
app.blueprint(bp_audio)
app.blueprint(bp_trio)
app.blueprint(bp_chat)

app.blueprint(bp_auth)
app.blueprint(bp_project)
app.blueprint(bp_classroom)

def setup_caches(app):
	# hello
    app.ctx.ds_cache = {}

import os


UPDATE_EXE_PATH = "api/version/Neuralese.exe"
UPDATE_STATE_PATH = "api/cfg.json"
CHUNK_SIZE = 1024 * 1024  # 1 MB

from common.stream_progressor import get_body
from sanic.response import text as sanic_text
from sanic.response import json as sanic_json
from sanic.response import html as sanic_html

@bp_auth.get("/health")
async def health(request):
	return sanic_html("<body><img src='https://media.tenor.com/ss582_czT8sAAAAM/konata-dance.gif'></img></body>", status=200)

@bp_auth.get("/check")
async def check_update(request):
	return sanic_json(json.loads(open(UPDATE_STATE_PATH, "r").read()))

from sanic.views import stream

from sanic.response import text as sanic_text

@bp_auth.get("/download")
@stream
async def download_update(request):
	file_path = UPDATE_EXE_PATH

	if not os.path.exists(file_path):
		return text("Update not found", status=404)

	file_size = os.path.getsize(file_path)

	headers = {
		"Content-Type": "application/octet-stream",
		"Content-Disposition": "attachment; filename=Neuralese.exe",
		"Content-Length": str(file_size),
	}

	response = await request.respond(headers=headers)

	with open(file_path, "rb") as f:
		while True:
			chunk = f.read(1024 * 1024)  # 1 MB
			if not chunk:
				break
			await response.send(chunk)



if __name__ == "__main__":

	for route in app.router.routes_all.values():
		print(route)
	asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
	app.run(host="0.0.0.0", port=8000, debug=True)
