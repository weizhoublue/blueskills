#!/usr/bin/env bash
# Usage: audit-code-triage.sh <REVIEW_TMP>
# Reads: review-files.json, optional change-context.json, raw-diff.patch, scope.json
# Writes: review-profile.json
set -euo pipefail

REVIEW_TMP="${1:?usage: audit-code-triage.sh <REVIEW_TMP>}"
OUT="$REVIEW_TMP/review-profile.json"

export REVIEW_TMP REVIEW_DEPTH="${REVIEW_DEPTH:-}"

python3 - "$REVIEW_TMP" "$OUT" <<'PY'
import json
import os
import re
from pathlib import Path

review_tmp = Path(os.environ["REVIEW_TMP"])
out_path = Path(os.environ.get("OUT", review_tmp / "review-profile.json"))
if len(os.sys.argv) >= 3:
    out_path = Path(os.sys.argv[2])

def load_json(name: str) -> dict:
    p = review_tmp / name
    if p.is_file():
        return json.loads(p.read_text(encoding="utf-8"))
    return {}

files_doc = load_json("review-files.json")
ctx = load_json("change-context.json")
patch = (review_tmp / "raw-diff.patch").read_text(encoding="utf-8", errors="replace") if (review_tmp / "raw-diff.patch").is_file() else ""

files: list[str] = []
raw = files_doc.get("files", [])
if isinstance(raw, list):
    for item in raw:
        if isinstance(item, str):
            files.append(item)
        elif isinstance(item, dict):
            files.append(item.get("path") or item.get("file", ""))
elif isinstance(raw, dict):
    files = list(raw.keys())

files = [f for f in files if f]
total_added = total_removed = 0
for ent in load_json("hunk-index.json").get("files", []):
    total_added += int(ent.get("lines_added") or 0)
    total_removed += int(ent.get("lines_removed") or 0)
if not total_added and not total_removed and patch:
    total_added = sum(1 for ln in patch.splitlines() if ln.startswith("+") and not ln.startswith("+++"))
    total_removed = sum(1 for ln in patch.splitlines() if ln.startswith("-") and not ln.startswith("---"))

change_kind = ctx.get("change_kind") or "unknown"
if change_kind == "unknown" and re.search(r"\b(fix|bug|hotfix|patch)\b", patch, re.I):
    change_kind = "bugfix"

docs_only = bool(files) and all(
    f.startswith("docs/") or f.endswith(".md") or f.endswith(".rst") or f.endswith(".adoc")
    for f in files
)
tiny = len(files) <= 3 and (total_added + total_removed) < 80

skip_kinds: list[str] = []
enable_architecture = not tiny
enable_residual = change_kind == "bugfix"
enable_security = bool(re.search(r"auth|token|password|Validate|http\.|HandleFunc|ServeHTTP", patch, re.I))

if docs_only:
    enable_residual = False
    enable_security = False
    skip_kinds.extend(["performance", "security"])

if tiny:
    enable_architecture = False
    skip_kinds.append("performance")

if change_kind != "bugfix":
    enable_residual = False

if not enable_security:
    skip_kinds.append("security")

depth = "fast"
if os.environ.get("REVIEW_DEPTH", "").lower() == "full":
    depth = "full"
    enable_architecture = True

skip_kinds = sorted(set(skip_kinds))
reasons = []
if docs_only:
    reasons.append("docs_only")
if tiny:
    reasons.append("tiny_diff")
if change_kind != "bugfix":
    reasons.append(f"change_kind={change_kind}")
if depth == "full":
    reasons.append("REVIEW_DEPTH=full")

profile = {
    "version": 1,
    "depth": depth,
    "skip_kinds": skip_kinds,
    "enable_architecture": enable_architecture,
    "enable_residual": enable_residual,
    "enable_security": enable_security,
    "rationale": "; ".join(reasons) if reasons else "default",
    "stats": {
        "file_count": len(files),
        "lines_added": total_added,
        "lines_removed": total_removed,
        "change_kind": change_kind,
    },
}

out_path.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo "wrote $OUT"
