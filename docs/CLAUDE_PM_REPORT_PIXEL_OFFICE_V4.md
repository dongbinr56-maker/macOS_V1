# AI Web Ops Monitor Pixel Office V4 작업 보고서 (Claude/PM 전달용)

## 1) 문서 목적
- 본 문서는 `Pixel Office` 기능 고도화(V4) 관련 작업 내역을 PM 관점으로 정리한 보고서입니다.
- 전달 대상은 클로드 모델(후속 구현/검토 담당)이며, 작업 배경/의사결정/구현 상세/검증 결과/리스크/후속 계획을 포함합니다.

## 2) 범위 및 전제
- 범위: `Pixel Office` 기능 전용 고도화 + 연관 UI 텍스트/카드 보강
- 제외: Pixel Office 외 신규 기능 대규모 확장(백엔드 구조 변경, 데이터 모델 대수술 등)
- 전제: 사용자 요구사항은 "Pixel Office는 시각적 핵심 경험이므로 어설프면 안 됨"이며, 스타듀밸리급 체감 품질을 목표로 함

## 3) 최근 컨텍스트(브랜치 히스토리 기준)
- 주요 기준 커밋(최근):
  - `6a93653`: V3 안정화/보강 완료
  - `cbb58c6`: Pixel Office pose/테스트 보강
  - `867e7ab`: V3 핵심 기능(히스토리/액션보드/상태 안정화) 반영
  - `43fd9d5`: 로컬 로그 기반 상태 신호 통합
- 현재 작업은 위 기반 위에서 V4 시각 고도화 및 UX 디테일 강화로 진행됨.

## 4) 이번 작업 요약 (실행 순서)

### 4-1. 사용량 카드 보강 (Codex 5시간 초기화 시각)
- 사용자 요청: "코덱스 모델 5시간 사용량이 언제 초기화되는지 사용량 영역에 표시"
- 조치:
  - `QuotaMetricCardView`에서 초기화 문구를 단순 표시에서 의도형 문구로 변경
  - `5시간` 라벨일 때:
    - 값 존재: `5시간 초기화: ...`
    - 값 부재: `5시간 초기화 시각 수집 중`
  - 일반 라벨: `초기화: ...`
- 변경 파일:
  - `Sources/AIWebUsageMonitor/Views.swift`

### 4-2. Pixel Office V4 1차: 시각 분위기/용어/미션 톤 정비
- 목표: "첫인상 품질"을 즉시 끌어올리는 기반 연출 및 한국어 톤 통일
- 조치:
  - 시간대 기반 분위기 시스템(`새벽/낮/노을/밤`) 도입
  - 장면 오버레이/강조 색상/상태 문구를 시간대와 운영 상태(경고/활성)에 연동
  - 야간 반딧불 효과 추가(상황형 몰입 연출)
  - 미션 보드 카피 개선:
    - `즉시 조치` -> `긴급 요청`
    - `활성 작업` -> `진행 중 퀘스트`
  - 필터 한글화:
    - `All/Work/Alerts/Idle` -> `전체/작업중/주의/휴식`
- 변경 파일:
  - `Sources/AIWebUsageMonitor/PixelOfficeView.swift`
  - `Sources/AIWebUsageMonitor/PixelOfficeSceneBuilder.swift`

### 4-3. Pixel Office V4 2차: 연출 프로필/브리핑/레전드
- 목표: 예쁨 + 운영 가독성 동시 확보
- 조치:
  - 렌더 프로필 도입:
    - `집중`(저연출), `균형`, `시네마`(고연출)
  - 프로필별 프레임/효과 밀도 조절:
    - 타임라인 간격, 야간 이펙트 밀도 차등
  - `상황 브리핑` 패널 추가:
    - 경고/활성 세션 우선 요약, 특이사항 없을 때 안정 상태 메시지 노출
  - 상태 점 색상 레전드 추가:
    - 작업/대기/주의/오류를 즉시 해석 가능하도록 명시
- 변경 파일:
  - `Sources/AIWebUsageMonitor/PixelOfficeView.swift`

### 4-4. Pixel Office V4 3차: 시네마 카메라/경고 조명/역할 아이덴티티
- 목표: "눈이 즐거운 경험"을 제품급으로 완성
- 조치:
  - 선택 캐릭터 중심 카메라 트랜스폼(줌/팬) 도입
    - `균형/시네마` 모드에서 동작, `집중` 모드는 가독성 우선
  - 경고 상태 존재 시 장면 경고 조명 펄스 오버레이 추가
  - 시네마 모드 전용 `dust` 레이어 추가(공간감/깊이감)
  - 선택 캐릭터 발광 링 추가(시선 유도)
  - 캐릭터 태그 역할 배지 추가:
    - Codex=`OPS`, Claude=`R&D`, Cursor=`BUILD`
  - 태그 정보밀도 향상(최신 힌트 1줄)
- 변경 파일:
  - `Sources/AIWebUsageMonitor/PixelOfficeView.swift`

## 5) 파일별 변경 상세

### `Sources/AIWebUsageMonitor/Views.swift`
- `QuotaMetricCardView` 내부:
  - `resetDescription` 계산 프로퍼티 추가
  - `isFiveHourQuota` 판별 로직 추가
  - 5시간 한도 초기화 시각 안내 문구 강화

### `Sources/AIWebUsageMonitor/PixelOfficeSceneBuilder.swift`
- 필터 제목 지역화:
  - `PixelOfficeAgentVisibilityFilter.title`
  - `PixelOfficePlatformFilter.title`

### `Sources/AIWebUsageMonitor/PixelOfficeView.swift`
- 신규 타입/구조 추가:
  - `PixelOfficeAmbience`
  - `PixelOfficeRenderProfile`
  - `PixelOfficeBriefingItem`
  - `PixelOfficeBriefingPanel`
  - `PixelOfficeStatusLegend`
  - `PixelOfficeSceneHUD`
  - `PixelOfficeAlertLighting`
  - `PixelOfficeNightFireflies`
  - `PixelOfficeCinematicDust`
- 기존 컴포넌트 확장:
  - `PixelOfficeView`: 렌더 프로필 AppStorage/브리핑 계산/상위 전달
  - `PixelOfficeCommandDeck`: 연출 프로필 필터, 브리핑/레전드 영역
  - `PixelOfficeSceneCard`: HUD 오버레이 + 품질 점수 계산
  - `PixelOfficeScene`: 카메라 스케일/오프셋 기반 포커스 추적
  - `PixelOfficeBackdrop`: 시간대/프로필 기반 합성 레이어
  - `PixelOfficeAgentView`/`PixelOfficeAgentTag`: 선택 하이라이트, 역할 배지, 힌트 라인

## 6) 검증 결과
- 반복 검증 커맨드: `swift test`
- 결과: 전 구간 **30 tests passed / 0 failed** 유지
- 확인 포인트:
  - PixelOffice 관련 테스트 회귀 없음
  - 기존 V3 안정성 테스트도 모두 통과

## 7) 현재 워킹트리 상태
- 수정 파일(미커밋):
  - `Sources/AIWebUsageMonitor/PixelOfficeSceneBuilder.swift`
  - `Sources/AIWebUsageMonitor/PixelOfficeView.swift`
  - `Sources/AIWebUsageMonitor/Views.swift`
- diff 요약:
  - `PixelOfficeView.swift`: 대규모 고도화 (`+584` 라인 수준)
  - `PixelOfficeSceneBuilder.swift`: 지역화 중심 소규모 수정
  - `Views.swift`: 5시간 초기화 안내 문구 강화

## 8) 리스크 및 보완 포인트
- 리스크:
  - 시네마 모드에서 환경에 따라 시각 효과가 과하게 느껴질 수 있음
  - 카메라 포커스 이동에 민감한 사용자는 어지러움을 느낄 수 있음
- 완화:
  - `집중` 모드를 통해 저연출 선택 가능
  - 연출 강도는 프로필로 제어 가능하도록 설계됨

## 9) 클로드 모델에게 요청하는 후속 작업 (우선순위)
1. **시각 QA 루프 강화**
   - 실제 사용자 시나리오(경고 발생/선택 전환/야간 진입) 스냅샷 검토
   - 과연출 구간(밝기/펄스/먼지 밀도) 미세 조정
2. **성능 프로파일링**
   - 시네마 모드에서 CPU/GPU 사용량 비교 측정(집중/균형/시네마)
   - 저사양 환경 대비 디그레이드 정책 문서화
3. **역할 시스템 확장**
   - `OPS/R&D/BUILD`를 단순 배지에서 행동/애니메이션 차별화로 확장
   - 역할별 이벤트 피드백 설계(예: 경고 시 OPS 우선 강조)

## 10) PM 관점 결론
- 본 작업은 Pixel Office를 "상태 나열"에서 "몰입형 운영 공간"으로 전환하는 방향으로 진행됨.
- 핵심은 단순 화려함이 아니라, **시각적 몰입 + 운영 가독성 + 모드별 제어 가능성**의 균형을 맞춘 구조화된 업그레이드임.
- 현재 기준으로도 체감 품질은 유의미하게 상승했으며, 다음 단계는 성능/QA 기반의 정밀 튜닝이 핵심임.
