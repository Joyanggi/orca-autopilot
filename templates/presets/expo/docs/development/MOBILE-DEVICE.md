# 실기기 준비 (iPhone)

`oap setup --mobile`이 Xcode 확인, CocoaPods·watchman 설치, Claude Code·Codex에 Mobile MCP 등록까지 진행합니다. 아래는 사람이 해야 하는 단계입니다.

1. **Xcode 경로와 라이선스** — `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -license accept`
2. **iPhone 연결** — USB로 연결하고 "이 컴퓨터 신뢰"를 누른 뒤, 설정 > 개인정보 보호 및 보안 > **개발자 모드**를 켭니다.
3. **서명** — Xcode > Settings > Accounts에 Apple ID를 추가합니다. 무료 Personal Team 서명은 7일마다 만료되므로, 만료 후에는 개발 빌드와 Mobile MCP용 앱을 다시 설치해야 합니다. 유료 Apple Developer Program 가입은 필수 개입 (b)입니다.
4. **확인** — `xcrun devicectl list devices`에 기기가 보이고, Claude Code에서 Mobile MCP로 기기 목록을 조회할 수 있으면 준비가 끝났습니다.

## 기기가 연결되지 않았을 때

- 작업자는 기기 없이 가능한 검사(타입·린트·테스트·`expo-doctor`·`expo export`)를 모두 실행하고, 기기가 필요한 항목은 PR에 **실기기 미확인**으로 남깁니다.
- 기기가 꼭 필요한 시점에만 마스터가 연결을 요청합니다. 연결을 기다리는 동안 관련 없는 작업은 계속합니다.
- Mobile MCP로 조작하기 전에는 기기의 **잠금을 해제**해 두세요. 잠긴 상태에서 화면 조작이 되는지는 기기와 버전에 따라 다르므로, 실패하면 잠금 해제를 요청하는 것을 기본으로 합니다.
- 시뮬레이터 검증이 필요해지면 Xcode에서 iOS 시뮬레이터 런타임을 설치합니다(수 GB). 디스크 여유를 먼저 확인합니다.
