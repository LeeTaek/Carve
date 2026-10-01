# SwiftData Rules (Carve)

## Goal
- 리듀서가 SwiftData 세부 구현(ModelContext, @Model, FetchDescriptor 등)에 직접 의존하지 않게 한다.
- 저장/조회 로직을 한 폴더(Domain `Sources/SwiftData/`)의 저장소 구현으로 모아 디버깅/테스트/리팩터링을 쉽게 만든다.
- 운영 앱(배포) + 스터디 목적을 동시에 만족하도록, "현재 구조를 유지하면서도 추후 분리 가능한 설계"를 지향한다.

---

## Current state (현 구성)
- SwiftData 는 Domain `Domain/Domain/Sources/SwiftData/` 한 폴더에 있다 — 스키마와 마이그레이션(`Model/DrawingSchemaV1~V6` · `DrawingDataMigrationPlan`),
  actor(`SwiftDatabaseActor`), 저장소 구현(`SwiftDataDrawingRepository` · `SwiftDataFavoriteVerseRepository` · `SwiftDataDrawingActivityRepository`),
  옛 클라이언트(`DrawingDatabase`), 저장소 열기 · 소유 증명(`ReleaseStoreBootstrapper` · `LocalStoreLoader` · `CloudKitStoreOwnershipProofClient` 등).
- 저장소 계약(프로토콜)과 DTO 는 Domain 의 주제 폴더에 있다 — `Sources/Drawing/`(`DrawingRepository` · `VerseDrawingSnapshot` · `DrawingActivityRepository` · `DrawingActivity`),
  `Sources/Favorite/`(`FavoriteVerseRepository` · `FavoriteVerseSnapshot`).
- App 은 조립 지점이다 — `App/CarveApp/Sources/App/App.swift` 가 Domain(`ReleaseStoreBootstrapper`)이 연 `ModelContainer` 를 받아 `SwiftDatabaseActor` 와 저장소를 의존성으로 넣는다.
- **"한 곳" 은 한 폴더 · 여러 저장소다.** 저장소는 주제마다 하나씩 두고, 모두 `Sources/SwiftData/` 안에서 구현한다.

---

## Core principles
1) SwiftData API(`ModelContext` · `ModelContainer` · `FetchDescriptor` · `#Predicate` · `@Query` · `PersistentIdentifier`)는 Domain `Sources/SwiftData/` 의 저장소 · 클라이언트 구현에서만 쓴다.
   - 기계 검사: `feature_no_swiftdata_api`(Feature 소스의 SwiftData API 이름)
2) Feature 는 SwiftData 를 import 하지 않는다. 쓰지 않는 import 는 예외로 두지 않고 지운다.
   - 기계 검사: `feature_no_swiftdata_import`
3) Feature 는 Domain 이 노출한 저장소 의존성만 부르고 결과로 Domain DTO 를 받는다 — `drawingRepository` · `favoriteVerseRepository` · `drawingActivityRepository` · `drawingDataEraser` · `drawingVerseImporter` 등.
   공유 actor(`createSwiftDataActor`)와 @Model 을 돌려주는 옛 클라이언트(`drawingData` = `DrawingDatabase`)는 새로 부르지 않는다 — 필요한 조회는 저장소에 DTO 를 돌려주는 메서드로 더한다.
   - 기계 검사: lint 가 보장하지 않는다 — 리뷰로 본다.
4) Feature 는 @Model 타입(`BibleDrawing` · `FavoriteVerse` 등)을 State · Action 에 두거나 직접 만들지 않는다. 저장소가 DTO 로 바꿔 넘긴다.
   - 기계 검사: 없음(리뷰). 지금 참조하는 6파일은 아래 이행 중 예외다.
5) 저장/조회는 "무엇을 저장하나(도메인 · DTO)"와 "어떻게 저장하나(SwiftData)"를 분리한다.
6) async 작업은 Effect 로 분리하고, UI 이벤트와 저장 작업의 타이밍을 명시적으로 설계한다.

### 이행 중 예외 (레거시 — 늘리지 않는다)
lint 가 있는 규칙(`feature_no_swiftdata_import` · `feature_no_swiftdata_api`)은 규칙별 `excluded` 로 동결하고, lint 가 없는 항목(@Model 참조 · 옛 의존성 호출)은 이 표가 목록이다. 고치면 예외에서 뺀다.

| 무엇 | 어디 |
|---|---|
| `import SwiftData` · Action 의 `PersistentIdentifier` · `persistentModelID` · State 의 @Model `[BibleDrawing]` | `VerseDrawingHistoryFeature`(이전 필사 내용 보기) |
| 공유 actor `createSwiftDataActor` 로 저장소가 비었는지 확인(`databaseIsEmpty(BibleDrawing.self)` · `FavoriteVerse.self`) | `iCloudSettingReducer`(전체 삭제 확인) |
| @Model 타입(`BibleDrawing` · `FavoriteVerse`) 참조 — Feature 6파일 | `CarveDetailFeature` · `CanvasFeature`(N-Canvas) · `SentencesWithDrawingFeature` · `VerseDrawingHistoryFeature` · `VerseDrawingHistoryView` · `iCloudSettingReducer` |
| 옛 클라이언트 `drawingData`(`DrawingDatabase`) 호출 | `CarveDetailFeature` · `VerseDrawingHistoryFeature` · `CarveNavigationFeature`(`fetchDrawingRecord` — DTO 를 돌려준다) |
| App 리듀서의 공유 actor — 로컬 필사가 있는지(`hasAny(BibleDrawing.self)`) | `LaunchProgressFeature`(App) |

---

## Access boundary (접근 경계)
### Allowed
- Feature 리듀서 → (Dependency) Domain 저장소 계약 → `Sources/SwiftData/` 의 구현 → `SwiftDatabaseActor`
- App(조립) → Domain 이 연 `ModelContainer` 를 `withDependencies` 와 SwiftUI `.modelContainer` 에 건다

### Forbidden
- Feature 에서 SwiftData API(`ModelContext` · `ModelContainer` · `FetchDescriptor` · `#Predicate` · `@Query` · `PersistentIdentifier`) 사용
- Feature 에서 `@Model` 타입을 직접 참조(State · Action · 생성)
- Feature 에서 공유 actor(`createSwiftDataActor`)를 직접 부르기
- UI(View)에서 데이터 저장/쿼리 호출

권장 구조:
- 계약(프로토콜) + DTO 는 Domain 주제 폴더, 구현은 `Sources/SwiftData/`.
  본보기: Domain `FavoriteVerseRepository`(프로토콜) + `SwiftDataFavoriteVerseRepository`(구현) + `FavoriteVerseRepositoryTesting`
- 내부에서만 SwiftData 의 fetch/save 를 수행

---

## API design guideline (Repository/Client)
- 메서드는 "UI 관점"이 아니라 "도메인 관점"으로 설계한다.
- 결과 타입은 **Domain DTO** 를 쓴다(@Model 을 돌려주지 않는다).
- 호출자가 "쿼리 세부"를 알 필요 없게 만든다.

예시(지금 코드):
- `DrawingRepository.load(chapter:) -> DrawingChapterLoad` — 장의 스냅샷(`VerseDrawingSnapshot`)과 그 조회 시점의 저장소 세대
- `DrawingRepository.apply(_:chapter:generation:)` — 한 편집의 절 저장 명령을 한 트랜잭션으로(전부 성공 또는 전부 실패)
- `FavoriteVerseRepository.favorites() -> [FavoriteVerseSnapshot]`
- `DrawingActivityRepository.activities(in:) -> [DrawingActivity]`

---

## Persistence model vs Domain model (모델 전략)
SwiftData schema(@Model)에 강하게 엮인 모델이 존재할 수 있으므로, 2가지 전략을 허용한다.

### Strategy A: Single model (현 구조 유지, 단기)
- `@Model` 은 Domain `Sources/SwiftData/Model/`(`DrawingSchemaV1~V6`)에 있다.
- 단, Feature로 `@Model` 타입이 새지 않도록 저장소가 DTO 로 바꿔 넘긴다(이행 중 예외 제외).

### Strategy B: Split model + mapping (추후 권장)
- Domain에는 순수 모델(DTO)을 둔다.
- SwiftData 구현(또는 Persistence 모듈)에 `@Model`을 두고 매핑한다.
- 장점: Domain 순수화, 교체 가능성 증가, 테스트 용이

> 현재는 A를 유지하되, 저장소 API는 B로 옮겨도 안 깨지게(= DTO 중심) 설계한다. `DrawingRepository` · `FavoriteVerseRepository` · `DrawingActivityRepository` 가 이미 그렇다.

---

## Concurrency & scheduling (동시성/타이밍)
- UI 이벤트는 MainActor에서 Action으로 들어온다.
- 저장/정리는 Reducer 내부에서 직접 하지 않고 **Effect로 분리**한다.
- 드로잉 저장은 빈번하므로 다음 중 하나를 명시적으로 선택한다:
  - `debounce` 저장
  - 드로잉 종료 시점 저장
  - 수동 저장 버튼 저장

주의:
- "그리는 중"에는 무거운 fetch/merge/save를 피한다.
- 필요한 경우 cancellation id를 사용해 이전 저장 작업을 취소할 수 있어야 한다.

---

## CloudKit sync & bootstrap (동기화/초기화)
- CloudKit/동기화 상태는 `ObservableObject`(예: `PersistentCloudKitContainer`)로 표현할 수 있다.
- Launch/Bootstrap 과정에서 SwiftData 준비 및 sync 완료 이벤트를 Feature에서 관찰한다.
- AppCoordinator는 "동기화 완료" 같은 이벤트를 받아 root 전환을 수행한다.

원칙:
- sync 이벤트 관찰은 "상태를 표현"하는 곳에서 수행하고,
- Feature는 그 상태 변화에만 반응한다(직접 초기화 로직을 들고 있지 않기).

---

## Error handling (에러 처리)
- SwiftData/CloudKit 에러는:
  - 사용자에게 노출할 에러(네트워크/계정 등)
  - 로그만 남길 에러(일시적/복구 가능)
  를 구분한다.
- Repository는 "도메인 친화적 에러"로 변환해 넘기는 것을 선호한다.

---

## Naming & documentation
- 타입 네이밍 예시:
  - 계약(프로토콜): `DrawingRepository`
  - 구현: `SwiftData<이름>Repository`(예: `SwiftDataDrawingRepository`)
- 주석 규칙:
  - 저장/조회 메서드는 "무엇을 보장하는지(계약)"를 1줄로 남긴다.
  - 마이그레이션/스키마 버전은 "왜 이 버전이 필요한지"를 기록한다.
- 변수명은 2글자 이상을 기본으로 한다.

---

## iOS 17 — @Model 은 컨테이너가 있어야 만든다
- 규칙: 시험에서 @Model 인스턴스(`BibleDrawing(...)` 등)를 만들기 전에 그 모델을 담는 컨테이너를 먼저 만들고 시험 끝까지 쥔다.
  ```swift
  let container = try ModelContainer(for: BibleDrawing.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  defer { withExtendedLifetime(container) {} }
  ```
- 이유: 활성 컨테이너 없이 @Model 을 만들면 iPadOS 17 에서만 `failed to find a currently active container for <모델>` 로 trap 해 시험 프로세스가 죽는다
  (xcresult 에는 "Test crashed with signal trap"). 18 이상은 통과하고, 다른 시험이 컨테이너를 살려 둔 순서에서는 17 에서도 우연히 통과해 원인이 가려진다.
- 확인: 17.5 회귀에서만 signal trap 이 나면 로그에서 위 문구를 먼저 찾고, `-only-testing:<타깃>/<스위트>/<함수>()` 로 단독 재현한다(Swift Testing 함수는 괄호 필수).
- 본보기: `Feature/CarveFeature/Tests/CanvasLightAppearanceTesting.swift`
- 기계 검사: 없음.

---

## Testing checklist
- Reducer 테스트에서는 Repository를 mock으로 주입한다.
- 새 저장소 의존성의 `testValue` 는 공유 SwiftData actor 를 쓰지 않는 빈 스텁으로 둔다(testing.md).
- Repository 단위 테스트는 in-memory 또는 임시 저장소로 수행한다.
- @Model 을 만드는 시험은 컨테이너부터 만든다(위 iOS 17 절).
- 최소 기준:
  - 저장 1건 → 조회 1건이 일관되는지
  - 히스토리/정렬(createdAt 등) 규칙이 맞는지
  - 마이그레이션 모드/일반 모드 플로우가 분기대로 동작하는지

---

## Definition of done (SwiftData 작업 완료 기준)
- Feature 에 `import SwiftData` 가 새로 없다 — `feature_no_swiftdata_import` error 0
- Feature 에 SwiftData API 가 새로 없다 — `feature_no_swiftdata_api` error 0
- 새 조회 · 저장은 Domain 저장소 계약 + `Sources/SwiftData/` 구현으로 들어갔고, 결과는 DTO 다.
- @Model 참조 · `createSwiftDataActor` · `drawingData` 호출이 늘지 않았다(이행 중 예외 표).
- 동시성/타이밍 정책(debounce/end-of-drawing 등)이 문서화돼 있다.
- 테스트가 최소 기준을 충족한다.
