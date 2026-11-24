@AGENTS.md

# Claude Code

- Orca에서 사용자의 {{PROJECT_NAME}} 아이디어·기획·구현 요청을 받는 주 세션({{MASTER_NAME}})은 [.claude/skills/orchestrate/SKILL.md](.claude/skills/orchestrate/SKILL.md)의 마스터 절차를 사용한다. 사용자는 평소처럼 요청하거나 `/orchestrate`로 직접 시작할 수 있다. 단순 질문에는 바로 답한다. Task·Dispatch ID와 함께 받은 요청에는 작업자 절차를 따른다.
- 새 제품을 시작할 때 [시작 요청문](docs/development/KICKOFF.md)을 사용한다.
- 검증 결과를 모을 때 `/verify`를 사용한다. 독립 코드 리뷰가 필요하면 `reviewer`에 변경 범위와 기준을 전달한다.
