from __future__ import annotations

from pathlib import Path

from dotenv import load_dotenv
from sanic import Sanic
from sanic.log import logger
from sanic.response import html, json

from auth.attempts import AuthAttemptStore
from auth.routes import bp_auth
from auth.web import bp_auth_web, render_auth_page
from axon.routes import bp_axon
from axon.service import AxonService
from billing.routes import bp_billing
from billing.service import BillingService
from classrooms.events import ClassroomEventHub
from classrooms.routes import bp_classrooms, bp_classrooms_api
from classrooms.service import ClassroomService
from config import Settings
from datasets.routes import bp_datasets
from projects.routes import bp_projects
from storage import Database
from users.routes import bp_users
from users.service import UserService


LEGACY_ROUTE_ALIASES = {
    "/save": "/api/projects/save",
    "/project": "/api/projects/get",
    "/delete_project": "/api/projects/delete",
    "/project_list": "/api/projects/list",
    "/get_chat": "/api/projects/get-chat",
    "/clear_chat": "/api/projects/clear-chat",
    "/reg_dataset": "/api/projects/register-dataset",
    "/datasets": "/api/datasets",
    "/classroom/create": "/api/classrooms/create",
    "/classroom/join": "/api/classrooms/join",
    "/classroom/meta": "/api/classrooms/meta",
    "/classroom/leave": "/api/classrooms/leave",
    "/classroom/update_meta": "/api/classrooms/update-meta",
    "/classroom/update_lessons": "/api/classrooms/update-lessons",
    "/classroom/lesson_auto_project": "/api/classrooms/lesson-auto-project",
    "/classroom/update_state": "/api/classrooms/update-state",
    "/classroom/mark_explanation_made": "/api/classrooms/mark-explanation-made",
    "/classroom/get_state": "/api/classrooms/get-state",
    "/classroom/events": "/api/classrooms/events",
    "/ask_once": "/api/axon/ask-once",
    "/ws/talk": "/ws/axon/talk",
}


def create_app() -> Sanic:
    load_dotenv(Path(__file__).with_name(".env"))
    settings = Settings.from_env()
    settings.data_dir.mkdir(parents=True, exist_ok=True)

    app = Sanic("neuralese_clean_backend")
    app.ctx.settings = settings
    app.ctx.db = Database(str(settings.db_path))
    app.ctx.user_service = UserService(app.ctx.db)
    app.ctx.billing_service = BillingService(app.ctx.db)
    app.ctx.auth_attempts = AuthAttemptStore()
    app.ctx.classroom_service = ClassroomService(app.ctx.db)
    app.ctx.classroom_events = ClassroomEventHub()
    app.ctx.axon_service = AxonService(settings)

    @app.middleware("request")
    async def log_legacy_route(request):
        canonical = LEGACY_ROUTE_ALIASES.get(request.path)
        if canonical:
            logger.info("legacy route used path=%s canonical=%s", request.path, canonical)

    app.blueprint(bp_auth)
    app.blueprint(bp_auth_web)
    app.blueprint(bp_users)
    app.blueprint(bp_billing)
    app.blueprint(bp_projects)
    app.blueprint(bp_datasets)
    app.blueprint(bp_classrooms)
    app.blueprint(bp_classrooms_api)
    app.blueprint(bp_axon)

    @app.get("/")
    async def index(request):
        if "format=json" not in request.query_string:
            return render_auth_page(request)
        return json({
            "ok": True,
            "service": "neuralese_clean_backend",
            "storage": str(settings.db_path),
            "routes": [
                "POST /api/auth/device/start",
                "GET /api/auth/device/wait",
                "POST /api/auth/device/complete",
                "POST /api/auth/device/cancel",
                "GET /api/auth/me",
                "POST /api/auth/refresh",
                "GET /auth",
                "POST /auth/api/profile",
                "POST /auth/api/claim-username",
                "POST /auth/api/complete-login",
                "POST /auth/api/sign-out",
                "GET /api/users/me",
                "POST /api/users/claim-username",
                "GET /api/users/username-available",
                "GET /api/billing/gumroad/checkout-url",
                "POST /api/billing/gumroad/verify-license",
                "POST /api/billing/gumroad/ping",
                "GET /api/billing/status",
                "POST /api/projects/save",
                "POST /api/projects/get",
                "POST /api/projects/delete",
                "POST /api/projects/list",
                "POST /api/projects/get-chat",
                "POST /api/projects/clear-chat",
                "POST /api/projects/register-dataset",
                "GET /api/datasets",
                "POST /api/classrooms/create",
                "POST /api/classrooms/join",
                "POST /api/classrooms/meta",
                "POST /api/classrooms/leave",
                "POST /api/classrooms/update-meta",
                "POST /api/classrooms/update-lessons",
                "POST /api/classrooms/lesson-auto-project",
                "POST /api/classrooms/update-state",
                "POST /api/classrooms/mark-explanation-made",
                "POST /api/classrooms/get-state",
                "GET /api/classrooms/events",
                "WS /ws/axon/talk",
                "POST /api/axon/ask-once",
                "legacy aliases still available: /save, /project, /delete_project, /project_list, /datasets, /classroom/*, /ws/talk, /ask_once",
            ],
        })

    @app.get("/health")
    async def health(_request):
        return html("<body>ok</body>")

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8081, dev=False, access_log=True, single_process=True)
