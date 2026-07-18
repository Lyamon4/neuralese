import subprocess
from pathlib import Path

# CONFIG
REPO_PATH = R"C:\godotprojs\nnets\teachneurons"
OUTPUT_FILE = "commits_FRONT.txt"


def run_git(repo_path, args):
	result = subprocess.run(
		["git", "-C", repo_path] + args,
		capture_output=True,
		text=True,
		encoding="utf-8",
		errors="replace"
	)

	if result.returncode != 0:
		raise RuntimeError("Git command failed:\n" + result.stderr)

	return result.stdout


def get_git_log(repo_path):
	cmd = [
		"log",
		"--all",
		"--date=format:%Y-%m-%d %H:%M",
		"--pretty=format:===COMMIT===%n%ad | %h | %an%n%s",
		"--numstat"
	]

	raw = run_git(repo_path, cmd)

	return compact_numstat(raw)


def compact_numstat(raw_log):
	blocks = raw_log.split("===COMMIT===")
	entries = []

	for block in blocks:
		block = block.strip()

		if not block:
			continue

		lines = block.splitlines()

		header = lines[0]
		subject = lines[1] if len(lines) > 1 else ""

		file_changes = []

		for line in lines[2:]:
			parts = line.split("\t")

			if len(parts) != 3:
				continue

			added, deleted, filename = parts

			if added == "-":
				added = "bin"
			if deleted == "-":
				deleted = "bin"

			file_changes.append(f"- {filename} (+{added}/-{deleted})")

		if not file_changes:
			file_changes_text = "- no file-level changes"
		else:
			file_changes_text = "\n".join(file_changes)

		entry = f"""===COMMIT===
{header}
{subject}
Files:
{file_changes_text}
"""

		entries.append(entry)

	return "\n\n".join(entries)


def save_to_file(data, filename):
	Path(filename).write_text(data, encoding="utf-8")


if __name__ == "__main__":
	log_data = get_git_log(REPO_PATH)
	save_to_file(log_data, OUTPUT_FILE)
	print(f"Saved compact commit log to {OUTPUT_FILE}")