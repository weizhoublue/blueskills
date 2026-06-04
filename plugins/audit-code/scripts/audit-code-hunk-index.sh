#!/usr/bin/env bash
# Usage: audit-code-hunk-index.sh <REVIEW_TMP>
# Reads: $REVIEW_TMP/raw-diff.patch, $REVIEW_TMP/review-files.json
# Writes: $REVIEW_TMP/hunk-index.json
set -euo pipefail

REVIEW_TMP="${1:?usage: audit-code-hunk-index.sh <REVIEW_TMP>}"
PATCH="$REVIEW_TMP/raw-diff.patch"
FILES_JSON="$REVIEW_TMP/review-files.json"
OUT="$REVIEW_TMP/hunk-index.json"

if [[ ! -f "$FILES_JSON" ]]; then
  echo "audit-code-hunk-index: missing review-files.json" >&2
  exit 1
fi

python3 - "$PATCH" "$FILES_JSON" "$OUT" <<'PY'
import json
import re
import sys
from pathlib import Path

patch_path, files_json_path, out_path = sys.argv[1:4]
patch_text = Path(patch_path).read_text(encoding="utf-8", errors="replace") if Path(patch_path).is_file() else ""

data = json.loads(Path(files_json_path).read_text(encoding="utf-8"))
file_entries = data.get("files", [])
if isinstance(file_entries, dict):
    paths = list(file_entries.keys())
elif isinstance(file_entries, list):
    if file_entries and isinstance(file_entries[0], str):
        paths = file_entries
    else:
        paths = [f.get("path") or f.get("file") for f in file_entries if isinstance(f, dict)]
else:
    paths = []

# Parse unified diff per file
per_file_lines: dict[str, list[str]] = {}
current: str | None = None
for line in patch_text.splitlines():
    if line.startswith("diff --git "):
        m = re.match(r"diff --git a/(.+?) b/(.+)$", line)
        if m:
            current = m.group(2)
            per_file_lines.setdefault(current, [])
        continue
    if line.startswith("+++ b/"):
        current = line[6:].strip()
        if current == "/dev/null":
            current = None
        else:
            per_file_lines.setdefault(current, [])
        continue
    if current and (line.startswith("+") or line.startswith("-") or line.startswith(" ")):
        if not line.startswith("+++") and not line.startswith("---"):
            per_file_lines.setdefault(current, []).append(line)

func_re = re.compile(
    r"^[+-]\s*(?:func\s+(\w+)|(?:\w+\s+)?(\w+)\s*\([^)]*\)\s*\{)",
    re.MULTILINE,
)
method_re = re.compile(r"^[+-]\s*func\s+\([^)]+\)\s*(\w+)\s*\(", re.MULTILINE)

def symbols_from_hunk(lines: list[str]) -> list[str]:
    found: list[str] = []
    chunk = "\n".join(lines)
    for m in func_re.finditer(chunk):
        name = m.group(1) or m.group(2)
        if name and name not in found:
            found.append(name)
    for m in method_re.finditer(chunk):
        if m.group(1) not in found:
            found.append(m.group(1))
    return found[:20]

def hunk_summary(lines: list[str], max_lines: int = 80) -> str:
    if not lines:
        return ""
    trimmed = lines[:max_lines]
    text = "\n".join(trimmed)
    if len(lines) > max_lines:
        text += f"\n... ({len(lines) - max_lines} more diff lines)"
    return text

out_files = []
for path in paths:
    if not path:
        continue
    lines = per_file_lines.get(path, [])
    added = sum(1 for ln in lines if ln.startswith("+") and not ln.startswith("+++"))
    removed = sum(1 for ln in lines if ln.startswith("-") and not ln.startswith("---"))
    out_files.append(
        {
            "path": path,
            "lines_added": added,
            "lines_removed": removed,
            "symbols_touched": symbols_from_hunk(lines),
            "hunk_summary": hunk_summary(lines),
        }
    )

result = {"version": 1, "files": out_files}
Path(out_path).write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo "wrote $OUT"
