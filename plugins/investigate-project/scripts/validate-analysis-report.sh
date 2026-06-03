#!/usr/bin/env bash
# validate-analysis-report.sh — 半自动校验 analysis-report 产物（主线程阶段 1 预检 / 阶段 6 出口门禁）
# 用法: validate-analysis-report.sh <REPORT_ROOT> [--strict]
set -euo pipefail

ROOT="${1:?用法: $0 <REPORT_ROOT> [--strict]}"
STRICT="${2:-}"

fail=0
warn=0

err() { echo "ERROR: $*" >&2; fail=$((fail + 1)); }
warn_msg() { echo "WARN: $*" >&2; warn=$((warn + 1)); }

# --- project-overview.json ---
PO="$ROOT/project-overview.json"
if [[ ! -f "$PO" ]]; then
  err "缺少 project-overview.json"
else
  if command -v jq >/dev/null 2>&1; then
    sc=$(jq '.scenarios | length' "$PO" 2>/dev/null || echo 0)
    ps=$(jq '.problems_solved | length' "$PO" 2>/dev/null || echo 0)
    [[ "$sc" -ge 2 ]] || err "scenarios 条数 < 2 (got $sc)"
    [[ "$ps" -ge 3 ]] || err "problems_solved 条数 < 3 (got $ps)"
    al=$(jq '.module_landscape.architecture_layers | length' "$PO" 2>/dev/null || echo 0)
    [[ "$al" -ge 2 ]] || err "module_landscape.architecture_layers < 2"
    ok_ps=$(jq '[.problems_solved[] | ((.causal_chain // []) | length >= 3) or (((.contrast // "") | length > 0) and ((.mechanism_at_a_glance // "") | length > 0))] | all' "$PO" 2>/dev/null || echo false)
    [[ "$ok_ps" == "true" ]] || err "某条 problems_solved 缺 causal_chain(≥3层) 或 contrast+mechanism_at_a_glance"
    if [[ "$STRICT" == "--strict" ]]; then
      min_chars=$(jq '[.problems_solved[].narrative | length] | min // 0' "$PO")
      [[ "$min_chars" -ge 120 ]] || warn_msg "某条 problems_solved.narrative < 120 字（结构齐全时可接受）"
    fi
  else
    warn_msg "未安装 jq，跳过 project-overview.json 结构校验"
  fi
fi

# --- overview.md ---
OV="$ROOT/overview.md"
if [[ -f "$OV" ]]; then
  if grep -E '^\|[^|]+\|' "$OV" >/dev/null 2>&1; then
    err "overview.md 含 markdown 表格行"
  fi
  grep -q '功能模块与协作关系' "$OV" || err "overview.md 缺少 §6 功能模块与协作关系"
  h2_sc=$(grep -c '^### ' "$OV" || true)
  [[ "$h2_sc" -ge 2 ]] || warn_msg "overview.md ### 小节较少（期望 §2/§3 多条）"
  # final 与「全部通过」矛盾
  if compgen -G "$ROOT/quality-review/**/*-final.json" >/dev/null 2>&1; then
    if grep -q '质量质审均在约定轮次内通过' "$OV" 2>/dev/null; then
      err "存在 *-final.json 但 overview 仍写「全部通过」"
    fi
  fi
fi

# --- feature-plan vs finals ---
FP="$ROOT/feature-plan.json"
if [[ -f "$FP" ]] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r slug; do
    [[ -n "$slug" ]] || continue
    if [[ -f "$ROOT/quality-review/features/${slug}-final.json" ]]; then
      : # ok
    fi
  done < <(jq -r '.features[].slug' "$FP" 2>/dev/null)
fi

echo "---"
if [[ $fail -gt 0 ]]; then
  echo "校验失败: $fail 个错误, $warn 个警告"
  exit 1
fi
echo "校验通过（$warn 个警告）"
exit 0
