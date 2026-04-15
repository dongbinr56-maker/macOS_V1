# Operations

## 요구 사항

- macOS 14 이상
- Xcode 16 이상 권장
- Swift 6 toolchain

## 실행

권장 실행 명령:

```bash
open -na "$(./scripts/build_app.sh)"
```

이 명령은 `.app` 번들을 빌드한 뒤 바로 실행합니다. 메뉴바 앱, 알림 권한, 실제 번들 기반 동작 확인은 이 경로를 기준으로 봅니다.

## 개발 검증

```bash
swift build
swift test
./scripts/build_app.sh
```

권장 순서는 아래와 같습니다.

1. `swift build`
2. `swift test`
3. `./scripts/build_app.sh`

UI나 자산 변경이 있으면 실제 `.app` 실행까지 확인하는 것이 좋습니다.

## CI

GitHub Actions 워크플로:

- 파일: `.github/workflows/ci.yml`
- 러너: `macos-15`
- 단계:
  - `swift build`
  - `swift test`
  - `./scripts/build_app.sh`

## 운영 체크리스트

### 세션/로그인

- 새 세션 추가 후 실제로 로그인 창이 열리는지 확인
- 재로그인 후 해당 세션 refresh가 성공하는지 확인
- 앱 재실행 후 세션이 유지되는지 확인

### 사용량

- quota 카드가 정상 파싱되는지 확인
- low quota 경고가 20% 이하에서만 뜨는지 확인
- blocked 상태가 0% 또는 차단 상태에서만 뜨는지 확인

### Pixel Office

- `working/responding/waiting`가 desk 구역으로 가는지 확인
- `idle`이 라운지로 가는지 확인
- `needsLogin/blocked/error`가 라운지 소파에 앉아 있는지 확인
- `quotaLow/stale`가 alert 동선을 도는지 확인
- 상태 전환 시 순간이동 대신 walking transition이 보이는지 확인
- 이동 경로가 벽 밖으로 나가지 않는지 확인

## 문제 대응

### 앱 재실행 후 세션이 사라지는 경우

현재 구현은 `SwiftData + UserDefaults JSON 백업` 구조입니다. 이 문제가 다시 보이면 `AccountStore.swift`의 저장/복구 경로를 먼저 확인합니다.

### 특정 플랫폼이 갑자기 파싱되지 않는 경우

`PlatformScraper.swift`의 selector, 텍스트 힌트, fallback 경로를 확인합니다. 웹 UI가 바뀌면 스크래퍼 보정이 필요할 수 있습니다.

### 경고가 이상하게 남는 경우

`UsageAlertManager.swift`와 `UsageMonitorViewModel.swift`의 상태 파생 순서를 같이 확인합니다. `taskState`가 바뀌어도 alert dedupe key가 남아 있을 수 있습니다.

### Pixel Office가 부자연스러운 경우

다음 네 파일을 같이 봅니다.

- `PixelOfficeSceneBuilder.swift`
- `PixelOfficeView.swift`
- `PixelOfficeSourceLayout.swift`
- `Tests/AIWebUsageMonitorTests/PixelOfficeSceneBuilderTests.swift`
