#!/usr/bin/env bash
# Offline tests: no network, no Orca/GitHub writes. Run: tests/run.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }

echo "== bash syntax"
for f in "$ROOT"/bin/oap "$ROOT"/lib/*.sh "$ROOT"/install.sh; do check bash -n "$f"; done
if command -v shellcheck >/dev/null; then
  echo "== shellcheck"; check shellcheck -x -S warning "$ROOT"/bin/oap "$ROOT"/lib/*.sh "$ROOT"/install.sh
else echo "(shellcheck 없음 — 건너뜀)"; fi

echo "== merge runner unit tests"
check bash -c "cd '$ROOT/merge' && python3 -B -m unittest -q test_orca_merge"

export HOME="$TMP/home"; mkdir -p "$HOME/.codex"   # never touch the real ~/.codex
export NO_COLOR=1
for preset in generic expo; do
  echo "== init ($preset)"
  d="$TMP/app-$preset"
  check "$ROOT/bin/oap" init "$d" --name "테스트 앱" --key demo --repo acme/demo-app --preset "$preset" >/dev/null
  check test -f "$d/orca-autopilot.json"
  check test -f "$d/.github/workflows/demo-ci.yml"
  check test -f "$d/.claude/skills/orchestrate/SKILL.md"
  # No unrendered {{TOKENS}} anywhere.
  if grep -rIl '{{[A-Z0-9_]*}}' "$d" --exclude-dir=.git; then echo "FAIL: unrendered tokens" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi
  check python3 -m json.tool "$d/.claude/settings.json" >/dev/null
  check python3 -m json.tool "$d/orca-autopilot.json" >/dev/null
  check grep -q 'name: DEMO CI' "$d/.github/workflows/demo-ci.yml"
  check grep -q 'DEMO-REVIEW-TARGET' "$d/.claude/skills/orchestrate/SKILL.md"
  check grep -q 'acme/demo-app' "$d/.claude/settings.json"
  # Re-running is idempotent: nothing created, nothing in conflict.
  out="$("$ROOT/bin/oap" init "$d")"
  check grep -q 'created 0, unchanged [1-9][0-9]*, conflict 0' <<<"$out"
  # A locally edited file is never overwritten without --force.
  echo "local edit" >> "$d/REVIEW.md"
  "$ROOT/bin/oap" init "$d" >/dev/null || true
  check test -f "$d/REVIEW.md.oap-new"
  check grep -q 'local edit' "$d/REVIEW.md"
done
check test -f "$TMP/app-expo/docs/development/MOBILE-DEVICE.md"
check test ! -f "$TMP/app-generic/docs/development/MOBILE-DEVICE.md"
check test ! -e "$TMP/app-expo/.oap-preset"

echo "== title checker"
check python3 -c "
import importlib.util, sys
s = importlib.util.spec_from_file_location('t', '$TMP/app-generic/.github/scripts/check_git_titles.py'); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
good = ['feat: 로그인 화면 추가', 'fix(auth): 토큰 만료 처리 수정', 'feat!: 설정 구조 변경']
bad = ['Add login screen', 'feat: add login', 'feat:로그인', 'feature: 로그인 추가', '']
assert all(m.valid_title(t) for t in good), good
assert not any(m.valid_title(t) for t in bad), bad
"

echo "== merge runner render"
d="$TMP/app-generic"; bin="$TMP/bin/demo-orca-merge"; mkdir -p "$TMP/bin"
python3 - "$d/orca-autopilot.json" "$bin" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1])); cfg["MERGE_BIN"] = sys.argv[2]
json.dump(cfg, open(sys.argv[1], "w"))
PY
check "$ROOT/bin/oap" merge-runner "$d" >/dev/null
check test -x "$bin"
check grep -q '"repo": "acme/demo-app"' "$bin"
check bash -c "'$bin' --pr 1 --sha bad --run run_x 2>&1 | grep -q 'Expected a PR number'"

echo "== github ruleset json"
check bash -c ". '$ROOT/lib/common.sh'; . '$ROOT/lib/github.sh'; ruleset_json 'n' 'DEMO CI' demo | python3 -c 'import json,sys; r=json.load(sys.stdin); c=[x[\"context\"] for x in r[\"rules\"][3][\"parameters\"][\"required_status_checks\"]]; assert c==[\"DEMO CI\",\"demo/review-claude\",\"demo/review-codex\"], c'"

echo "== dry-run setup prints but changes nothing"
check bash -c "OAP_DRY_RUN=1 '$ROOT/bin/oap' setup --dry-run >/dev/null 2>&1 || true; test ! -f '$HOME/.codex/rules/orca-orchestration.rules'"

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
