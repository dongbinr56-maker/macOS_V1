# AI Web Ops Monitor

`AI Web Ops Monitor`는 macOS 메뉴바에서 Codex, Claude, Cursor 웹 세션을 추적하는 운영용 앱입니다. 공식 API 없이 로그인된 웹 세션을 유지한 채 usage 페이지와 대시보드를 읽고, 결과를 `Overview` 화면과 `Pixel Office` 화면으로 보여줍니다.

## 핵심 기능

- macOS 메뉴바 앱
- Codex, Claude, Cursor 세션 추가 및 재로그인
- 세션별 독립 `WKWebsiteDataStore` 사용
- `Overview` 모드와 `Pixel Office` 모드 제공
- 세션 검색, 플랫폼 필터, 상태 필터, 인스펙터 UI
- 60초 주기 자동 새로고침, 최대 동시 2세션 새로고침
- 낮은 한도, 로그인 필요, 차단, stale, refresh 실패 알림
- 세션 영구 저장과 JSON 백업 복구
- GitHub Actions CI에서 `swift build`, `swift test`, `.app` 번들 빌드 검증

## 현재 동작 기준

### 사용량/상태 판정

- 자동 새로고침 주기: `60초`
- 낮은 한도 경고 기준: `20% 이하`
- idle 판정 기준: 최근 의미 있는 작업 신호 없음 + `10분` 이상 활동 없음
- stale 판정 기준: `15분` 이상 갱신 지연
- 새로고침 동시성 제한: `2`

세션 상태 우선순위는 아래 순서입니다.

1. `error`
2. `needsLogin`
3. `blocked`
4. `stale`
5. `quotaLow`
6. `responding`
7. `waiting`
8. `working`
9. `idle`

즉 오래된 제목이나 대기 중인 화면만으로는 `작업 중`으로 올리지 않고, 최근 명시적 작업 신호가 있을 때만 `working / responding / waiting`으로 분류합니다.

### Pixel Office 동작 (V2)

- `working`, `responding` 세션은 워크스테이션에 고정되고 작업 포즈를 표시합니다.
- `waiting` 세션은 과한 순회 대신 좌석 중심 정지 상태로 표시됩니다.
- `idle` 세션은 라운지에서 최소 유휴 동작만 유지합니다.
- `needsLogin`, `blocked`, `error`, `quotaLow`, `stale` 세션은 경고 도트 중심으로 표시됩니다.
- 상태 전환 시에만 제한적으로 이동하며, 평상시 과한 이동 연출은 줄였습니다.
- 이동 경로는 오피스 내부 안전 타일만 통과하도록 제한되어 벽 밖으로 벗어나지 않습니다.

세부 규칙은 [docs/PIXEL_OFFICE.md](docs/PIXEL_OFFICE.md)에 정리했습니다.

### 세션 저장 방식

- 기본 저장소는 `SwiftData`입니다.
- 저장 시 `UserDefaults` JSON 백업도 같이 유지합니다.
- 다음 실행에서 `SwiftData`가 비어 있으면 JSON 백업에서 세션을 복구합니다.
- 즉 앱 재실행 후 세션이 사라지지 않도록 이중 저장 경로를 사용합니다.

## 화면 구성

### Overview

- 플랫폼별 운영 카드(상태 우선 정렬)
- 핵심 quota 1~2개 + 최소 컨텍스트 중심 카드
- Primary CTA 1개 + `더보기` 메뉴 기반 액션 구조

### Pixel Office

- 픽셀 캐릭터 기반 오피스 장면
- 상단 요약 보드
- `All / Work / Alerts / Idle` 필터
- `Codex / Claude / Cursor` 플랫폼 필터
- 인스펙터에서 대화 제목, 프롬프트, 응답 상태, quota, 링크 액션 확인

## 요구 사항

- macOS 14 이상
- Xcode 16 이상 권장
- Swift 6 toolchain

## 실행

가장 간단한 앱 실행 방법:

```bash
open -na "$(./scripts/build_app.sh)"
```

개발 검증용 명령:

```bash
swift build
swift test
./scripts/build_app.sh
```

`swift run`은 개발 확인에는 쓸 수 있지만, 실제 메뉴바 앱 동작, 알림 권한, 앱 번들 기반 테스트는 `.app` 실행 쪽이 기준입니다.

## 프로젝트 구조

- `AIWebUsageMonitor.xcodeproj`: Xcode 앱 프로젝트
- `Package.swift`: Swift Package 설정
- `Sources/AIWebUsageMonitor`: 앱 소스
- `Tests/AIWebUsageMonitorTests`: 테스트
- `scripts/build_app.sh`: 릴리스 `.app` 번들 빌드 스크립트
- `.github/workflows/ci.yml`: CI
- `docs/`: 현재 동작 기준 문서

## 문서 맵

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): 앱 구조와 데이터 흐름
- [docs/PIXEL_OFFICE.md](docs/PIXEL_OFFICE.md): 픽셀 오피스 상태/배치/애니메이션 규칙
- [docs/OPERATIONS.md](docs/OPERATIONS.md): 실행, 테스트, CI, 운영 체크리스트
- [CONTRIBUTING.md](CONTRIBUTING.md): 개발/PR 가이드

## CI

GitHub Actions `CI` 워크플로는 `macos-15` 러너에서 아래를 검증합니다.

- `swift build`
- `swift test`
- `./scripts/build_app.sh`

## 자산 및 라이선스

- 픽셀 오피스 자산 일부는 `pixel-agents` 프로젝트의 MIT 자산을 사용합니다.
- 자산과 고지 파일은 `Sources/AIWebUsageMonitor/Resources/PixelOfficeAssets`에 포함되어 있습니다.

## 현재 제한 사항

- 웹 UI 텍스트나 DOM 구조가 바뀌면 `PlatformScraper.swift` 보정이 필요할 수 있습니다.
- 코드 서명과 notarization은 아직 포함하지 않았습니다.
- 서명되지 않은 앱은 Gatekeeper 경고가 발생할 수 있습니다.
