from __future__ import annotations

import os
from pathlib import Path
from tempfile import TemporaryDirectory


def main() -> None:
    with TemporaryDirectory() as d:
        os.environ["NEURALESE_DATA_DIR"] = d
        os.environ["NEURALESE_DB_PATH"] = str(Path(d) / "userdata.db")
        os.environ["CLERK_HANDOFF_SECRET"] = "test_handoff"
        os.environ["NEURALESE_JWT_SECRET"] = "test_jwt_secret_long_enough_for_hs256"

        from app import app
        from auth.dependencies import handoff_principal
        from auth.jwt import decode_token
        from projects.service import ProjectService

        settings = app.ctx.settings
        db = app.ctx.db
        try:
            users = app.ctx.user_service
            billing = app.ctx.billing_service
            classrooms = app.ctx.classroom_service
            attempts = app.ctx.auth_attempts

            clerk_user = {"clerk_user_id": "user_smoke", "email": "kid@example.com", "display_name": "Kid"}
            principal = handoff_principal(clerk_user)
            profile = users.claim_username(principal, "kid_smoke", "teacher")
            assert profile.type == "teacher"
            assert users.get_or_create_from_principal(principal).username == "kid_smoke"

            attempt, _secret = attempts.create(300)
            complete = attempts.complete(attempt.attempt_id, settings, clerk_user, profile)
            payload = attempts.result_payload(complete)
            assert payload["status"] == "complete"
            decoded = decode_token(settings, payload["access_token"], "access")
            assert decoded["sub"] == "clerk:user_smoke"

            project_service = ProjectService()
            from storage.account_paths import account_root
            root = account_root(db, principal.user_id)
            project_service.save_project(root, scene_id="1", name="Smoke", blob={"graph": []})
            scene, name = project_service.get_project(root, "1")
            assert scene == {"graph": []}
            assert name == "Smoke"

            class Account:
                pass
            account = Account()
            account.principal = principal
            account.profile = profile
            account.root = root
            classroom_id, data = classrooms.create(account, {"name": "Math"})
            assert data["name"] == "Math"
            assert classrooms.load(classroom_id).read_rel("meta.doc")["teacher_account_id"] == profile.account_id

            assert billing.entitlement_status(profile.account_id)["active"] is False
            binding = billing.bind_gumroad_license(
                account_id=profile.account_id,
                license_hash="hash",
                sale={"id": "sale_1", "email": "buyer@example.com"},
                product_id="product",
                product_permalink="neuralese",
            )
            assert binding["active"] is True
            assert billing.entitlement_status(profile.account_id)["active"] is True
        finally:
            db.close()

    print("clean backend smoke OK")


if __name__ == "__main__":
    main()
