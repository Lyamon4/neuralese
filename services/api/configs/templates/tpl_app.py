import toml
from sanic import Sanic
from sanic.log import logger
from worker import worker_pebble as wp
from core import database
from app.trio_bp import bp_trio

def run_app():
	cfg = toml.load("config/settings.toml")

	app = Sanic("local_runner")
	app.config.LOG_LEVEL = cfg.get("log_level", "info")

	db_path = cfg.get("db_path", "./local_data/userdata.db")
	app.ctx.database = database.Database(db_path)

	app.blueprint(bp_trio)

	@app.before_server_start
	async def before_start(app, loop):
		wp.bind_loop_callsoon(loop.call_soon_threadsafe)

	port = int(cfg.get("port", 8000))
	app.run(host="0.0.0.0", port=port, workers=cfg.get("workers", 1))
