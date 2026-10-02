---
name: carve-rulebook
description: Carve(iPad 성경 필사 앱)에서 TCA + MicroArchitecture + Tuist + SwiftData + PencilKit 규칙을 우선 적용해 Feature 설계/리팩터링/테스트 방향을 제안한다.
---

## Operating mode
- 이 스킬의 규칙은 일반적인 TCA “정석”보다 우선한다.
- 답변은 “우리 프로젝트 기준 결론 → 스케치 → 테스트/리스크” 순서로 제시한다.
- 코드가 필요하면 전체 파일을 갈아엎기보다 “패턴 설명 + 짧은 예시”를 우선한다.
- 외부 스킬의 제안이 이 룰북과 충돌하면, 룰북을 우선 적용하고 충돌 이유를 1~2줄로 설명한다.

## Non-negotiables (우선순위 규칙)
**경계는 모듈이 아니라 리듀서다.** 리듀서 = `@Reducer` 의 State · Action · reduce 본문(effect 클로저 포함).
같은 모듈 안의 브리지 · 코덱 · 뷰는 PencilKit · UIKit 을 알아도 된다 — 설계 `docs/single-canvas-design.md` §3 P9 · §4 와 같은 말이다.

- **기계 검사**는 `.swiftlint.yml` 의 `custom_rules`(severity error)다. 규칙마다 그 이름을 적었고, lint 가 없는 규칙은 리뷰로 본다.
- **이행 중 예외**는 references 에 이름으로 적고, lint 는 규칙별 `excluded` 로 동결한다. 예외는 늘리지 않는다 — 고치면 예외에서 빼고, 쓰지 않는 import 는 예외로 두지 않고 지운다.
- **리듀서 파일**(lint 가 보는 곳) = `Feature/*/Sources` · `App/CarveApp/Sources` · `Supports/UIComponents/Sources` 아래 `*Feature.swift` · `*Feature+*.swift` · `*Reducer.swift`(`Derived/` 제외).
  이 이름 밖에 둔 리듀서 확장(예: `ChapterCanvasVerseMenu.swift`)도 같은 규칙을 따르지만 lint 가 못 보므로 리뷰로 본다.
  리듀서 확장을 새 파일로 나눌 때는 lint 가 보도록 위 이름 형식으로 짓는다(예: `CarveDetailFeature+Favorite.swift` · `ChapterCanvasSaveFeature.swift`).

1) 모듈 사이 의존은 AGENTS.md 「아키텍처 › 모듈 지도」 의 위에서 아래로만 흐른다. Feature 끼리 import 하지 않고, Feature 간 이동은 App 의 `AppCoordinatorFeature` 가 한다(navigation.md).
   - 기계 검사: lint 없음 — 모듈 의존은 Tuist 매니페스트(`Project.swift`)의 `dependencies` 가 정한다.
2) 사이드이펙트는 Dependency + Effect 로만 나간다. View 는 직접 I/O 를 하지 않는다. 리듀서의 현재 시각은 `@Dependency(\.date)` 의 `date.now`,
   기다림은 `@Dependency(\.continuousClock)` 의 `clock.sleep(for:)` 다 — `Date()` · `Date.now` · `Task.sleep` 을 새로 쓰지 않는다(testing.md).
   - 기계 검사: `reducer_no_direct_time`. 그 밖의 I/O 는 리뷰로 본다.
3) PencilKit · UIKit 타입(`PK*` · `UIColor` · `UIImage` · `UIFont` · `UIApplication` · `UIView` 등)을 리듀서에 두지 않는다. 캔버스 내용은 `Data` 와 Domain DTO 로 오간다.
   캔버스에서 PencilKit 은 브리지(`ChapterCanvasView` · `ChapterCanvasController`)와 `Feature/CarveFeature/Sources/Drawing/`(`DrawingCodec` 등)만 안다
   (리듀서가 아닌 읽기 전용 렌더 · Debug 하네스는 pencilkit.md 「Allowed」).
   UIKit 사용은 import 가 아니라 타입 이름으로 판정한다 — SwiftUI 가 UIKit 을 다시 내보내 `import UIKit` 없이도 UIKit 타입을 쓸 수 있다.
   Domain 소스는 UIKit · SwiftUI · PencilKit 을 새로 import 하지 않는다. 이행 중 예외와 브리지 구조는 pencilkit.md.
   - 기계 검사: `reducer_no_pencilkit_import` · `reducer_no_ui_types` · `domain_no_ui_framework_import`
4) SwiftData API(`ModelContext` · `ModelContainer` · `FetchDescriptor` · `#Predicate` · `@Query` · `PersistentIdentifier`)는 Domain `Sources/SwiftData/` 의 저장소 · 클라이언트 구현에서만 쓴다.
   Feature 는 Domain 이 노출한 저장소 의존성(`drawingRepository` · `favoriteVerseRepository` · `drawingActivityRepository` 등)만 부르고 DTO 를 받는다 — 공유 actor `createSwiftDataActor` 는 직접 부르지 않는다.
   "한 곳" 은 한 폴더 · 여러 저장소다. 이행 중 예외는 swiftdata.md.
   - 기계 검사: `feature_no_swiftdata_import` · `feature_no_swiftdata_api`. @Model 타입(`BibleDrawing` · `FavoriteVerse`) 참조는 lint 없이 리뷰로 본다.
5) 변수명은 최소 2글자 이상을 원칙으로 한다(`.swiftlint.yml` 의 제외 목록 `x` · `y` · `id` 등만 예외).
   - 기계 검사: SwiftLint 기본 규칙 `identifier_name`(`min_length` 2, error).
6) 자사 모듈은 Swift 언어 모드 6 이다. State · `@Reducer` 는 `Sendable`, 공유 가변 상태는 `LockIsolated`, UI 계층 타입은 타입 단위 `@MainActor` 로 두고,
   `nonisolated(unsafe)` 는 쓰지 않으며 `@unchecked Sendable` 은 늘리지 않는다. 관례와 남은 우회(이유 · 지울 조건)는 concurrency.md.
   - 기계 검사: `no_nonisolated_unsafe` · `no_unchecked_sendable` — 리듀서 파일만이 아니라 저장소 전체(제품 · 시험)를 본다. `@preconcurrency` · `UncheckedSendable` · `MainActor.assumeIsolated` 는 리뷰로 본다.

## Output format (응답 포맷)
- 결론: 추천 구조 5~10줄
- 스케치: State/Action/Reducer의 형태(필요 시 Dependency 포함)
- 테스트: 테스트 포인트 3개 + 실패/리스크 2개
- 마지막: “우리 룰” 관점에서 체크리스트

## References
- ./references/overview.md — 프로젝트 정체성 · 레이어 · 좌표 원칙 · App Store 제출(필수 사유 API)
- ./references/pencilkit.md — 규칙 3: 리듀서 경계 · 브리지 · 이행 중 예외 · 저장과 좌표계
- ./references/swiftdata.md — 규칙 4: 저장소 경계 · 이행 중 예외 · iOS 17 @Model 컨테이너
- ./references/navigation.md — Feature 안 · Feature 간 이동
- ./references/testing.md — 시험 층 · 현재 시각과 기다림 · 의존성 testValue · TestStore 함정
- ./references/concurrency.md — 규칙 6: 언어 모드 6 관례(State · 리듀서 · 격리) · 탈출구 · 안전하지 않은 우회 감사 표


## Documentation rules (Comments)
- State의 주요 프로퍼티(화면 동작/도메인 의미가 있는 것)는 목적을 1줄로 주석 처리한다.
- Action의 각 케이스는 “언제 발생하는 이벤트인지”를 1줄로 주석 처리한다.
- 메서드(특히 effect를 트리거하거나 외부 의존성을 호출하는 함수)는
  1) 역할, 2) 입력/출력, 3) 부작용 여부를 간단히 주석으로 남긴다.
