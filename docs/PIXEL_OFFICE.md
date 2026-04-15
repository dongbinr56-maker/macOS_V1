# Pixel Office

## 목적

`Pixel Office`는 usage 데이터를 단순 카드 대신 공간 기반 상태판으로 보여주기 위한 화면입니다. 현재 구현 기준은 `원본 자산 + Swift 렌더러 + 상태 기반 이동`입니다.

## 자산과 레이아웃 소스

- 픽셀 자산: `Sources/AIWebUsageMonitor/Resources/PixelOfficeAssets`
- 장면 해석: `PixelOfficeSourceLayout.swift`
- 상태별 장면 배치: `PixelOfficeSceneBuilder.swift`
- 실제 렌더링과 전환: `PixelOfficeView.swift`

장면은 source layout을 읽어 타일, 벽, 가구, 좌석 기준점을 만든 뒤 그 위에 캐릭터를 올립니다.

## 존 정의

- `desk`
  - 워크스테이션 책상 구역
- `lounge`
  - 소파와 라운지 주변 구역
- `alert`
  - 경고 동선 구역

## 상태별 배치 규칙

### 작업 중 세션

- `working`
- `responding`
- `waiting`

이 세 상태는 `desk` 존에 배치됩니다.

- `working`: 착석 + typing
- `responding`: 착석 + reading
- `waiting`: desk 주변 짧은 동선 순회

### 쉬는 세션

- `idle`

`lounge` 존에 배치됩니다. 라운지 좌석과 책장 주변을 짧게 오가며 쉬는 동작을 가집니다.

### 작업 불가 세션

- `needsLogin`
- `blocked`
- `error`

이 세 상태는 `경고 상태`로는 계속 유지되지만, 물리 배치는 `lounge` 존입니다. 즉 UI 상으로는 경고 세션이지만 캐릭터는 얌전히 소파에 앉아 있고, 별도 순회는 하지 않습니다.

### 주의/지연 세션

- `quotaLow`
- `stale`

이 두 상태는 `alert` 존을 사용합니다. 경고 동선에서 순회하며 상태 버블과 queue에도 포함됩니다.

## 이동 모델

캐릭터는 상태가 바뀔 때 단순 재배치되지 않습니다.

- `PixelOfficeMotionCoordinator`가 이전 프레임의 위치를 기억합니다.
- 상태/존이 바뀌면 `transitionPlan`을 생성합니다.
- transition이 끝날 때까지 실제 walking 포즈로 보간합니다.

즉 `idle -> working`이면 라운지에서 책상으로 걸어가고, `working -> idle`이면 다시 라운지로 돌아옵니다.

## 경계 제한

현재 경로는 내부 안전 타일만 통과하도록 고정되어 있습니다.

- desk aisle
- right doorway
- lounge center
- lounge bookcase
- utility center

이 안전 웨이포인트만 사용하므로 캐릭터가 벽 밖으로 빠졌다가 다시 들어오는 경로가 나오지 않도록 제한되어 있습니다.

## 상태 버블과 보드

경고 여부는 더 이상 `zone == alert`만으로 판정하지 않습니다. 현재 구현은 `taskState` 기준입니다.

- `alerts` 필터는 `needsLogin`, `quotaLow`, `blocked`, `stale`, `error`를 포함합니다.
- `alertQueue`도 상태 기준입니다.
- 따라서 `needsLogin / blocked / error`가 라운지에 앉아 있어도 경고 보드에서는 계속 보입니다.

## 수정 시 주의할 점

픽셀 오피스를 수정할 때는 아래를 같이 봐야 합니다.

1. `PixelOfficeSceneBuilder.swift`
2. `PixelOfficeView.swift`
3. `PixelOfficeSourceLayout.swift`
4. `Tests/AIWebUsageMonitorTests/PixelOfficeSceneBuilderTests.swift`

레이아웃만 바꾸고 테스트를 안 고치면 존 배치, 웨이포인트, 경고 좌석 규칙이 쉽게 깨집니다.
