# shellcheck shell=bash
# oap orca / oap gui — register the repo in Orca, create the master worktree and chat.

_orca_json_has() { # <python expression over `r` (result) and `q` ($2)> ; reads JSON on stdin
  local py; py="$(oap_python)"
  OAP_Q="${2:-}" "$py" -I -c "
import json, os, sys
q = os.environ['OAP_Q']
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
r = d.get('result', d)
sys.exit(0 if ($1) else 1)
"
}

cmd_orca() {
  local dir="${1:-.}"
  dir="$(abs_path "$dir")"; require_project "$dir"
  have orca || die "orca CLI가 필요합니다. 'oap doctor'를 확인하세요."
  local name master branch model effort
  name="$(cfg_get "$dir" PROJECT_NAME)"; master="$(cfg_get "$dir" MASTER_NAME)"
  branch="$(cfg_get "$dir" MASTER_BRANCH orca/coordinator)"
  model="$(cfg_get "$dir" MODEL_MASTER)"; effort="$(cfg_get "$dir" EFFORT_MASTER)"
  step "Orca 연결 — $name"

  if ! orca status >/dev/null 2>&1; then run orca open; fi
  git -C "$dir" rev-parse --verify -q HEAD >/dev/null \
    || die "커밋이 없어 worktree를 만들 수 없습니다. 'oap github $dir'로 첫 커밋을 올리거나 직접 커밋하세요."

  if orca repo list --json 2>/dev/null | _orca_json_has "any(x.get('path') == q for x in r.get('repos', []))" "$dir"; then
    ok "Orca 저장소 등록됨"
  else
    run orca repo add --path "$dir" --kind git --json >/dev/null
    ok "Orca 저장소 등록 (Local Mac)"
  fi

  local base="main"
  if git -C "$dir" rev-parse --verify -q refs/remotes/origin/main >/dev/null; then
    base="origin/main"
    run orca repo set-base-ref --repo "path:$dir" --ref origin/main --json >/dev/null || warn "기본 base ref 설정 실패"
  fi

  # Scope the check to this repository: other projects may have their own orca/coordinator.
  if git -C "$dir" worktree list --porcelain 2>/dev/null | grep -qx "branch refs/heads/$branch"; then
    ok "마스터 워크트리 있음 ($branch)"
  else
    run orca worktree create --repo "path:$dir" --name "$master" --branch "$branch" \
      --base-branch "$base" --setup skip --no-parent --json >/dev/null
    ok "마스터 워크트리 생성: $master ($branch)"
  fi

  say ""
  say "  마스터 채팅은 Claude 사용량을 씁니다. 처음 한 번만 만들고, 이후엔 같은 채팅을 다시 엽니다."
  if confirm "'$master' 채팅을 지금 시작할까요? ($model · $effort)"; then
    run orca agent launch --environment local --worktree "branch:$branch" \
      --agent claude --model "$model" --effort "$effort" --surface chat --focus \
      --prompt "${master}로 준비해줘. CLAUDE.md와 AGENTS.md, /orchestrate 절차를 읽고 준비됐다고 알려줘. 작업 실행은 내 다음 요청부터 시작해줘."
  fi
  say ""
  ok "다시 열기: orca worktree activate --environment local --worktree 'branch:$branch'"
  ok "작업 맡기기: 마스터 채팅에 '/orchestrate <할 일>'"
}

cmd_gui() {
  local doc="$OAP_ROOT/docs/ORCA-GUI-SETTINGS.md"
  sed -n '1,200p' "$doc"
  say ""
  say "${C_BOLD}자동 적용${C_RESET}: 위 목록을 에이전트가 Orca 화면에서 직접 바꾸게 하려면, Orca의 Claude 또는 Codex 채팅에 아래 파일 내용을 붙여넣으세요."
  say "  $OAP_ROOT/docs/ORCA-GUI-AGENT-PROMPT.md"
}
