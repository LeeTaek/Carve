# Testing Rules (Carve)

## Goal
- 운영 앱(배포) 품질을 지키기 위해 핵심 로직을 자동화된 테스트로 보호한다.
- 스터디 목적을 위해, 테스트를 “나중에”가 아니라 Feature 설계 과정에 함께 포함한다.
- Domain(SwiftData 저장 · 마이그레이션)뿐 아니라 Feature(Reducer)와 네비게이션(AppCoordinatorFeature)까지 Swift Testing + TestStore 로 커버한다.

## Current state
- 새 시험은 Swift Testing + TCA TestStore 로 쓴다(옛 XCTest 는 Domain `DrawingDatabaseTest` 하나). Domain · 세 Feature · UIComponents · CarveToolkit 에 단위 시험 타깃(`<모듈>Test`)이 있다(ClientInterfaces · Resources 는 없다).
- 단위 시험은 호스트 앱 없이 돈다. App 코디네이터(Feature 간 네비게이션) 시험은 호스트 없는 App 단위 시험 타깃 `CarveAppTest` 에 둔다 — 앱 타깃에 의존하지 않고 코디네이터 소스를 함께 컴파일한다.
- 회귀 기준선은 `docs/regression-baseline.md` 한 곳에 둔다. 통과 수가 줄면 회귀다.

## Testing layers
### 1) Domain unit tests
- 순수 로직/정책/유즈케이스를 검증한다.
- 외부 시스템(SwiftData/PencilKit/파일 I/O)은 직접 다루지 않거나 최소 boundary로만 검증한다.

### 2) Persistence tests (SwiftData)
- SwiftData 스키마/마이그레이션/저장·조회 규칙을 검증한다.
- 테스트는 가능한 한 임시 컨테이너/파일 URL 또는 in-memory 설정으로 독립적으로 수행한다.

### 3) Feature reducer tests (TCA)
- Reducer의 상태 변화와 Effect 트리거를 검증한다.
- 의존성은 Dependencies로 주입하고, 테스트에서는 mock/in-memory 구현으로 치환한다.

## Preferred tools
- 기본 테스트 프레임워크: Testing
- Feature(Reducer) 테스트: TCA TestStore + Testing
- 의존성 주입: Dependencies (withDependencies로 주입/오버라이드)

## Naming & documentation
- 테스트 함수명은 “시나리오-기대결과”가 드러나게 작성한다.
- 변수명은 2글자 이상을 기본으로 한다.
- Arrange/Act/Assert(Given/When/Then) 블록을 분리하고, 중요한 의도는 1줄 주석으로 남긴다.

## SwiftData testing guideline
- 테스트마다 고유한 ModelConfiguration(url:) 또는 in-memory 설정으로 상호 간섭을 차단한다.
- @Model 인스턴스를 만드는 시험은 컨테이너부터 만든다 — iOS 17 에서만 trap 한다(swiftdata.md 「iOS 17」).
- 마이그레이션 테스트는 다음 구조를 따른다.
  1) V1 컨테이너 생성 → 데이터 저장
  2) 동일 URL로 최신 컨테이너 생성 + migrationPlan 적용
  3) 최신 컨텍스트 fetch → 결과 일치 검증
- teardown(삭제/파일 정리)은 테스트 안정성을 위해 반드시 수행한다.

## Feature reducer testing guideline
- State 변화: Action 입력에 따른 상태 변경
- Effect 트리거: 특정 Action이 dependency 호출을 발생시키는지
- Cancellation: debounce/저장 작업이 취소/대체되는지(필요한 경우)
- State 가 Equatable 이 아니면 시험 타깃 안에서만 수기 `==`(case 와 핵심 필드)를 붙이고 `exhaustivity = .off` 로 본다 — 본보기 `Feature/ChartFeature/Tests/ChartTestSupport.swift`.

## 현재 시각과 기다림 (리듀서)
- 규칙: 리듀서의 현재 시각은 `@Dependency(\.date) var date` 의 `date.now`, 기다림은 `@Dependency(\.continuousClock) var clock` 의 `try await clock.sleep(for:)` 다.
  `Date()` · `Date.now` · `Task.sleep` 을 새로 쓰지 않는다. 달력은 `Calendar.current` 를 그대로 쓴다(의존성으로 바꾸지 않는다).
- 이유: 직접 읽으면 시험이 실제 시각 · 실제 시간에 묶인다 — 시각을 고정할 수 없고, 기다림이 든 효과는 실제로 기다리거나 실행마다 결과가 달라진다.
- 시험: `$0.date = .constant(<고정 시각>)` · `$0.continuousClock = TestClock()` 을 넣고 `await clock.advance(by:)` 로 시간을 진행한다. 기다림 길이가 시험과 무관하면 `ImmediateClock()`.
- 본보기: 제품 `CarveDetailFeature.swift`(`date` · `clock`), 시험 `Feature/ChartFeature/Tests/ChartTestSupport.swift` 의 `ChartTestTime.now` · `fixedTimeDependencies`.
- 기계 검사: `reducer_no_direct_time`(리듀서 파일의 `Date()` · `Date.now` · `Task.sleep`)
- 이행 중 예외(늘리지 않는다): ChartFeature 의 State 기본값 · 계산 프로퍼티의 `Date()`(`DrawingChartFeature` · `DailyRecordChartFeature` · `DrawingWeeklySummaryFeature`),
  N-Canvas `CanvasFeature` 의 `Date.now`. 이 경로를 검증하는 시험만 `liveTimeDependencies`(ChartTestSupport)를 쓴다.

## 새 의존성의 testValue — 공유 SwiftData actor 금지
- 규칙: 새 저장소 · 클라이언트 의존성의 `testValue` 는 저장소를 건드리지 않는 스텁(빈 구현)으로 둔다. `createSwiftDataActor.testValue`(공유 테스트 actor)나 그것을 쓰는 SwiftData 구현을 기본값으로 두지 않는다.
  그 의존성을 확인하는 시험이 스파이나 자기만의 인메모리 컨테이너를 주입한다.
- 이유: 테스트 actor 는 프로세스에 하나이고 처음 깨운 시험의 컨테이너에 묶인다. 장 열기 · 화면 진입 경로에서 새 의존성이 그 actor 를 먼저 깨우면,
  검증용 컨테이너를 따로 여는 무관한 시험(`DrawingErasePersistenceTesting` 등)이 다른 저장소를 보고 실패한다. 좁은 범위 실행은 통과하고 전체 회귀에서만 드러난다.
- 본보기: Domain `FavoriteVerseRepository` 의 `EmptyFavoriteVerseRepository` · `DrawingActivityRepository` 의 `EmptyDrawingActivityRepository`.
  `drawingRepository` 의 testValue 는 공유 actor 를 쓰는 옛 구성이다 — 새 의존성은 따라 하지 않는다.
- 확인: 새 의존성을 붙이면 좁은 범위만 보지 말고 전체 회귀(`Carve-Workspace`)까지 돌린다.
- 기계 검사: 없음(리뷰).

## TestStore — 받은 액션을 소비해야 state 가 바뀐다
- 규칙: 비망라(`exhaustivity = .off`) TestStore 에서 효과가 보낸 액션은 리듀서를 돌리지만 `store.state` 에는 `receive` · `skipReceivedActions` 로 소비해야 반영된다.
  도착 순서를 정하지 않는 흐름은 `await store.finish()` 다음 `await store.skipReceivedActions(strict: false)` 로 마지막 상태에 맞춘 뒤 `store.state` 를 검사한다. 순서를 아는 흐름은 `receive` 로 소비한다.
- 같은 원리: 비망라 TestStore 의 `send` 는 그때까지 받아 놓고 확인하지 않은 액션을 건너뛴다. 효과가 이미 보낸 액션을 `send` 뒤에 `receive` 하면 기다리다 실패하므로, 실제 흐름 순서대로 먼저 `receive` 하고 `send` 한다.
- 이유: `TestStore.state` 는 send 와 받은 액션 소비 때만 갱신된다(TCA `TestStore.swift` 의 `_reduce` · `_skipReceivedActions`). `finish()` 뒤 바로 읽으면 옛 상태가 보여, 분기는 돌았는데 기대가 실패하는 헛실패가 난다.
- 본보기: `Feature/CarveFeature/Tests/ChapterCanvasStoreGenerationTesting.swift` 의 `settle(_:)`.
- 기계 검사: 없음.

## Navigation testing guideline (AppCoordinator)
- child 이벤트 입력 → root 전환이 발생하는지
- child 이벤트 입력 → path.append / path.removeLast가 올바른지
- pop 후 특정 화면으로 이동시키는 send가 필요한 경우 함께 검증

## Geometry related tests (추천)
- 좌표 영역 · captureRect 계산(`ChapterLayoutBuilder`)
- 획 → 절 소유권 판정 · 승계(`StrokeOwnershipResolver`)
- reflow(밑줄 band 이동 · 축소) 계산(`LineBandReflow`)

## Minimum bar
- 새 Feature 추가/리팩터링 시 Reducer 테스트 1개 이상
- SwiftData 스키마 변경 시 마이그레이션(또는 저장/조회) 테스트 1개 이상
- AppCoordinator path 목적지 추가 시 네비게이션 테스트 1개 이상

## Test writing checklist
- [ ] 테스트는 독립적으로 실행 가능해야 한다(순서 의존 금지)
- [ ] 외부 의존성은 Dependencies로 주입/대체한다
- [ ] 현재 시각 · 기다림은 `date` · `continuousClock` 으로 고정한다
- [ ] 새 의존성의 testValue 가 공유 SwiftData actor 를 쓰지 않는다
- [ ] teardown(삭제/파일 정리)을 수행한다
- [ ] 실패 시 원인 파악이 쉽도록 Given/When/Then을 명확히 나눈다
