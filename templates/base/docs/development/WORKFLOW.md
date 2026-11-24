# Orca 개발 흐름

**{{MASTER_NAME}}** Claude 채팅(`{{MODEL_MASTER}}`, `{{EFFORT_MASTER}}`)에 아이디어나 작업을 자연어로 맡깁니다. 마스터는 [오케스트레이션 절차](../../.claude/skills/orchestrate/SKILL.md)에 따라 개발 작업자(`{{MODEL_DEV}}`, `{{EFFORT_DEV}}`)에게 구현을 맡기고, 모든 변경을 Codex(`{{MODEL_CODEX}}`)와 Claude(`{{MODEL_REVIEW_CLAUDE}}`)가 서로의 결과를 보지 못하게 병렬로 리뷰합니다. 중요한 결정에만 사람의 승인을 요청합니다.

```
사용자 ──/orchestrate──▶ 마스터 ──Task──▶ 개발 작업자 (orca/<작업> worktree)
                          │                    │ worker_done (커밋, Verified:)
                          ▼                    ▼
                     Draft PR ◀──────────── 마스터
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
       Codex 리뷰어 (읽기 전용)   Claude 리뷰어 (읽기 전용)
              └─── {{REVIEW_MARK}} <SHA> PASS ───┘
                          ▼
     {{MERGE_BIN}}  → {{PROJECT_KEY}}/review-claude, {{PROJECT_KEY}}/review-codex 상태 게시
                          ▼
     GitHub 룰셋: {{CI_NAME}} + 두 리뷰 상태 + 최신 main  → squash 자동 병합
```

## 마스터 열기

Orca 사이드바에서 **{{PROJECT_NAME}} → {{MASTER_NAME}}**의 기존 Claude 채팅을 엽니다. 터미널에서는 아래 명령을 씁니다. Orca가 꺼져 있으면 먼저 `orca open`을 실행합니다.

```sh
orca worktree activate --environment local --worktree 'branch:{{MASTER_BRANCH}}'
```

마스터에 목표를 한 문장으로 보내면 됩니다. 양식은 [시작 요청문](KICKOFF.md)에 있습니다.

```text
/orchestrate 로그인 실패 시 원인별 안내 문구를 보여줘.
```

작성 규칙이나 마스터 절차가 `main`에 병합되면, 마스터 작업을 마치고 변경 사항이 없는 상태에서 해당 워크트리 터미널의 `git pull --ff-only origin main`으로 갱신합니다.

마스터 채팅을 처음부터 만들 때만 `oap orca .`을 사용하거나 아래 명령을 실행합니다.

```sh
orca agent launch --environment local --worktree 'branch:{{MASTER_BRANCH}}' \
  --agent claude --model {{MODEL_MASTER}} --effort {{EFFORT_MASTER}} --surface chat --focus \
  --prompt '{{MASTER_NAME}}로 준비해줘. CLAUDE.md와 AGENTS.md, /orchestrate 절차를 읽고 준비됐다고 알려줘. 작업 실행은 내 다음 요청부터 시작해줘.'
```

## 자동 병합의 안전장치

- `main`은 GitHub 룰셋으로 보호합니다: PR 필수, 강제 푸시·삭제 금지, 최신 `main` 반영 필수, 필수 검사 `{{CI_NAME}}`, `{{PROJECT_KEY}}/review-claude`, `{{PROJECT_KEY}}/review-codex`. 설정은 `oap github`이 만듭니다.
- 두 리뷰 상태는 GitHub 봇이 아니라 마스터가 맥에 설치된 `{{MERGE_BIN}}`으로 게시합니다. 실행기는 Orca에 보존된 두 `worker_done` 보고가 같은 SHA의 `PASS`인지, 읽기 전용이었는지, 서로 다른 공급자였는지 확인합니다.
- 실행기는 작업 브랜치가 아니라 `orca-autopilot` 키트에서 설치됩니다(`oap merge-runner`). 작업 브랜치의 코드는 GitHub 쓰기 권한으로 실행되지 않습니다.
- 하네스(`.claude/`, `.github/`, `AGENTS.md`, `CLAUDE.md`, `REVIEW.md`, `orca-autopilot.json`), 판정 기준(`docs/quality/`, 요구사항, ADR), DB 마이그레이션을 바꾼 PR은 실행기가 자동 병합을 거부합니다. 사람이 PR에서 확인하고 병합합니다.
- 이견 재검토를 등록하면 실행기가 해당 SHA에 `{{PROJECT_KEY}}/recheck-registered` 상태로 PR 링크와 Orca Run ID를 기록합니다. 등록과 병합 요청은 GitHub의 임시 `{{PROJECT_KEY}}-review-lock/<SHA>` 브랜치로 동시에 한 실행기만 처리합니다. 중단으로 잠금이 남으면, 같은 SHA를 처리하던 실행기가 모두 종료됐는지 확인한 뒤 저장소 소유자가 그 브랜치만 삭제합니다.

## 작업 정리

- GitHub는 PR이 병합되면 원격 작업 브랜치를 자동으로 삭제합니다(`oap github`).
- Orca의 워크스페이스 자동 정리를 켜면 병합된 작업 worktree와 로컬 브랜치가 정리됩니다. 마스터 worktree는 고정(pin)해 정리 대상에서 뺍니다. 설정 방법은 `oap gui`에 있습니다.

## Codex 작업자 설정 (저장소 밖, 맥마다 1회)

Codex 작업자는 샌드박스 때문에 `orca orchestration send`(worker_done 보고)가 막혀 승인을 요구할 수 있습니다. `oap setup`이 `~/.codex/rules/orca-orchestration.rules`에 `orca orchestration send`와 `orca orchestration ask`만 허용하는 규칙을 설치합니다. 확인은 `oap doctor`로 합니다.
