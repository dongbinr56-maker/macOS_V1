# Architecture

## 개요

앱은 `메뉴바 셸 + 세션 저장소 + 웹 스크래핑 + 상태 파생 + 두 가지 UI(List / Pixel Office)` 구조입니다.

핵심 모듈은 아래와 같습니다.

- `AIWebUsageMonitorApp.swift`
  - 앱 엔트리포인트
  - SwiftUI 씬과 메뉴바 초기화
- `StatusBarController.swift`
  - 메뉴바 아이콘, 팝오버, 우클릭 메뉴
- `UsageMonitorViewModel.swift`
  - 세션 목록, 자동 새로고침, 상태 파생, 검색/필터용 데이터 공급
- `WebSessionManager.swift`
  - 세션별 `WKWebsiteDataStore` 등록
  - 로그인 윈도우와 백그라운드 웹뷰 수명 관리
- `PlatformScraper.swift`
  - Codex / Claude / Cursor 페이지에서 quota, reset, 상태 텍스트 파싱
- `AccountStore.swift`
  - `SwiftData` 영구 저장
  - `UserDefaults` JSON 백업/복구
- `UsageAlertManager.swift`
  - 낮은 한도, 로그인 필요, stale, 차단/실패 알림 발송 및 중복 억제
- `Views.swift`
  - 리스트 기반 운영 화면
- `PixelOfficeView.swift`
  - 픽셀 오피스 UI, 선택/호버, 인스펙터, 실제 이동 렌더링
- `PixelOfficeSceneBuilder.swift`
  - 상태별 존 배치, 좌석, 경로, 요약 보드, alert queue 생성
- `PixelOfficeSourceLayout.swift`
  - source layout 데이터와 타일/가구 메타 해석

## 데이터 흐름

1. 앱 시작 시 `UsageMonitorViewModel`이 `AccountStore`에서 세션을 읽습니다.
2. 각 세션은 `WebSessionManager`에 등록됩니다.
3. `UsageMonitorViewModel.start()`가 자동 새로고침 타이머를 시작합니다.
4. `refreshAll()` 또는 개별 `refresh(accountID:)`가 `WebSessionManager`를 통해 웹 페이지를 읽습니다.
5. `PlatformScraper`가 quota, reset, activity 신호, 에러/로그인 필요 상태를 추출합니다.
6. 결과는 `AccountStore`에 저장되고, 같은 시점에 JSON 백업도 갱신됩니다.
7. `UsageMonitorViewModel`이 `availability`, `activity`, `taskState`를 계산합니다.
8. `Views.swift`와 `PixelOfficeView.swift`가 같은 세션 모델을 서로 다른 형태로 렌더링합니다.

## 상태 파생 규칙

`taskState`는 단순 화면 텍스트가 아니라 여러 입력 신호를 우선순위로 합쳐 계산합니다.

- refresh 실패면 `error`
- 로그인 필요면 `needsLogin`
- quota blocked면 `blocked`
- activity stale이면 `stale`
- quota low면 `quotaLow`
- 최근 90초 이내 streaming 응답이면 `responding`
- 최근 90초 이내 user waiting이면 `waiting`
- 최근 명시적 작업 신호가 있으면 `working`
- 나머지는 `idle`

이 구조 때문에 오래된 대화 제목이나 예전 프롬프트만으로 `작업 중`으로 남지 않습니다.

## 저장 전략

기본 저장소는 `SwiftData`입니다. 다만 저장소 초기화 실패나 재실행 후 복구 문제를 완화하기 위해 `WebAccountSession` 배열을 `UserDefaults` JSON으로도 백업합니다.

- 정상 저장: `SwiftData` + JSON 백업 동시 저장
- 재실행 시 `SwiftData` 비어 있음: JSON 백업에서 복구
- 영구 저장소 초기화 실패: 메모리 저장소 폴백 가능

즉 문서 기준 현재 구현은 단일 저장 경로가 아니라 복구 가능한 이중 저장 구조입니다.

## Pixel Office 구성

픽셀 오피스는 정적 스크린샷 배경이 아니라 source layout 기반 장면 + 상태 기반 캐릭터 배치입니다.

- 장면 자산: `Resources/PixelOfficeAssets`
- 레이아웃 해석: `PixelOfficeSourceLayout.swift`
- 상태별 존/경로 생성: `PixelOfficeSceneBuilder.swift`
- 이전 위치에서 새 위치까지의 이동 보간: `PixelOfficeMotionCoordinator`

픽셀 오피스 세부 규칙은 [PIXEL_OFFICE.md](PIXEL_OFFICE.md)를 참고합니다.

## 테스트 전략

현재 자동 검증은 아래 세 층으로 나뉩니다.

- `PixelOfficeSceneBuilderTests`
  - 존 배치, queue 정렬, 경로 안전 타일, 작업 불가 세션 좌석 규칙
- `SessionSearchFilterTests`
  - 검색과 generic title 필터링
- `UsageMonitorIntegrationTests`
  - task state 판정, snapshot 반영, 백업 복구

## CI

`.github/workflows/ci.yml`은 `macos-15`에서 아래를 실행합니다.

- `swift build`
- `swift test`
- `./scripts/build_app.sh`
