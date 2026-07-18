from hashlib import sha3_224
import asyncio, json

def kief(what: str):
    return sha3_224(what.encode("utf-8")).hexdigest()

def classroom_data(root):
    got = root.read_rel("meta.doc")
    return {"name": got.get("name", ""), "classroom_data": got}

def load_classroom(app, classroom_id: str):
    #print(app.ctx.database["/classrooms/"].ls())
    root = app.ctx.database["/classrooms/"][classroom_id]
    if not root.exists_rel("meta.doc"):
        return None
    return root

def update_no_overwrite(a: dict, b: dict) -> dict:
    for i in b:
        if i not in a:
            a[i] = b[i]
    return a

async def graceful_close(ws, args: dict):
    args["_close_request"] = ""
    try:
        await ws.send(json.dumps(args))
        await asyncio.sleep(0.05)
        await ws.drain()
        await ws.recv()
        await ws.close()
    except Exception:
        pass
