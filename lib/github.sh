# shellcheck shell=bash
# oap github — repository, main ruleset, auto-merge and branch cleanup.

cmd_github() {
  local dir="${1:-.}"
  dir="$(abs_path "$dir")"; require_project "$dir"
  have gh || die "gh가 필요합니다. 'oap setup'을 먼저 실행하세요."
  gh auth status >/dev/null 2>&1 || die "GitHub 로그인이 필요합니다: gh auth login"
  local repo key ci; repo="$(cfg_get "$dir" GITHUB_REPO)"; key="$(cfg_get "$dir" PROJECT_KEY)"; ci="$(cfg_get "$dir" CI_NAME)"
  step "GitHub 설정 — $repo"

  # 1. Repository
  if gh repo view "$repo" >/dev/null 2>&1; then
    ok "저장소 있음: https://github.com/$repo"
  else
    say "  저장소가 없습니다. 개인 계정의 비공개 저장소는 GitHub Pro가 아니면 룰셋(main 보호)을 쓸 수 없습니다."
    local visibility="--private"
    if confirm "https://github.com/$repo 를 공개(public) 저장소로 만들까요? (아니오 = 비공개)"; then visibility="--public"; fi
    if confirm "GitHub에 $repo 저장소를 만들고 현재 커밋을 올릴까요?"; then
      initial_commit "$dir"
      run gh repo create "$repo" "$visibility" --source "$dir" --remote origin --push
    else
      warn "저장소 생성을 건너뛰었습니다."; [ "$OAP_DRY_RUN" = 1 ] || return 0
    fi
  fi
  if ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    run git -C "$dir" remote add origin "https://github.com/$repo.git"
  fi
  if ! git -C "$dir" ls-remote --exit-code origin main >/dev/null 2>&1; then
    if confirm "원격 main이 비어 있습니다. 하네스 첫 커밋을 main에 올릴까요?"; then
      initial_commit "$dir"
      run git -C "$dir" push -u origin main
    fi
  fi

  # 2. Merge settings: squash only, PR title as commit title, auto-merge, delete merged branches.
  say "  병합 설정: squash만 허용 · 커밋 제목 = PR 제목 · 자동 병합 · 병합된 브랜치 자동 삭제"
  if confirm "$repo 의 병합 설정을 바꿀까요?"; then
    run gh api -X PATCH "repos/$repo" --silent \
      -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
      -F allow_auto_merge=true -F delete_branch_on_merge=true -F allow_update_branch=true \
      -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=BLANK
    ok "병합 설정 적용"
  fi

  # 3. Ruleset protecting main.
  local name="oap: protect main" body existing
  body="$(ruleset_json "$name" "$ci" "$key")"
  existing="$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$name\") | .id" 2>/dev/null || true)"
  case "$existing" in ''|*[!0-9]*) existing="" ;; esac
  say "  main 룰셋: PR 필수 · 강제 푸시/삭제 금지 · 최신 main 반영 필수 · 필수 검사 [$ci, $key/review-claude, $key/review-codex]"
  if confirm "main 브랜치 룰셋을 $([ -n "$existing" ] && echo 갱신 || echo 생성)할까요?"; then
    local tmp; tmp="$(mktemp -t oap-ruleset)"; printf '%s' "$body" > "$tmp"
    if [ -n "$existing" ]; then run gh api -X PUT "repos/$repo/rulesets/$existing" --input "$tmp" --silent
    else run gh api -X POST "repos/$repo/rulesets" --input "$tmp" --silent; fi
    rm -f "$tmp"
    ok "룰셋 적용 — https://github.com/$repo/settings/rules"
  fi
  dim "  두 리뷰 판정은 GitHub 봇이 아니라 마스터가 병합 실행기로 커밋 상태에 게시합니다."
}

initial_commit() {
  if git -C "$1" rev-parse --verify HEAD >/dev/null 2>&1; then return 0; fi
  run git -C "$1" add -A
  run git -C "$1" commit -m "chore: orca-autopilot 하네스 초기화"
}

ruleset_json() { # name ci key
  local py; py="$(oap_python)"
  "$py" -I -c '
import json, sys
name, ci, key = sys.argv[1:4]
print(json.dumps({
    "name": name,
    "target": "branch",
    "enforcement": "active",
    "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
    "bypass_actors": [],
    "rules": [
        {"type": "deletion"},
        {"type": "non_fast_forward"},
        {"type": "pull_request", "parameters": {
            "required_approving_review_count": 0,
            "dismiss_stale_reviews_on_push": True,
            "require_code_owner_review": False,
            "require_last_push_approval": False,
            "required_review_thread_resolution": True,
            "allowed_merge_methods": ["squash"],
        }},
        {"type": "required_status_checks", "parameters": {
            "strict_required_status_checks_policy": True,
            "do_not_enforce_on_create": False,
            "required_status_checks": [
                {"context": ci, "integration_id": 15368},
                {"context": key + "/review-claude"},
                {"context": key + "/review-codex"},
            ],
        }},
    ],
}, ensure_ascii=False))
' "$1" "$2" "$3"
}
