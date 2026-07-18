from __future__ import annotations

from hashlib import sha3_224


def account_id_for_user_id(user_id: str) -> str:
    return sha3_224(user_id.encode("utf-8")).hexdigest()


def account_root(db, user_id: str):
    return db[f"/accounts/{account_id_for_user_id(user_id)}/"]
