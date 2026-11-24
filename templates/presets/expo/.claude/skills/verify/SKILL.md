---
name: verify
description: 변경의 인수 기준, 실행한 검사와 실기기 결과를 확인하고 증거를 정리한다.
disable-model-invocation: true
---

1. 변경 범위와 관련 요구사항을 확인하고 [테스트 전략](../../../docs/quality/TEST-STRATEGY.md), [실기기 체크리스트](../../../docs/quality/RELIABILITY-CHECKLIST.md)에서 필요한 검사를 고른다.
2. 저장소에 실제로 정의된 검사만 실행한다. 문서 변경만 있거나 앱이 초기화 전이면 `git diff --check`와 변경된 문서 링크를 확인하고, 앱 검사는 미실행으로 기록한다.
3. 기기 없이 가능한 검사(타입·린트·테스트·`npx expo-doctor`·`npx expo export --platform ios`)는 항상 실행한다.
4. 실기기 확인이 필요하면 `xcrun devicectl list devices`로 연결 상태를 확인한다. 연결돼 있으면 잠금 해제를 확인한 뒤 Mobile MCP로 흐름을 재현하고, 연결돼 있지 않으면 "실기기 미확인"과 필요한 확인 항목을 보고한다.
5. 검사별 명령, 결과, 환경(기기·iOS·빌드), 확인하지 못한 이유를 보고한다. 실패를 보고할 때 재현 조건과 다음에 확인할 지점을 함께 적는다.
