# {{PROJECT_NAME}}

{{PROJECT_NAME}}의 기획·설계 문서와 개발 규칙을 담은 저장소(`{{GITHUB_REPO}}`)입니다. Orca에서 Claude Code와 Codex로 기획, 구현, 검증, 리뷰, 병합을 자동으로 진행합니다.

## 시작하기

Orca에서 **Local Mac → {{PROJECT_NAME}} → {{MASTER_NAME}}**을 열고 `/orchestrate <하고 싶은 작업>`을 보냅니다. 처음이라면 [시작 요청문](docs/development/KICKOFF.md)을 붙여넣습니다. 마스터를 여는 명령과 자동 병합 흐름은 [개발 흐름](docs/development/WORKFLOW.md)에 있습니다.

## 문서와 개발 규칙

| 파일 | 용도 |
| --- | --- |
| [PRD](docs/product/PRD.md) · [요구사항](docs/product/REQUIREMENTS.md) | 어떤 문제를 풀고 무엇을 만들어야 하는지 |
| [아키텍처](docs/architecture/ARCHITECTURE.md) · [기술 결정 기록](docs/decisions/README.md) | 구조와 주요 선택의 이유 |
| [테스트 전략](docs/quality/TEST-STRATEGY.md) · [위험 목록](docs/quality/RISK-REGISTER.md) | 무엇을 검증하고 어떤 증거를 남길지 |
| [개발 흐름](docs/development/WORKFLOW.md) · [리뷰 기준](REVIEW.md) · [커밋·이슈·PR 작성 규칙](docs/development/PR-ISSUE-GUIDE.md) | Orca, Git worktree, 검토와 GitHub 작성 양식 |
| [AGENTS.md](AGENTS.md) · [CLAUDE.md](CLAUDE.md) | Claude Code와 Codex가 공유하는 저장소 규칙 |

## 현재 상태

하네스 초기화 단계입니다. 실행 명령과 검증 결과는 프로젝트를 만든 뒤 추가합니다.

<sub>이 하네스는 orca-autopilot {{OAP_VERSION}}으로 생성했습니다. 역할별 모델은 `orca-autopilot.json`에서 바꿉니다.</sub>
