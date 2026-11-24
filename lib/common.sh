# shellcheck shell=bash
# Shared helpers. Compatible with the bash 3.2 that ships with macOS.

# shellcheck disable=SC2034  # used by the files that source this one
OAP_VERSION="0.1.0"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

OAP_DRY_RUN="${OAP_DRY_RUN:-0}"
OAP_YES="${OAP_YES:-0}"

say()   { printf '%s\n' "$*"; }
info()  { printf '%s→%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '%s✔%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s✖%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }
step()  { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
dim()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

have() { command -v "$1" >/dev/null 2>&1; }

# run <cmd...>: print and execute, or only print in dry-run mode.
run() {
  printf '%s  $ %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2
  if [ "$OAP_DRY_RUN" = "1" ]; then return 0; fi
  "$@"
}

# run_remote_script <https-url>: official installers (Homebrew, Claude Code) only.
run_remote_script() {
  printf '%s  $ /bin/bash -c "$(curl -fsSL %s)"%s\n' "$C_DIM" "$1" "$C_RESET"
  if [ "$OAP_DRY_RUN" = "1" ]; then return 0; fi
  local script
  script="$(curl -fsSL "$1")" || die "다운로드 실패: $1"
  /bin/bash -c "$script"
}

# confirm "question" -> 0 when the user agrees. --yes answers for them.
confirm() {
  if [ "$OAP_YES" = "1" ]; then return 0; fi
  if [ "$OAP_DRY_RUN" = "1" ]; then dim "  (dry-run: '$1' 건너뜀)"; return 1; fi
  if [ ! -t 0 ]; then warn "비대화형 실행이라 '$1'을 건너뜁니다. --yes로 승인할 수 있습니다."; return 1; fi
  local answer
  printf '%s?%s %s [y/N] ' "$C_YELLOW" "$C_RESET" "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES|예|네) return 0 ;; *) return 1 ;; esac
}

# version_ge 24.1.0 22.13 -> true when $1 >= $2
version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" = "$2" ]
}

# backup_file <path>: keep a timestamped copy before we change a user file.
backup_file() {
  [ -e "$1" ] || return 0
  local dest
  dest="$1.oap-bak.$(date +%Y%m%d%H%M%S)"
  run cp -p "$1" "$dest"
}

oap_python() {
  if [ -x /usr/bin/python3 ]; then echo /usr/bin/python3; elif have python3; then command -v python3; else return 1; fi
}

brew_prefix() {
  if have brew; then brew --prefix; elif [ -d /opt/homebrew ]; then echo /opt/homebrew; else echo /usr/local; fi
}

require_macos() {
  [ "$(uname -s)" = "Darwin" ] || die "orca-autopilot는 macOS 전용입니다. (현재: $(uname -s))"
}
