_PBKDF2_ITERS = 50_000
import base64
import os
import hashlib
import secrets
import re

def hash_password(password: str) -> str:
    try:
        salt = os.urandom(16)
        dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _PBKDF2_ITERS)
        return f"{base64.urlsafe_b64encode(salt).decode()}$" \
               f"{base64.urlsafe_b64encode(dk).decode()}"
    except Exception:
        raise BaseException("Invalid Input Data")

def verify_password(password: str, stored: str) -> bool:
    try:
        salt_b64, hash_b64 = stored.split("$", 1)
        salt = base64.urlsafe_b64decode(salt_b64)
        expected_dk = base64.urlsafe_b64decode(hash_b64)
    except Exception:
        return False
    new_dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _PBKDF2_ITERS)
    return secrets.compare_digest(new_dk, expected_dk)


def get_node_docs() -> str:
	read = open("api/axon/node_docs.txt", encoding="utf-8", mode="r").read()
	return read

def get_start_prompt() -> str:
	read = open("api/axon/prompt.txt", encoding="utf-8", mode="r").read()
	read = read.replace("{node_docs}", get_node_docs())
	return read

def get_builder_prompt() -> str:
	read = open("api/axon/builder.txt", encoding="utf-8", mode="r").read()
	read = read.replace("{node_docs}", get_node_docs())
	return read



def remove_tag_blocks(text: str, tags: list[str]) -> str:
	tag_pattern = "|".join(re.escape(tag) for tag in tags)
	full = re.compile(rf"\s*<(?P<tag>{tag_pattern})>.*?</(?P=tag)>\s*", re.DOTALL)
	open_only = re.compile(rf"\s*<(?P<tag>{tag_pattern})>.*?(?=\Z|\n|$)", re.DOTALL)
	close_only = re.compile(rf"</(?P<tag>{tag_pattern})>\s*", re.DOTALL)

	while True:
		new_text, n1 = full.subn(" ", text)
		new_text, n2 = open_only.subn(" ", new_text)
		new_text, n3 = close_only.subn(" ", new_text)
		if n1 + n2 + n3 == 0:
			break
		text = new_text

	text = re.sub(r"[ \t]+", " ", text)
	text = re.sub(r"\s*\n\s*", "\n", text)
	text = re.sub(r"\n{2,}", "\n", text)
	return text.strip()