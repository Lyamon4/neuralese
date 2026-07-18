import storage

def update_last_id(node: storage.Node, scene_id: str, chat_id: str, last_id: int):
    clear = False
    chat = node.child(f"projects/{scene_id}/chats/{chat_id}.doc")
    result = []
    for i in (chat.read() or {}).get("messages", []):
        if not clear:
            result.append(i)
        if i.get("id", 0) == last_id:
            clear = True
    chat.update_doc({"messages": result, "last_id": last_id})
    return result
