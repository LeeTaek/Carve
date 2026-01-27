# SwiftData Rules (Carve)

## Goal
- Feature가 SwiftData 세부 구현(ModelContext, @Model, FetchDescriptor 등)에 직접 의존하지 않게 한다.
- 저장/조회 로직을 한 경로로 모아 디버깅/테스트/리팩터링을 쉽게 만든다.
- 운영 앱(배포) + 스터디 목적을 동시에 만족하도록, “현재 구조를 유지하면서도 추후 분리 가능한 설계”를 지향한다.

---

## Current state (현 구성)
- 현재 레포에서는 SwiftData 관련 코드가 **Domain에 포함**될 수 있다.
- 다만 Feature 관점에서는 SwiftData가 **직접 보이지 않도록** 경계를 둔다.

---

## Core principles
1) **Feature는 SwiftData를 직접 import 하지 않는다.**
2) 데이터 접근은 **Repository/Client(Dependency) 단일 진입점**을 통해서만 수행한다.
3) SwiftData 스키마/모델(@Model)과 ModelContext 접근 코드는 **한 폴더/파일군으로 격리**한다.
4) 저장/조회는 “무엇을 저장하나(도메인)”와 “어떻게 저장하나(SwiftData)”를 분리한다.
5) async 작업은 Effect로 분리하고, UI 이벤트와 저장 작업의 타이밍을 명시적으로 설계한다.

---

## Access boundary (접근 경계)
### Allowed
- Feature → (Dependency) Repository/Client → SwiftData 구현

### Forbidden
- Feature에서 `ModelContext` 직접 사용
- Feature에서 `@Model` 타입을 직접 참조
- UI(View)에서 데이터 저장/쿼리 호출

권장 구조:
- `DrawingRepository` / `DrawingStore` 같은 계약을 통해 도메인 레벨 API만 제공
- 내부에서만 SwiftData의 fetch/save를 수행

---

## API design guideline (Repository/Client)
- 메서드는 “UI 관점”이 아니라 “도메인 관점”으로 설계한다.
- 결과 타입은 가능한 한 **Domain 모델/DTO**를 사용한다.
- 호출자가 “쿼리 세부”를 알 필요 없게 만든다.

예시(개념):
- `fetchDrawing(for verseId: VerseID) -> Drawing?`
- `saveDrawing(_ drawing: Drawing) -> Void`
- `fetchHistory(for chapterId: ChapterID) -> [DrawingHistory]`

---

## Persistence model vs Domain model (모델 전략)
SwiftData schema(@Model)에 강하게 엮인 모델이 존재할 수 있으므로, 2가지 전략을 허용한다.

### Strategy A: Single model (현 구조 유지, 단기)
- Domain 내부에 `@Model`이 존재할 수 있다.
- 단, Feature로 `@Model` 타입이 새지 않도록 Repository에서 캡슐화한다.
- `SwiftData/` 또는 `Persistence/` 폴더로 격리한다.

### Strategy B: Split model + mapping (추후 권장)
- Domain에는 순수 모델(예: `Drawing`)을 둔다.
- `SwiftDataClient`(또는 Persistence 모듈)에 `@Model`을 두고 매핑한다.
- 장점: Domain 순수화, 교체 가능성 증가, 테스트 용이

> 현재는 A를 유지하되, Repository API는 B로 옮겨도 안 깨지게(= Domain 타입 중심) 설계한다.

---

## Concurrency & scheduling (동시성/타이밍)
- UI 이벤트는 MainActor에서 Action으로 들어온다.
- 저장/정리는 Reducer 내부에서 직접 하지 않고 **Effect로 분리**한다.
- 드로잉 저장은 빈번하므로 다음 중 하나를 명시적으로 선택한다:
  - `debounce` 저장
  - 드로잉 종료 시점 저장
  - 수동 저장 버튼 저장

주의:
- “그리는 중”에는 무거운 fetch/merge/save를 피한다.
- 필요한 경우 cancellation id를 사용해 이전 저장 작업을 취소할 수 있어야 한다.

---

## CloudKit sync & bootstrap (동기화/초기화)
- CloudKit/동기화 상태는 `ObservableObject`(예: `PersistentCloudKitContainer`)로 표현할 수 있다.
- Launch/Bootstrap 과정에서 SwiftData 준비 및 sync 완료 이벤트를 Feature에서 관찰한다.
- AppCoordinator는 “동기화 완료” 같은 이벤트를 받아 root 전환을 수행한다.

원칙:
- sync 이벤트 관찰은 “상태를 표현”하는 곳에서 수행하고,
- Feature는 그 상태 변화에만 반응한다(직접 초기화 로직을 들고 있지 않기).

---

## Error handling (에러 처리)
- SwiftData/CloudKit 에러는:
  - 사용자에게 노출할 에러(네트워크/계정 등)
  - 로그만 남길 에러(일시적/복구 가능)
  를 구분한다.
- Repository는 “도메인 친화적 에러”로 변환해 넘기는 것을 선호한다.

---

## Naming & documentation
- 타입 네이밍 예시:
  - 계약(프로토콜): `DrawingRepository`
  - 구현: `SwiftDataDrawingRepository` 또는 `DrawingRepositoryLive`
- 주석 규칙:
  - 저장/조회 메서드는 “무엇을 보장하는지(계약)”를 1줄로 남긴다.
  - 마이그레이션/스키마 버전은 “왜 이 버전이 필요한지”를 기록한다.
- 변수명은 2글자 이상을 기본으로 한다.

---

## Testing checklist
- Reducer 테스트에서는 Repository를 mock으로 주입한다.
- Repository 단위 테스트는 in-memory 또는 임시 저장소로 수행한다.
- 최소 기준:
  - 저장 1건 → 조회 1건이 일관되는지
  - 히스토리/정렬(createdAt 등) 규칙이 맞는지
  - 마이그레이션 모드/일반 모드 플로우가 분기대로 동작하는지

---

## Definition of done (SwiftData 작업 완료 기준)
- Feature에 `import SwiftData`가 없다.
- 저장/조회 경로가 Repository/Client 하나로 통일돼 있다.
- 동시성/타이밍 정책(debounce/end-of-drawing 등)이 문서화돼 있다.
- 테스트가 최소 기준을 충족한다.
