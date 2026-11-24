# shellcheck shell=bash
# oap setup — machine-wide dependencies. Every step is idempotent and skips what is already there.

MOBILE_MCP_PACKAGE="${MOBILE_MCP_PACKAGE:-@mobilenext/mobile-mcp@1.0.19}"
ORCA_SKILLS="orca-cli orchestration orca-computer-use"

setup_clt() {
  if xcode-select -p >/dev/null 2>&1; then ok "Xcode Command Line Tools"; return; fi
  warn "Xcode Command Line Tools가 없습니다. 설치 창이 뜨면 설치를 마친 뒤 'oap setup'을 다시 실행하세요."
  run xcode-select --install || true
  exit 1
}

setup_brew() {
  if have brew; then ok "Homebrew $(brew --version | head -n1 | awk '{print $2}')"; return; fi
  [ -x /opt/homebrew/bin/brew ] && { eval "$(/opt/homebrew/bin/brew shellenv)"; ok "Homebrew (PATH 추가)"; return; }
  warn "Homebrew가 없습니다. 공식 설치 스크립트는 관리자 암호를 직접 입력해야 합니다."
  if confirm "Homebrew 공식 설치 스크립트를 실행할까요?"; then
    run_remote_script https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    die "Homebrew 없이 계속할 수 없습니다. https://brew.sh 참고"
  fi
}

brew_ensure() { # brew_ensure <command> <formula> [--cask]
  if have "$1"; then ok "$1"; return; fi
  if [ "${3:-}" = "--cask" ]; then run brew install --cask "$2"; else run brew install "$2"; fi
}

setup_node() {
  if have node && version_ge "$(node -v | tr -d v)" "$NODE_MIN"; then ok "Node.js $(node -v)"; return; fi
  info "Node.js 24 LTS 설치 (Expo·최신 도구는 $NODE_MIN 이상 필요)"
  run brew install node@24
  run brew link --overwrite --force node@24 || warn "node@24 링크 실패 — PATH에 $(brew_prefix)/opt/node@24/bin 을 추가하세요."
}

setup_agents() {
  if have claude; then ok "Claude Code $(claude --version 2>/dev/null | head -n1)"
  else
    info "Claude Code 설치 (공식 설치 스크립트)"
    run_remote_script https://claude.ai/install.sh
  fi
  brew_ensure codex codex --cask
  if have codex && ! codex login status >/dev/null 2>&1; then
    warn "Codex 로그인이 필요합니다. 이 터미널에서 'codex login'을 실행하세요 (브라우저 로그인)."
  fi
  if have gh && ! gh auth status >/dev/null 2>&1; then
    warn "GitHub 로그인이 필요합니다. 'gh auth login'을 실행하세요."
  fi
}

setup_orca() {
  if [ ! -d /Applications/Orca.app ]; then
    warn "Orca 앱이 없습니다. 다운로드 페이지를 엽니다. 설치 후 앱 설정에서 orca CLI도 설치하세요."
    run open "https://orca.dev"
    return
  fi
  ok "Orca 앱"
  if ! have orca; then warn "orca CLI가 PATH에 없습니다. Orca 앱 설정에서 CLI를 설치한 뒤 다시 실행하세요."; return; fi
  local s args=()
  for s in $ORCA_SKILLS; do args+=(--skill "$s"); done
  info "Orca 번들 스킬 설치/갱신: $ORCA_SKILLS"
  run orca skills install "${args[@]}" || warn "스킬 설치 일부 실패 — 'orca skills install --force ...'로 다시 시도할 수 있습니다."
}

setup_codex_rules() {
  local src="$OAP_ROOT/config/codex/orca-orchestration.rules"
  mkdir -p "$HOME/.codex/rules"
  if [ -f "$CODEX_RULES" ] && cmp -s "$src" "$CODEX_RULES"; then ok "Codex 보고 규칙"; return; fi
  if [ -f "$CODEX_RULES" ]; then backup_file "$CODEX_RULES"; fi
  info "Codex 작업자가 승인 없이 worker_done/ask를 보낼 수 있게 규칙 설치"
  run cp "$src" "$CODEX_RULES"
  if have codex && [ "$OAP_DRY_RUN" != 1 ]; then
    codex execpolicy check --rules "$CODEX_RULES" -- orca orchestration send --from t --type worker_done | grep -q allow \
      && ok "규칙 확인: allow" || warn "규칙 확인 실패 — Codex 버전을 확인하세요."
  fi
}

setup_mobile() {
  step "모바일(iOS) 도구"
  if [ -d /Applications/Xcode.app ]; then ok "Xcode"
  else
    warn "Xcode가 없습니다. App Store를 엽니다. 설치 후 'oap setup --mobile'을 다시 실행하세요."
    run open "macappstore://apps.apple.com/app/id497799835"
  fi
  case "$(xcode-select -p 2>/dev/null)" in
    /Applications/Xcode.app/*) ;;
    *) [ -d /Applications/Xcode.app ] && warn "관리자 암호가 필요해 직접 실행하세요: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -license accept" ;;
  esac
  brew_ensure pod cocoapods
  brew_ensure watchman watchman
  if have claude; then
    if claude mcp get mobile-mcp >/dev/null 2>&1; then ok "Mobile MCP (Claude)"
    else run claude mcp add -s user mobile-mcp -- npx -y "$MOBILE_MCP_PACKAGE"; fi
  fi
  if have codex; then
    if codex mcp get mobile-mcp >/dev/null 2>&1; then ok "Mobile MCP (Codex)"
    else run codex mcp add mobile-mcp -- npx -y "$MOBILE_MCP_PACKAGE"; fi
  fi
  dim "  iPhone 실기기: USB 연결 → 신뢰 → 설정 > 개인정보 보호 및 보안 > 개발자 모드 켜기. 첫 실기기 빌드 때 마스터가 연결을 요청합니다."
}

cmd_setup() {
  local mobile=0 a
  for a in "$@"; do case "$a" in --mobile) mobile=1 ;; *) die "알 수 없는 옵션: $a" ;; esac; done
  say "${C_BOLD}oap setup${C_RESET} — 이미 있는 항목은 건너뜁니다$([ "$OAP_DRY_RUN" = 1 ] && echo ' (dry-run)')"
  step "1/5 기본 도구"
  setup_clt
  setup_brew
  brew_ensure git git
  brew_ensure gh gh
  brew_ensure jq jq
  setup_node
  step "2/5 에이전트 CLI"
  setup_agents
  step "3/5 Orca"
  setup_orca
  step "4/5 Codex 규칙"
  setup_codex_rules
  if [ "$mobile" = 1 ]; then setup_mobile; else dim "  (모바일 도구는 --mobile로 설치)"; fi
  step "5/5 Orca 앱 설정"
  say "  Orca 앱 화면에서만 바꿀 수 있는 설정이 있습니다. 'oap gui'로 목록과 자동 적용 프롬프트를 확인하세요."
}
