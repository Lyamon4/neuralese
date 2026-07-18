bins = {}

def persist_binary(topo: str, key: str, binary: bytes):
	if not topo in bins: bins[topo] = {key: binary}
	else: bins[topo][key] = binary

def get_persisted_binary(topo:str, key: str):
	root = bins.get(topo, {})
	if not root: return None
	return root.get(key, None)