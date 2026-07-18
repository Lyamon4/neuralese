from __future__ import annotations

import copy
import hashlib
import random


class ClassroomService:
    def __init__(self, db):
        self.db = db

    def root(self):
        return self.db["/classrooms/"]

    def load(self, classroom_id: str):
        root = self.root()[classroom_id]
        return root if root.exists_rel("meta.doc") else None

    def generate_id(self) -> str:
        root = self.root()
        for _ in range(50):
            cid = f"{random.randint(0, 999999):06d}"
            if not root.exists_rel(f"{cid}/meta.doc"):
                return cid
        raise RuntimeError("failed to allocate classroom id")

    def public_data(self, classroom_root) -> dict:
        meta = classroom_root.read_rel("meta.doc") or {}
        return {"name": meta.get("name", ""), "classroom_data": copy.deepcopy(meta)}

    def snapshot(self, classroom_root) -> dict:
        return {
            "classroom_id": classroom_root.name,
            "meta": classroom_root.read_rel("meta.doc") or {},
            "students": classroom_root.read_rel("students.doc") or {},
        }

    def is_teacher(self, profile) -> bool:
        return profile.type == "teacher"

    def create(self, account, meta_patch: dict) -> tuple[str, dict]:
        if not self.is_teacher(account.profile):
            raise PermissionError("not_teacher")
        classroom_id = self.generate_id()
        account.root.update_doc_rel("config.doc", {"my_classroom": classroom_id})
        root = self.root()[classroom_id]
        meta = {
            "teacher_account_id": account.profile.account_id,
            "teacher_user_id": account.profile.user_id,
            "teacher_username": account.profile.username,
            "name": "",
            "classroom_data": {},
            "lesson_customs": {},
        }
        meta.update(meta_patch or {})
        meta = self.store_lesson_auto_projects(root, meta)
        root.write_rel("meta.doc", meta)
        root.write_rel("students.doc", {})
        return classroom_id, self.public_data(root)

    def join(self, account, classroom_id: str):
        root = self.load(classroom_id)
        if not root:
            raise FileNotFoundError("not_found")
        account.root.update_doc_rel("config.doc", {"my_classroom": classroom_id})
        students = root.read_rel("students.doc") or {}
        students[account.profile.account_id] = {"username": account.profile.username, "awaiting": False}
        root.write_rel("students.doc", students)
        return self.public_data(root)

    def require_teacher(self, account, classroom_root) -> None:
        meta = classroom_root.read_rel("meta.doc") or {}
        if meta.get("teacher_account_id") != account.profile.account_id:
            raise PermissionError("not_teacher")

    def store_lesson_auto_projects(self, classroom_root, meta: dict) -> dict:
        result = copy.deepcopy(meta or {})
        lessons = result.get("lessons", {})
        if not isinstance(lessons, dict):
            return result
        for lesson_key, lesson in lessons.items():
            if not isinstance(lesson, dict):
                continue
            auto_project = lesson.get("auto_project")
            if not isinstance(auto_project, dict):
                continue
            blob = auto_project.pop("blob", "")
            if not blob:
                continue
            import base64
            raw = base64.b64decode(str(blob).encode("ascii"), validate=True)
            ref = f"lesson_auto_projects/{self._lesson_blob_key(str(lesson_key))}.blob"
            classroom_root.write_rel(ref, raw)
            auto_project["blob_ref"] = ref
            auto_project["encoding"] = "base64_var_bytes"
        return result

    def lesson_auto_project_blob(self, classroom_root, lesson_key: str) -> str | None:
        import base64
        meta = classroom_root.read_rel("meta.doc") or {}
        lessons = meta.get("lessons", {})
        if not isinstance(lessons, dict):
            return None
        lesson = lessons.get(lesson_key)
        if not isinstance(lesson, dict):
            return None
        auto_project = lesson.get("auto_project")
        if not isinstance(auto_project, dict):
            return None
        ref = str(auto_project.get("blob_ref", ""))
        if not ref:
            return None
        raw = classroom_root.read_rel(ref)
        if not isinstance(raw, (bytes, bytearray)):
            return None
        return base64.b64encode(bytes(raw)).decode("ascii")

    def _lesson_blob_key(self, lesson_key: str) -> str:
        digest = hashlib.sha256(lesson_key.encode("utf-8")).hexdigest()
        return digest
