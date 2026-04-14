# AI Web Ops Monitor

`AI Web Ops Monitor`는 macOS 메뉴바에서 Codex, Claude, Cursor 같은 웹 기반 AI 세션의 상태를 추적하는 앱입니다.

공식 API 없이 `WKWebView`와 계정별 `WKWebsiteDataStore`를 이용해 로그인 세션을 유지한 채 usage 페이지와 대시보드를 읽습니다. 메뉴바 팝오버에서는 두 가지 모드를 제공합니다.

- `Office`: 세션을 픽셀 캐릭터로 배치한 실시간 픽셀 오피스
- `List`: 사용량 카드와 상태를 확인하기 쉬운 운영형 리스트 화면

## 현재 지원 범위

- macOS 메뉴바 앱
- Codex, Claude, Cursor 웹 로그인 창 제공
- 세션별 독립 저장소 사용
- 1분 주기 자동 새로고침
- `5시간 사용 한도`, `주간 사용 한도` 카드 표시
- 한도 20% 이하 경고 강조 및 macOS 알림
- `5시간` 또는 `주간` 한도 중 하나라도 `0%`면 `현재 사용 불가` 표시
- 픽셀 오피스 시각화
- `Office / List` 화면 전환
- 메뉴바 오른쪽 클릭 빠른 액션
- 오피스 상태/플랫폼 필터
- 오피스 상단 경고/활성 세션 운영 보드
- 세션/프롬프트/대화 검색 및 검색 결과 새로고침
- 로그인 시 자동 실행 토글
- 설정 화면에서 세션 추가, 재로그인, 테스트 알림, 권한 상태 확인

## 요구 사항

- macOS 14 이상
- Xcode 16 이상 권장
- Swift 6 toolchain

## 프로젝트 구조

- Xcode 프로젝트: `AIWebUsageMonitor.xcodeproj`
- Swift Package: `Package.swift`
- 앱 소스: `Sources/AIWebUsageMonitor`
- 앱 번들 빌드 스크립트: `scripts/build_app.sh`

## 실행 방법

### Xcode에서 실행

1. `AIWebUsageMonitor.xcodeproj`를 엽니다.
2. Scheme를 `AIWebUsageMonitor`로 선택합니다.
3. `Run`을 누릅니다.

실행 후 Dock이 아니라 macOS 메뉴바에 상태 아이콘이 나타납니다.

### 터미널에서 실행

```bash
swift build
swift run
```

터미널 실행은 개발용 확인에 적합합니다. 로그인 시 자동 실행이나 알림 권한 등록은 실제 `.app` 번들 실행 쪽이 더 안정적입니다.
`swift run`으로 실행하면 메뉴바 UI와 세션 로직은 동작하지만, 시스템 알림 권한 요청과 테스트 알림 발송은 비활성화됩니다.

UI 디버그 창으로 메인 화면을 일반 윈도우에 띄우려면 아래 실행 플래그를 사용할 수 있습니다.

```bash
swift run AIWebUsageMonitor --debug-window
```

## .app 빌드

```bash
./scripts/build_app.sh
```

기본 빌드 산출물 경로:

```bash
.build/xcode-derived-data/Build/Products/Release/AIWebUsageMonitor.app
```

실행 예시:

```bash
open -na ".build/xcode-derived-data/Build/Products/Release/AIWebUsageMonitor.app"
```

## 사용 방법

### 1. 메뉴바 아이콘 클릭

앱은 메뉴바 전용 앱입니다. 상단 메뉴바 아이콘을 클릭하면 팝오버가 열립니다.

오른쪽 클릭 메뉴에서는 아래 빠른 동작을 바로 사용할 수 있습니다.

- `픽셀 오피스 열기`
- `리스트 보기`
- `전체 새로고침`
- `종료`

### 2. 세션 추가

팝오버 오른쪽 상단의 설정 아이콘을 누른 뒤 `세션 추가`를 선택하면 Codex 로그인 창이 열립니다. 이 창에서 직접 로그인하면 해당 세션이 앱에 저장됩니다.

### 3. 사용량 확인

메인 화면에서 아래 정보를 확인할 수 있습니다.

- 5시간 사용 한도
- 주간 사용 한도
- 현재 사용 가능 여부
- 작업중, 응답중, 대기중, 로그인 필요 같은 세션 상태
- 마지막 갱신 시각

### 4. 화면 모드

- `Office` 모드에서는 각 세션이 픽셀 캐릭터로 표시됩니다.
- `All`, `Work`, `Alerts`, `Idle` 필터로 세션 상태를 바로 분류할 수 있습니다.
- `Codex`, `Claude`, `Cursor` 플랫폼 필터로 오피스를 즉시 좁혀 볼 수 있습니다.
- 오피스 상단 운영 보드에서 경고 세션과 활성 세션을 한 번에 골라 바로 인스펙터로 넘길 수 있습니다.
- 상단 검색창에서 세션 이름, 프로필, 대화 제목, 프롬프트, quota 텍스트를 기준으로 바로 찾을 수 있습니다.
- `working`, `responding` 세션은 책상에 배치됩니다.
- `waiting`, `idle` 세션은 라운지 쪽으로 이동합니다.
- `quotaLow`, `blocked`, `needsLogin`, `error` 세션은 경고 구역으로 배치됩니다.
- 오피스 인스펙터에서는 대화 제목, 최신 프롬프트, 응답 상태, 핵심 quota, 원본 페이지 열기, 텍스트 복사를 함께 처리할 수 있습니다.
- `List` 모드에서는 플랫폼별 운영 카드와 한도 값을 자세히 볼 수 있습니다.
- `List` 카드에서도 대시보드 열기, 원본 페이지 열기, 새로고침, 재로그인, 텍스트 복사를 바로 실행할 수 있습니다.

### 5. 상태 표시 규칙

- 두 한도가 모두 남아 있으면 `현재 사용 가능`
- 한도 중 하나가 20% 이하이면 주의 상태
- 한도 중 하나라도 0%이면 `현재 사용 불가`
- 페이지는 열렸지만 카드 파싱이 실패하면 설정 화면에서 재로그인 또는 새로고침이 필요하다고 표시

## 픽셀 오피스

- 픽셀 캐릭터 시트와 가구 자산 일부는 `pixel-agents` 오픈소스 프로젝트의 MIT 라이선스 자산을 사용합니다.
- 포함된 자산과 고지 파일은 `Sources/AIWebUsageMonitor/Resources/PixelOfficeAssets`에 있습니다.
- 자세한 라이선스 문구는 `NOTICE_pixel_agents_MIT.txt`를 참고하세요.

## 알림 동작

- 1분마다 Codex 사용량을 자동으로 다시 읽습니다.
- `5시간 사용 한도` 또는 `주간 사용 한도`가 20% 이하가 되면 경고 알림을 보냅니다.
- 해당 한도가 `0%`가 되면 `현재 사용할 수 없습니다` 알림을 한 번 더 보냅니다.
- 같은 상태가 계속 유지되는 동안 반복 알림은 억제합니다.
- 설정 화면의 `테스트 알림`으로 알림 채널을 직접 확인할 수 있습니다.

## 세션 및 스크래핑 방식

- 각 계정은 `WKWebsiteDataStore` 기반의 독립 세션을 사용합니다.
- 로그인 창은 앱 내부 `WKWebView`로 열립니다.
- 백그라운드 웹뷰가 각 플랫폼 usage 페이지를 열고 DOM 카드에서 `5시간 사용 한도`, `주간 사용 한도`, `남은 크레딧` 같은 정보를 읽습니다.
- 기본 대상 URL은 아래입니다.

```text
https://chatgpt.com/codex/settings/usage
```

## 공유 시 안내할 점

- 메뉴바 앱이라 Dock 아이콘이 기본으로 보이지 않습니다.
- 처음 실행 시 macOS에서 알림 권한을 요청할 수 있습니다.
- 웹 UI 구조가 바뀌면 스크래퍼 보정이 필요할 수 있습니다.
- 현재 빌드는 배포용 코드 서명과 notarization이 포함되지 않습니다.
- 서명되지 않은 앱은 Gatekeeper 경고가 발생할 수 있습니다.

## 주요 소스 파일

- `Sources/AIWebUsageMonitor/AIWebUsageMonitorApp.swift`
- `Sources/AIWebUsageMonitor/StatusBarController.swift`
- `Sources/AIWebUsageMonitor/UsageMonitorViewModel.swift`
- `Sources/AIWebUsageMonitor/Views.swift`
- `Sources/AIWebUsageMonitor/PixelOfficeView.swift`
- `Sources/AIWebUsageMonitor/PixelOfficeSceneBuilder.swift`
- `Sources/AIWebUsageMonitor/PixelOfficeAssets.swift`
- `Sources/AIWebUsageMonitor/WebSessionManager.swift`
- `Sources/AIWebUsageMonitor/PlatformScraper.swift`

## 검증 명령

```bash
swift build
swift test
./scripts/build_app.sh
```

## 기여

- 개발/기여 가이드는 `CONTRIBUTING.md`를 참고하세요.
- 버그 제보와 기능 제안은 `.github/ISSUE_TEMPLATE` 템플릿 기준으로 정리되어 있습니다.
- PR 제출 시 `.github/pull_request_template.md` 체크리스트를 사용합니다.

## 라이선스

- 이 저장소 기본 라이선스는 `MIT`입니다.
- 픽셀 오피스 자산 일부도 별도 MIT 고지와 함께 포함되어 있습니다.

## 현재 제한 사항

- Codex 웹 페이지의 DOM이나 텍스트 구조가 바뀌면 파서 보정이 필요할 수 있습니다.
- 앱 아이콘 리소스, 코드 서명, notarization은 아직 포함되지 않습니다.
- 시스템 알림 설정 목록에 안정적으로 노출되려면 실제 앱 번들 실행과 권한 허용이 필요합니다.
