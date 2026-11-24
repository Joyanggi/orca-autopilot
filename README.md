# orca-autopilot

**맥 한 대에서 [Orca](https://orca.dev) + Claude Code + Codex 자동 오케스트레이션을 처음부터 끝까지 세팅하는 도구입니다.**

일을 한 줄 던지면 마스터(Claude)가 작업을 나눠 개발 작업자에게 맡기고, **Claude와 Codex가 서로의 결과를 보지 못한 채 독립 리뷰**한 뒤, 같은 최종 커밋에 두 `PASS`와 CI가 모이면 보호된 `main`에 **자동으로 squash 병합**합니다. 사람은 제품 방향·비용·개인정보·배포처럼 꼭 필요한 결정에만 불려옵니다.

```
사용자 ──/orchestrate──▶ 마스터(Claude Opus) ──▶ 개발 작업자(Claude Sonnet, 별도 worktree)
                                │                         │ worker_done
                                ▼                         ▼
                           Draft PR ◀──────────────── 마스터
                    ┌───────────┴───────────┐
              Codex 리뷰어            Claude 리뷰어      (읽기 전용 · 격리 · 병렬)
                    └──── <KEY>-REVIEW <SHA> PASS ────┘
                                ▼
          <key>-orca-merge (맥에 설치된 검증 실행기) → 리뷰 상태 게시
                                ▼
          GitHub 룰셋: <KEY> CI + review-claude + review-codex → 자동 병합
```

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/Joyanggi/orca-autopilot/main/install.sh | bash
```

또는 저장소를 클론한 뒤 `bin/oap`을 직접 실행해도 됩니다.

## 빠른 시작

```bash
oap doctor                     # 무엇이 빠졌는지 읽기 전용 점검
oap setup --mobile             # 의존성·에이전트·Orca 스킬·Codex 규칙 (--mobile: Xcode·CocoaPods·Mobile MCP)
oap all ~/orca/my-app --name "내 앱" --key myapp --preset expo
oap gui                        # Orca 앱 화면에서만 바꾸는 설정 목록 + 자동 적용 프롬프트
```

그다음 Orca에서 **내 앱 → 내 앱 마스터** 채팅을 열고 `/orchestrate <할 일>`을 보내면 됩니다.

## 명령

| 명령 | 하는 일 | 외부에 쓰는가 |
| --- | --- | --- |
| `oap doctor` | 맥·도구·로그인·Orca·Codex 규칙·모바일 도구 점검 | 아니요 |
| `oap setup [--mobile]` | Homebrew, git, gh, jq, Node 24, Claude Code, Codex, Orca 번들 스킬, `~/.codex/rules/orca-orchestration.rules`, (모바일) CocoaPods·watchman·Mobile MCP | 맥에만 설치 |
| `oap init <폴더>` | 하네스 생성: `AGENTS.md`, `CLAUDE.md`, `REVIEW.md`, `.claude/`(권한·마스터 절차·검증 스킬·리뷰어), `docs/`(PRD·요구사항·아키텍처·ADR·품질·작업 흐름), `.github/`(CI·PR·이슈 양식·제목 검사) | 아니요 |
| `oap merge-runner <폴더>` | 검토 완료 병합 실행기를 `$(brew --prefix)/bin/<key>-orca-merge`에 설치 | 맥에만 설치 |
| `oap github <폴더>` | 저장소 생성(선택), squash·자동 병합·브랜치 자동 삭제, `main` 룰셋(필수 검사 3개) | **예 — 단계마다 확인** |
| `oap orca <폴더>` | Orca에 저장소 등록, base ref, 마스터 worktree(`orca/coordinator`), 마스터 채팅 시작(선택) | Orca 로컬 |
| `oap gui` | CLI로 못 바꾸는 Orca 앱 설정 목록과 에이전트용 적용 프롬프트 | 아니요 |
| `oap all <폴더> …` | 위 단계를 순서대로 | 단계별 확인 |

모든 명령은 `--dry-run`(실행할 명령만 표시)과 `--yes`(확인 생략)를 지원합니다. 이미 된 단계는 건너뛰므로 여러 번 실행해도 안전합니다.

## 디렉터리 구성 (생성되는 저장소)

```
my-app/
├── AGENTS.md · CLAUDE.md · REVIEW.md      # Claude·Codex 공통 규칙, 리뷰 기준
├── orca-autopilot.json                    # 프로젝트 키, 저장소, 역할별 모델·노력치
├── .claude/
│   ├── settings.json                      # 마스터 모델, 허용·거부 권한(비밀 경로 읽기 거부)
│   ├── agents/reviewer.md                 # 읽기 전용 리뷰어
│   └── skills/{orchestrate,verify}/       # 마스터 절차, 검증 절차
├── docs/
│   ├── product/{PRD,REQUIREMENTS}.md
│   ├── architecture/ARCHITECTURE.md · decisions/
│   ├── quality/{TEST-STRATEGY,RISK-REGISTER}.md (+ expo: RELIABILITY-CHECKLIST)
│   └── development/{WORKFLOW,PR-ISSUE-GUIDE,KICKOFF}.md (+ expo: MOBILE-DEVICE)
└── .github/
    ├── workflows/<key>-ci.yml             # 필수 검사 '<KEY> CI'
    ├── scripts/check_git_titles.py        # 'feat: 한국어 요약' 제목 검사
    └── pull_request_template.md · ISSUE_TEMPLATE/
```

## 역할별 모델 바꾸기

`orca-autopilot.json`의 `MODEL_*`, `EFFORT_*`를 고치고 `oap init <폴더>`를 다시 실행하면 마스터 절차와 문서가 갱신됩니다. 기본값:

| 역할 | 에이전트 | 모델 | 노력치 |
| --- | --- | --- | --- |
| 마스터 | Claude | `claude-opus-5-5` | high |
| 개발 작업자 | Claude | `claude-sonnet-5-5` | medium |
| 독립 리뷰 A · 그래픽 자산 | Codex | `gpt-6.2-sol` | high |
| 독립 리뷰 B | Claude | `claude-sonnet-5-5` | high |

## 안전장치

- **사람이 꼭 개입하는 경우**만 마스터가 묻습니다: 제품 범위·인수 기준 약화, 비용, 계정·비밀값·권한 설정, 외부 공개·배포, 개인정보·운영 데이터, 법적 판단, 기기 연결, 3라운드 후에도 남은 중요 지적.
- **병합 실행기는 키트에서 설치**되고 작업 브랜치 코드는 GitHub 쓰기 권한으로 실행되지 않습니다. 실행기는 Orca에 남은 두 리뷰 보고가 같은 SHA의 `PASS`인지, 읽기 전용이었는지, 다른 공급자였는지 확인합니다.
- 하네스·판정 기준·DB 마이그레이션을 바꾼 PR은 **자동 병합을 거부**하고 사람에게 넘깁니다.
- 한쪽 공급자가 사용량 한도에 걸려도 **다른 공급자로 대신하지 않고** Orca 자동 재개를 기다립니다.
- 기존 파일은 덮어쓰지 않고 `*.oap-new`로 저장합니다(`--force`면 백업 후 교체). 사용자 설정 파일(`~/.codex/…`)을 바꾸기 전엔 `*.oap-bak.<시각>` 백업을 만듭니다.

## 알려진 한계

- Orca 앱의 일부 설정(기본 호스트, 권한 모드, 자동 재개, 자동 정리, 빠른 명령, 고정)은 CLI가 없어 `oap gui`의 목록이나 에이전트 프롬프트로 적용합니다.
- 개인 계정의 **비공개** 저장소는 GitHub Pro가 아니면 룰셋을 쓸 수 없습니다. 공개 저장소 또는 Pro/조직 저장소가 필요합니다.
- Orca 앱은 [orca.dev](https://orca.dev)에서 설치합니다. Homebrew의 `orca` cask는 다른 프로그램입니다.
- macOS 전용입니다.

## 개발

```bash
tests/run.sh      # 네트워크·Orca·GitHub에 쓰지 않는 오프라인 테스트
```

MIT License.
