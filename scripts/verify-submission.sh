#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_paths=(
  "apps/builder/project.godot"
  "apps/block-editor/package.json"
  "services/api/app_bp.py"
  "services/backend/app.py"
  "services/landing/package.json"
  "runtime/onnx-training/README.md"
  "installer/setup/src-tauri/Cargo.toml"
  "research/Neuralese-ISEF-2026.pdf"
  "dist/Neuralese-Windows-x86_64.exe"
  "dist/Neuralese-macOS-universal.dmg"
)

for path in "${required_paths[@]}"; do
  if [[ ! -e "$ROOT/$path" ]]; then
    printf 'missing required path: %s\n' "$path" >&2
    exit 1
  fi
done

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$ROOT/dist" && sha256sum --check SHA256SUMS)
else
  while read -r expected file; do
    actual="$(shasum -a 256 "$ROOT/dist/$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
      printf 'checksum mismatch: %s\n' "$file" >&2
      exit 1
    fi
    printf '%s: OK\n' "$file"
  done < "$ROOT/dist/SHA256SUMS"
fi

windows_type="$(file -b "$ROOT/dist/Neuralese-Windows-x86_64.exe")"
if [[ "$windows_type" != *"PE32+ executable"* || "$windows_type" != *"x86-64"* ]]; then
  printf 'unexpected Windows artifact: %s\n' "$windows_type" >&2
  exit 1
fi

if command -v hdiutil >/dev/null 2>&1; then
  hdiutil verify "$ROOT/dist/Neuralese-macOS-universal.dmg" >/dev/null
fi

pdf_type="$(file -b "$ROOT/research/Neuralese-ISEF-2026.pdf")"
if [[ "$pdf_type" != PDF* ]]; then
  printf 'unexpected research artifact: %s\n' "$pdf_type" >&2
  exit 1
fi

printf 'Neuralese submission integrity: OK\n'
