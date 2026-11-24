# shellcheck shell=bash
# oap init / oap merge-runner — project harness and the reviewed-merge runner.

OAP_CONFIG_FILE="orca-autopilot.json"

# cfg_get <project-dir> <key> [default]
cfg_get() {
  local py; py="$(oap_python)" || die "python3가 필요합니다."
  "$py" -I -c '
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2], sys.argv[3]))
except FileNotFoundError:
    print(sys.argv[3])
' "$1/$OAP_CONFIG_FILE" "$2" "${3:-}"
}

require_project() {
  [ -f "$1/$OAP_CONFIG_FILE" ] || die "$1 에 $OAP_CONFIG_FILE 이 없습니다. 먼저 'oap init $1'을 실행하세요."
}

abs_path() { (cd "$1" && pwd -P); }

cmd_init() {
  local dir="" name="" key="" repo="" preset="" force=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --name=*) name="${1#*=}"; shift ;;
      --key) key="$2"; shift 2 ;;
      --key=*) key="${1#*=}"; shift ;;
      --repo) repo="$2"; shift 2 ;;
      --repo=*) repo="${1#*=}"; shift ;;
      --preset) preset="$2"; shift 2 ;;
      --preset=*) preset="${1#*=}"; shift ;;
      --force) force="--force"; shift ;;
      -*) die "알 수 없는 옵션: $1" ;;
      *) [ -z "$dir" ] || die "폴더는 하나만 지정하세요."; dir="$1"; shift ;;
    esac
  done
  [ -n "$dir" ] || die "사용법: oap init <폴더> [--name 이름] [--key 키] [--repo owner/name] [--preset expo|generic]"
  if [ "$OAP_DRY_RUN" = 1 ] && [ ! -d "$dir" ]; then
    dir="$(cd "$(dirname "$dir")" 2>/dev/null && pwd -P)/$(basename "$dir")"
  else
    mkdir -p "$dir"; dir="$(abs_path "$dir")"
  fi
  local base; base="$(basename "$dir")"

  # Existing config supplies defaults so re-running init upgrades templates in place.
  [ -n "$name" ] || name="$(cfg_get "$dir" PROJECT_NAME "$base")"
  if [ -z "$key" ]; then
    key="$(cfg_get "$dir" PROJECT_KEY "")"
    [ -n "$key" ] || key="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-8)"
  fi
  printf '%s' "$key" | grep -Eq '^[a-z][a-z0-9]{0,11}$' || die "--key는 영문 소문자로 시작하는 1~12자(영문 소문자·숫자)여야 합니다: '$key'"
  [ -n "$preset" ] || preset="$(cfg_get "$dir" PRESET generic)"
  [ -d "$OAP_ROOT/templates/presets/$preset" ] || die "알 수 없는 프리셋: $preset (expo | generic)"
  if [ -z "$repo" ]; then
    repo="$(cfg_get "$dir" GITHUB_REPO "")"
    if [ -z "$repo" ]; then
      local login=""; have gh && login="$(gh api user --jq .login 2>/dev/null || true)"
      [ -n "$login" ] || { login="OWNER"; warn "gh 로그인 계정을 몰라 저장소를 OWNER/$base 로 둡니다. --repo로 지정하세요."; }
      repo="$login/$base"
    fi
  fi
  printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$' || die "--repo는 owner/name 형식이어야 합니다: '$repo'"

  local upper; upper="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  local merge_bin; merge_bin="$(cfg_get "$dir" MERGE_BIN "$(brew_prefix)/bin/${key}-orca-merge")"
  local py; py="$(oap_python)" || die "python3가 필요합니다."
  local vars; vars="$(mktemp -t oap-vars)"
  "$py" -I - "$vars" "$dir/$OAP_CONFIG_FILE" "$OAP_VERSION" "$name" "$key" "$upper" "$preset" "$repo" "$merge_bin" <<'PY'
import json, sys
out, cfg_path, version, name, key, upper, preset, repo, merge_bin = sys.argv[1:10]
existing = {}
try:
    existing = json.load(open(cfg_path, encoding="utf-8"))
except FileNotFoundError:
    pass
values = {
    "OAP_VERSION": version,
    "PROJECT_NAME": name,
    "PROJECT_KEY": key,
    "KEY_UPPER": upper,
    "PRESET": preset,
    "GITHUB_REPO": repo,
    "GITHUB_OWNER": repo.split("/", 1)[0],
    "MASTER_BRANCH": "orca/coordinator",
    "MERGE_BIN": merge_bin,
    "CI_NAME": upper + " CI",
    "REVIEW_MARK": upper + "-REVIEW",
    "MODEL_MASTER": "claude-opus-5-5",
    "EFFORT_MASTER": "high",
    "MODEL_DEV": "claude-sonnet-5-5",
    "EFFORT_DEV": "medium",
    "MODEL_REVIEW_CLAUDE": "claude-sonnet-5-5",
    "EFFORT_REVIEW_CLAUDE": "high",
    "MODEL_CODEX": "gpt-6.2-sol",
    "EFFORT_CODEX": "high",
    "MAX_REVIEW_ROUNDS": "3",
}
# Model choices the user edited in the config survive a re-run.
for k in list(values):
    if k.startswith(("MODEL_", "EFFORT_", "MAX_")) and k in existing:
        values[k] = existing[k]
values["MASTER_NAME"] = values["PROJECT_NAME"] + " 마스터"
json.dump(values, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY

  step "oap init — $name ($key, $preset) → $dir"
  if [ ! -d "$dir/.git" ]; then run git -C "$dir" init -b main; fi
  local rc=0
  "$py" -I "$OAP_ROOT/lib/render.py" "$vars" "$dir" \
    "$OAP_ROOT/templates/base" "$OAP_ROOT/templates/presets/$preset" $force \
    $([ "$OAP_DRY_RUN" = 1 ] && echo --dry-run) || rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 3 ] || die "템플릿 렌더링 실패"
  if [ "$OAP_DRY_RUN" != 1 ]; then
    "$py" -I -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); json.dump(d,open(sys.argv[2],"w",encoding="utf-8"),ensure_ascii=False,indent=2); open(sys.argv[2],"a").write("\n")' \
      "$vars" "$dir/$OAP_CONFIG_FILE"
    ok "$OAP_CONFIG_FILE 저장 (모델·노력치를 바꾸려면 이 파일을 고친 뒤 'oap init'을 다시 실행)"
  fi
  rm -f "$vars"
  [ "$rc" = 3 ] && warn "기존 파일과 다른 템플릿은 *.oap-new 로 저장했습니다. 비교 후 병합하거나 --force로 덮어쓰세요."

  trust_codex_project "$dir"
  say ""
  ok "하네스를 만들었습니다. 다음: oap merge-runner \"$dir\" → oap github \"$dir\" → oap orca \"$dir\""
}

# Mark the project folder as trusted for Codex so new sessions don't stop at the trust prompt.
trust_codex_project() {
  local cfg="$HOME/.codex/config.toml"
  [ -f "$cfg" ] || return 0
  if grep -Fq "[projects.\"$1\"]" "$cfg"; then ok "Codex 폴더 신뢰: 이미 등록됨"; return; fi
  info "Codex가 이 폴더를 신뢰하도록 ~/.codex/config.toml에 추가합니다 (백업 생성)"
  backup_file "$cfg"
  if [ "$OAP_DRY_RUN" != 1 ]; then
    printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$1" >> "$cfg"
  fi
}

cmd_merge_runner() {
  local dir="${1:-.}"
  dir="$(abs_path "$dir")"; require_project "$dir"
  local bin py; bin="$(cfg_get "$dir" MERGE_BIN)"; py="$(oap_python)"
  step "병합 실행기 설치 → $bin"
  local tmp; tmp="$(mktemp -t oap-merge)"
  "$py" -I - "$OAP_ROOT/merge/orca_merge.py" "$dir/$OAP_CONFIG_FILE" "$tmp" <<'PY'
import json, sys
src, cfg_path, out = sys.argv[1:4]
cfg = json.load(open(cfg_path, encoding="utf-8"))
config = {
    "repo": cfg["GITHUB_REPO"],
    "base": "main",
    "ci": cfg["CI_NAME"],
    "status_prefix": cfg["PROJECT_KEY"],
    "mark": cfg["REVIEW_MARK"],
    "branch_prefix": "orca/",
}
text = open(src, encoding="utf-8").read()
line = "CONFIG = None  # oap:config"
if line not in text:
    raise SystemExit("merge runner template is missing its config line")
text = text.replace(line, "CONFIG = " + json.dumps(config, ensure_ascii=False) + "  # oap:config")
text = text.replace("#!/usr/bin/env python3", "#!/usr/bin/python3 -I", 1)
open(out, "w", encoding="utf-8").write(text)
PY
  if [ -f "$bin" ] && cmp -s "$tmp" "$bin"; then ok "최신 상태"; rm -f "$tmp"; return; fi
  [ -w "$(dirname "$bin")" ] || die "$(dirname "$bin") 에 쓸 수 없습니다."
  run install -m 0755 "$tmp" "$bin"
  rm -f "$tmp"
  ok "마스터는 이 절대 경로만 호출합니다. 작업 브랜치의 코드는 GitHub 쓰기 권한으로 실행하지 않습니다."
}
