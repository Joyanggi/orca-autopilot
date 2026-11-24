# shellcheck shell=bash
# oap doctor — read-only health check of everything the harness relies on.

DOCTOR_FAIL=0
DOCTOR_WARN=0
NODE_MIN="22.13.0"
CODEX_RULES="$HOME/.codex/rules/orca-orchestration.rules"

_row() { # status name detail [fix]
  local mark color
  case "$1" in
    ok) mark="✔"; color="$C_GREEN" ;;
    warn) mark="!"; color="$C_YELLOW"; DOCTOR_WARN=$((DOCTOR_WARN + 1)) ;;
    fail) mark="✖"; color="$C_RED"; DOCTOR_FAIL=$((DOCTOR_FAIL + 1)) ;;
    *) mark="·"; color="$C_DIM" ;;
  esac
  # Pad by display width: Hangul and other non-ASCII characters take two columns.
  local chars ascii pad
  chars=${#2}; ascii=$(printf '%s' "$2" | LC_ALL=C tr -cd '\000-\177' | wc -c | tr -d ' ')
  pad=$((22 - ascii - 2 * (chars - ascii))); [ "$pad" -lt 1 ] && pad=1
  printf '  %s%s%s %s%*s%s\n' "$color" "$mark" "$C_RESET" "$2" "$pad" "" "$3"
  if [ -n "${4:-}" ] && [ "$1" != "ok" ]; then printf '    %s↳ %s%s\n' "$C_DIM" "$4" "$C_RESET"; fi
}

_ver() { "$@" 2>/dev/null | head -n1 | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n1; }

doctor_core() {
  step "맥과 기본 도구"
  _row ok "macOS" "$(sw_vers -productVersion 2>/dev/null) ($(uname -m))"
  if xcode-select -p >/dev/null 2>&1; then _row ok "Xcode CLT" "$(xcode-select -p)"
  else _row fail "Xcode CLT" "없음" "xcode-select --install"; fi
  if have brew; then _row ok "Homebrew" "$(_ver brew --version)"
  else _row fail "Homebrew" "없음" "oap setup (공식 설치 스크립트 실행)"; fi
  if have git; then _row ok "git" "$(_ver git --version)"; else _row fail "git" "없음" "brew install git"; fi
  if have jq; then _row ok "jq" "$(_ver jq --version)"; else _row warn "jq" "없음" "brew install jq"; fi
  local py; py="$(oap_python || true)"
  if [ -n "$py" ]; then _row ok "python3" "$(_ver "$py" --version) ($py)"; else _row fail "python3" "없음" "xcode-select --install"; fi
  if have node; then
    local nv; nv="$(_ver node -v)"
    if version_ge "$nv" "$NODE_MIN"; then _row ok "Node.js" "$nv"
    else _row fail "Node.js" "$nv (최소 $NODE_MIN)" "brew install node@24 && brew link --overwrite --force node@24"; fi
  else _row fail "Node.js" "없음" "brew install node@24"; fi

  step "GitHub"
  if have gh; then
    if gh auth status >/dev/null 2>&1; then
      _row ok "gh" "$(_ver gh --version), 로그인: $(gh api user --jq .login 2>/dev/null || echo '?')"
    else _row fail "gh 로그인" "로그인 안 됨" "gh auth login"; fi
  else _row fail "gh" "없음" "brew install gh"; fi

  step "에이전트"
  if have claude; then _row ok "Claude Code" "$(_ver claude --version)"
  else _row fail "Claude Code" "없음" "curl -fsSL https://claude.ai/install.sh | bash"; fi
  if have codex; then
    _row ok "Codex CLI" "$(_ver codex --version)"
    if codex login status >/dev/null 2>&1; then _row ok "Codex 로그인" "확인됨"
    else _row fail "Codex 로그인" "로그인 필요" "codex login"; fi
  else _row fail "Codex CLI" "없음" "brew install --cask codex"; fi

  step "Orca"
  if [ -d "/Applications/Orca.app" ]; then _row ok "Orca 앱" "/Applications/Orca.app"
  else _row fail "Orca 앱" "없음" "https://orca.dev 에서 설치 (brew의 'orca' cask는 다른 프로그램입니다)"; fi
  if have orca; then
    _row ok "orca CLI" "$(_ver orca --version) ($(command -v orca))"
    if orca status >/dev/null 2>&1; then _row ok "Orca 런타임" "응답함"
    else _row warn "Orca 런타임" "응답 없음" "orca open"; fi
    local skills; skills="$(orca skills installed 2>/dev/null || true)"
    if printf '%s' "$skills" | grep -q orchestration; then _row ok "Orca 스킬" "orchestration 설치됨"
    else _row fail "Orca 스킬" "orchestration 스킬 없음" "orca skills install --skill orca-cli --skill orchestration --skill orca-computer-use"; fi
    local hosts; hosts="$(orca host list 2>/dev/null | grep -Evc '^(local|$)' || true)"
    if [ "${hosts:-0}" -gt 0 ]; then
      _row warn "원격 호스트" "원격 Orca 서버가 ${hosts}개 등록됨" "맥 단독 개발이면 'oap gui'의 '새 프로젝트 기본 위치 = 이 컴퓨터'를 확인하세요"
    fi
  else _row fail "orca CLI" "없음" "Orca 앱 설정에서 CLI를 설치하세요"; fi

  if [ -f "$CODEX_RULES" ]; then
    if have codex && codex execpolicy check --rules "$CODEX_RULES" -- orca orchestration send --from t --type worker_done 2>/dev/null | grep -q allow; then
      _row ok "Codex 보고 규칙" "worker_done 전송 허용"
    else _row warn "Codex 보고 규칙" "파일은 있으나 allow 확인 실패" "oap setup"; fi
  else _row fail "Codex 보고 규칙" "$CODEX_RULES 없음" "oap setup"; fi
}

doctor_mobile() {
  step "모바일(iOS) — 선택"
  if [ -d /Applications/Xcode.app ]; then
    _row ok "Xcode" "$(_ver xcodebuild -version)"
    case "$(xcode-select -p 2>/dev/null)" in
      /Applications/Xcode.app/*) _row ok "xcode-select" "Xcode.app 사용" ;;
      *) _row warn "xcode-select" "$(xcode-select -p 2>/dev/null)" "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
    esac
  else _row warn "Xcode" "없음" "App Store에서 Xcode 설치 (oap setup --mobile이 App Store를 엽니다)"; fi
  if have pod; then _row ok "CocoaPods" "$(_ver pod --version)"; else _row warn "CocoaPods" "없음" "brew install cocoapods"; fi
  if have watchman; then _row ok "watchman" "$(_ver watchman --version)"; else _row warn "watchman" "없음 (권장)" "brew install watchman"; fi
  if have claude && claude mcp get mobile-mcp >/dev/null 2>&1; then _row ok "Mobile MCP (Claude)" "등록됨"
  else _row warn "Mobile MCP (Claude)" "미등록" "oap setup --mobile"; fi
  if have codex && codex mcp get mobile-mcp >/dev/null 2>&1; then _row ok "Mobile MCP (Codex)" "등록됨"
  else _row warn "Mobile MCP (Codex)" "미등록" "oap setup --mobile"; fi
  local free_gb; free_gb="$(df -g / 2>/dev/null | awk 'NR==2{print $4}')"
  if [ -n "$free_gb" ]; then
    if [ "$free_gb" -ge 20 ]; then _row ok "여유 공간" "${free_gb}GB"
    else _row warn "여유 공간" "${free_gb}GB (iOS 빌드엔 20GB 이상 권장)"; fi
  fi
}

cmd_doctor() {
  local no_exit=0 a
  for a in "$@"; do [ "$a" = "--no-exit" ] && no_exit=1; done
  DOCTOR_FAIL=0; DOCTOR_WARN=0
  say "${C_BOLD}oap doctor${C_RESET} — 읽기 전용 점검"
  doctor_core
  doctor_mobile
  say ""
  if [ "$DOCTOR_FAIL" -eq 0 ]; then ok "필수 항목 모두 통과 (경고 $DOCTOR_WARN건)"
  else err "필수 항목 ${DOCTOR_FAIL}건 실패, 경고 ${DOCTOR_WARN}건 — 'oap setup'으로 대부분 해결됩니다."; fi
  if [ "$no_exit" = 1 ]; then return 0; fi
  [ "$DOCTOR_FAIL" -eq 0 ]
}
