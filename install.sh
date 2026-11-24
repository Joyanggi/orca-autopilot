#!/usr/bin/env bash
# orca-autopilot installer: clones (or updates) the kit and links the `oap` command.
#   curl -fsSL https://raw.githubusercontent.com/Joyanggi/orca-autopilot/main/install.sh | bash
set -euo pipefail

REPO_URL="${OAP_REPO_URL:-https://github.com/Joyanggi/orca-autopilot.git}"
REF="${OAP_REF:-main}"
DEST="${OAP_HOME:-$HOME/.orca-autopilot}"

[ "$(uname -s)" = "Darwin" ] || { echo "orca-autopilot는 macOS 전용입니다." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git이 없습니다. 먼저 'xcode-select --install'을 실행하세요." >&2; exit 1; }

if [ -d "$DEST/.git" ]; then
  echo "→ 업데이트: $DEST"
  git -C "$DEST" fetch --quiet origin "$REF"
  git -C "$DEST" checkout --quiet "$REF"
  git -C "$DEST" merge --quiet --ff-only "origin/$REF"
else
  echo "→ 설치: $DEST"
  git clone --quiet --branch "$REF" "$REPO_URL" "$DEST"
fi

if command -v brew >/dev/null 2>&1 && [ -w "$(brew --prefix)/bin" ]; then
  BIN="$(brew --prefix)/bin"
else
  BIN="$HOME/.local/bin"; mkdir -p "$BIN"
  case ":$PATH:" in *":$BIN:"*) ;; *) echo "! PATH에 $BIN 을 추가하세요: echo 'export PATH=\"$BIN:\$PATH\"' >> ~/.zprofile" ;; esac
fi
ln -sf "$DEST/bin/oap" "$BIN/oap"
echo "✔ oap → $BIN/oap"
echo
echo "다음 단계:"
echo "  oap doctor"
echo "  oap setup            # 모바일(iOS)이면: oap setup --mobile"
echo "  oap all ~/orca/my-app --name '내 앱' --key myapp --preset expo"
