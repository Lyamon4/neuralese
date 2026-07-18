from __future__ import annotations


def validate_scene_id(scene_id: str) -> bool:
    return str(scene_id).isdigit()


class ProjectService:
    def save_project(self, account_root, *, scene_id: str, name: str, blob, chat_id: str = "", last_id: int = -1) -> None:
        account_root.write_rel(f"projects/{scene_id}/data.scn", blob)
        account_root.write_rel(f"projects/{scene_id}/meta.doc", {"name": name})
        if not account_root.exists_rel(f"projects/{scene_id}/chats/metas.doc"):
            account_root.write_rel(f"projects/{scene_id}/chats/metas.doc", {})
        if not account_root.exists_rel(f"projects/{scene_id}/contexts/meta.doc"):
            account_root.write_rel(f"projects/{scene_id}/contexts/meta.doc", {})
        if last_id != -1 and chat_id:
            self.update_last_id(account_root, scene_id, chat_id, last_id)

    def update_last_id(self, account_root, scene_id: str, chat_id: str, last_id: int) -> list:
        chat = account_root.child(f"projects/{scene_id}/chats/{chat_id}.doc")
        data = chat.read() or {}
        result = []
        clear = False
        for msg in data.get("messages", []):
            if not clear:
                result.append(msg)
            if msg.get("id", 0) == last_id:
                clear = True
        data["messages"] = result
        data["last_id"] = last_id
        chat.write(data)
        return result

    def get_project(self, account_root, scene_id: str) -> tuple[object, str] | None:
        meta = account_root.read_rel(f"projects/{scene_id}/meta.doc")
        if not isinstance(meta, dict):
            return None
        return account_root.read_rel(f"projects/{scene_id}/data.scn"), str(meta.get("name", ""))

    def delete_project(self, account_root, scene_id: str) -> None:
        account_root.delete_rel(f"projects/{scene_id}")

    def list_projects(self, account_root) -> dict:
        root = account_root.child("projects")
        result = {}
        for name in root.ls():
            if not name.endswith(".doc"):
                meta = root.read_rel(f"{name}/meta.doc")
                if isinstance(meta, dict):
                    result[name] = meta
        return result
