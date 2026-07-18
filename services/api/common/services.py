import storage
import common.tools as tools
from common.utils import kief

database: storage.Database = None

def set_db(db):
    global database
    database = db

def try_login(data: dict) -> storage.Node:
    user, pw = kief(data["user"]), data["pass"]
    root = database[f"/{user}/"]
    if not root.exists_rel("user.doc"): return None
    if not tools.verify_password(pw, root.read_rel("user.doc")["hash"]): return None
    return root
