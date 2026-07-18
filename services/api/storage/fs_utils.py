def normalize_path(path: str) -> str:
	path = path.strip()
	if not path.startswith("/"):
		path = "/" + path
	return path.rstrip("/") if path != "/" else path

def normalize_prefix(path: str) -> str:
	p = normalize_path(path)
	if not p.endswith("/"):
		p += "/"
	return p
