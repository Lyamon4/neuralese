def normalize_path(path: str) -> str:
    path = "/" + "/".join(part for part in str(path).replace("\\", "/").split("/") if part)
    if path != "/" and path.endswith("/"):
        path = path[:-1]
    return path


def normalize_prefix(path: str) -> str:
    path = normalize_path(path)
    return "/" if path == "/" else path.rstrip("/") + "/"
