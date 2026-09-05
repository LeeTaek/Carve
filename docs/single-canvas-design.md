# CarveFeature 단일 Canvas 전환 설계

> 상태: **Phase 0B · S4 · Phase 1(구현) 완료** · 대상: `Feature/CarveFeature`, `Domain`
> rev.13 — **Phase 1 (V4 additive schema) 구현 완료** (`b68b6101`).
> optional 필드 2개(`layoutMetadataData` · `rowUUID`)만 추가하고 lightweight 마이그레이션 한 단계.
> **`drawingVersion` 을 건드리지 않고 좌표도 변환하지 않습니다** (§10-2).
> V3 → V4 마이그레이션을 임시 store 로 **실제로 태워** 검증했고, §10-3 의 등가 검증
> (기존 N-Canvas 경로가 마이그레이션된 V4 저장소에서 동작)을 확보했습니다 (§20-5).
> **⚠️ 구현 완료 ≠ 배포 가능** — CloudKit 제약은 D7 이월, V4 는 forward-only 입니다 (§13).
> 회귀 기준선 **155 → 175**.
> 멤버십 재결제 완료, **활성화 전파 대기 중** — 전파되면 Phase 0A-D 전체가 열립니다.
> **⚠️ Phase 2 는 D5 측정 이후에 착수합니다** — `LazyVStack` 을 걷어내면 baseline 측정 기회가 사라집니다 (§13).
> rev.12 — **Phase 0B 완료** (`f5206814` 레이아웃 · `0c071d29` 소유권/승계 · `565dfe69` line band reflow)
> **· Phase 0A-S4 완료** (`b53cbfd8` 스크롤 A/B spike 하네스).
> **★ S4 는 A 와 B 를 구별하지 못했습니다** — 8개 시나리오 전부 A·B 모두 max **0.000pt** PASS 였습니다 (§11 "S4 실행 결과").
> 따라서 현시점 "B 우세" 의 근거는 **수치가 아니라 구조**이며,
> **A/B 의 실질적 판정은 Phase 0A-D 의 D1/D2 로 이월됩니다** (§12).
> reflow 구현에서 결정한 §9 명세 공백 4건과, B 구조의 캔버스 좌표 규정·하단 인셋 미결을 §5 에 반영했습니다.
> `StableCanvasView` 가 "460줄 별도 파일" 이라는 서술을 정정했습니다 (§2 D5 · §11 · 부록).
> 회귀 기준선 **122 → 155**.
> rev.11 — **Phase 0B 착수.** `ChapterLayout` / `ChapterLayoutBuilder` 구현 완료 (`f5206814`).
> 구현 중 드러난 §5 명세 공백 2건(여유 높이 귀속 · 캔버스 폭 가정)을 보강하고,
> signature 의 `chapter` 포함 여부를 미결로 명시했습니다. 회귀 기준선 **82 → 95**.
> rev.10 — **D8(실기기 legacy 데이터 추출) 완료.** S5 fixture 확보로 Phase 0B 가 열렸습니다 (§18-4·§20-3).
> 그 과정에서 **`normalizedForVerseRect` 휴리스틱이 실데이터의 71%에서 실패**함이 실측됐습니다 (§10-2-1).
> 회귀 기준선 **76 → 82** (§19-4-2).
> rev.9 — **Phase 0A-S0 / S1 / S2 실행 완료** (측정 결과는 §18·§19) **+ 검증에서 파생된 기존 코드 버그 2건 수정 완료** (§16·§20).
> S1에서 §7-4·§7-5의 전제가 뒤집혔고, S2에서 §9-3의 `textLineRanges`가 확정됐습니다. PencilKit·SwiftData API는 iOS 26.2 SDK 헤더로 확인함.
> **rev.8의 "코드 변경·빌드·테스트는 수행하지 않았습니다"는 더 이상 사실이 아닙니다.**
> 기존 N-Canvas 구조 위의 수정 커밋 2건이 존재합니다 — `19be99ea`(주간 요약 동점 tie-break, S0-2 파생), `7ba5bc46`(지우개 저장 누락, S1-3 파생).
> **단, 새 아키텍처(Phase 0B 이후)는 여전히 미착수입니다.**
> `ChapterLayout` / `ChapterCanvasFeature` / `DrawingCodecClient` / `DrawingRepository` / `DrawingSchemaV4` 는 저장소에 **존재하지 않으며**(grep 확인, 스키마는 V3까지), 이 문서의 §4~§11은 전부 미구현 설계입니다.
> "검증 필요" 표시된 항목은 Phase 0A 실기기 확인 전까지 확정하지 않습니다.

---

## 1. 배경과 목표

### 현재 구조의 문제

- 각 절 Row가 `CanvasFeature` → `PKCanvasView`를 하나씩 생성합니다.
  ([SentencesWithDrawingView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/SentenceWithDrawing/SentencesWithDrawingView.swift))
- 절 경계를 넘는 획은 캔버스 경계에서 **끊깁니다.**
- 저장이 캔버스 단위로 일어나 SwiftData CRUD가 UI 구조에 종속됩니다.

### 목표

| # | 완료 조건 |
|---|---|
| G1 | 장(chapter)당 `PKCanvasView`는 **하나**. 필기 범위 제약 최소화 |
| G2 | 기존 절별 Drawing 데이터를 새 구조에서 올바른 위치에 배치 |
| G3 | 그려진 Y 범위에 따라 절별로 적합하게 저장 |
| G4 | 폰트/자간/폭 변경 시 밑줄 기준으로 필사가 재배치 |

---

## 2. 진단 — 왜 두 번 롤백됐는가

```
62c1abaa  1.2.0  CombinedCanvas 적용
e698a3c9  1.2.1  drawing rallback          ← 1차 롤백
69171e5a         [Edit] List 기반 롤백      ← 2차 롤백
```

`CombinedCanvasFeature` / `CombinedCanvasView`(726줄)는 파일로 남아 있고 호출부만 주석 처리된 상태입니다.

| # | 원인 | 근거 |
|---|---|---|
| D1 | **clipping이 손실적** — control point를 rect로 걸러 `PKStrokePath`를 재구성. 곡선 형태가 변하고 저장→복원→저장이 idempotent하지 않음 | [PKDrawing+Extension.swift:47](../Feature/CarveFeature/Sources/Extension/PKDrawing+Extension.swift) |
| D2 | **매 저장마다 전체 재절단** — 해당 절 데이터가 "그 순간 rect 안에 보이는 것"으로 덮어써짐 | [CombinedCanvasFeature.swift:167](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasFeature.swift) |
| D3 | **좌표계 구분자 없음** — `normalizedForVerseRect(tolerance: 20)`으로 절대/로컬을 추측. `drawingVersion`은 전부 `1`로만 쓰이는 죽은 필드 | [PKDrawing+Extension.swift:20](../Feature/CarveFeature/Sources/Extension/PKDrawing+Extension.swift) |
| D4 | **LazyVStack + 전체 캔버스는 원리적 충돌** — 화면 밖 절의 rect를 알 수 없어 `drawingRect` 맵이 항상 불완전 | [CombinedCanvasFeature.swift:106](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasFeature.swift) |
| D5 | **스크롤 컨테이너 2개** — `PKCanvasView`는 `UIScrollView`(SDK 확인)인데 SwiftUI `ScrollView` 안에 넣어 offset drift. `StableCanvasView`(아래 정정 참조)와 issue #6의 원인 | [CombinedCanvasView.swift:21](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasView.swift) |
| D6 | **레이아웃 메타데이터 없음** — 어떤 폭/폰트에서 그려졌는지 기록이 없어 G4가 원리적으로 불가능 | [DrawingSchemaV3.swift](../Domain/Domain/Sources/SwiftData/Model/DrawingSchemaV3.swift) |
| D7 | **지우개/undo 저장 누락** — stroke 수 증가시에만 변경 영역 계산, 빈 결과는 skip → 마지막 획 삭제가 DB에 반영 안 됨 | [CombinedCanvasView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasView.swift), [CombinedCanvasFeature.swift:186](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasFeature.swift) |
| D8 | **저장이 원자적이지 않음** — 요청마다 개별 `save()`, 에러를 per-item으로 삼킴 → 부분 갱신 상태 발생 | [DrawingDatabase.swift:97](../Domain/Domain/Sources/SwiftData/DrawingDatabase.swift) |
| D9 | **편집 순서 미보장** — 연속 편집의 비동기 저장이 직렬화되지 않으면 최신 편집이 과거 편집에 덮일 수 있음 | 신규 |

#### 정정 — `StableCanvasView` 는 별도 파일이 아닙니다 (rev.12)

rev.11 이하는 "`StableCanvasView` 460줄" 이라고 적었으나, 실제로는
[CombinedCanvasView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasView.swift)
**한 파일 안에 함께 선언된 클래스(21~458행)** 입니다. 같은 파일의 나머지가 `CombinedCanvasView` 본체입니다(파일 전체 726줄).

하는 일은 셋뿐입니다.

| # | 하는 일 | D5 와의 관계 |
|---|---|---|
| ① | `contentScaleFactor` / `layer.contentsScale` / `CAMetalLayer.drawableSize` 를 screen scale 로 강제 동기화 | 라이브 스트로크가 확대돼 보이는 증상 대응 |
| ② | `contentSize = bounds.size`, `contentInset`·`contentOffset` 0, zoom 1 리셋 | **중첩 스크롤 보정 그 자체** |
| ③ | 대량 디버그 덤프 (레이어 트리 / presentation layer / subview / Metal layer) | 부록의 "디버그 dump(~400줄)" 가 가리키는 것 |

> **Phase 0A-S4 가 ②에 대해 확인한 것:** B 구조(캔버스가 유일한 `UIScrollView`)에는
> **②가 보정할 대상 자체가 존재하지 않습니다.** 그리고 A 구조에서도 ② 상당의 정규화를
> **꺼둔 채로** 시뮬레이터 통과 기준 1~6 이 전부 통과했습니다 — 즉 프로그램 스크롤 경로에는
> 보정할 drift 가 없었습니다. 상세는 §11 "S4 실행 결과".

---

## 3. 설계 원칙

| # | 원칙 | 해소 대상 |
|---|---|---|
| P1 | **획은 자르지 않는다.** 한 획은 통째로 한 절에 귀속된다 | D1 |
| P2 | **소유권은 편집 시점에 결정하고 승계한다.** 기하로 매번 재유도하지 않는다 | D2 |
| P3 | **좌표 형식은 `drawingVersion`으로 명시 기록한다.** 추측 금지 | D3 |
| P4 | **레이아웃이 전량 준비될 때까지 합성·입력·저장을 금지한다** | D4 |
| P5 | **스크롤 컨테이너는 하나.** 단, 형태는 spike로 확정 | D5 |
| P6 | **저장 시점의 레이아웃 메타데이터를 함께 남긴다** | D6 |
| P7 | **빈 결과도 mutation이다.** dirty 집합을 먼저 구하고 `clear`를 명시 생성 | D7 |
| P8 | **한 편집의 모든 절 저장은 단일 트랜잭션이다** | D8 |
| P9 | **Feature는 PencilKit/UIKit 타입을 모른다.** `Data`와 도메인 DTO만 다룬다 | 룰북 |
| P10 | **레이아웃 변경은 표시 변환일 뿐, 저장을 덮어쓰지 않는다** | 원본 보존 |
| P11 | **편집 결과는 즉시 화면에 확정하고, 저장은 revision으로 직렬화한다** | D9 |

---

## 4. 아키텍처 경계

```
CombinedCanvasView / Coordinator      ← PencilKit 타입은 여기까지만
    PKCanvasView, PKDrawing, PKTool
            ↓ Data + DTO
ChapterCanvasFeature                  ← 상태/액션/저장 orchestration
    State, Action                        PencilKit 타입 없음
            ↓ Dependency
DrawingCodecClient                    ← PencilKit을 아는 유일한 Dependency
    합성 / 소유권 / reconcile / reflow / transform 적용
            ↓
DrawingRepository                     ← SwiftData 단일 접근 경로
    atomic batch replace/clear
```

### 좌표 관련 책임 분리

룰북의 "좌표계 변환은 한 곳에서만"을 다음처럼 해석합니다.

| 컴포넌트 | 책임 |
|---|---|
| `ChapterLayoutBuilder` | 좌표 **영역**을 계산 (rect, 밑줄 anchor, 높이) |
| `DrawingCodecClient` | Drawing에 **transform을 적용하는 유일한 곳** |

Feature·View·Repository는 좌표 변환을 수행하지 않습니다.

### 모듈 배치 — 순환 의존 회피

현재 의존 방향은 `Domain → ClientInterfaces` 입니다
([Domain/Project.swift](../Domain/Domain/Project.swift), [ClientInterfaces/Project.swift](../Supports/ClientInterfaces/Project.swift)).
따라서 `BibleChapter`를 쓰는 `ChapterLayout` / `DrawingRepository` 계약을
`ClientInterfaces`에 두면 **순환 의존이 생깁니다.**

```
Domain
 ├─ ChapterLayout, VerseCanvasRegion, VerseDrawingSnapshot, VerseDrawingMutation
 ├─ DrawingRepository 계약
 └─ SwiftData 구현체 (기존 위치 유지)

CarveFeature
 ├─ ChapterCanvasFeature
 ├─ CombinedCanvasView / Coordinator
 └─ DrawingCodecClient 계약 + PencilKit Adapter
```

> 전용 Drawing Client 모듈 분리는 장기 과제로 두고 이번 전환에서는 새 모듈을 추가하지 않습니다
> (AGENTS.md: 폴더 구조 재구성 금지, 변경 범위 최소화).
> `DrawingCodecClient`가 `CarveFeature`에 있어도 룰북 위반이 아닙니다 —
> 경계는 **모듈**이 아니라 **Reducer**이고, `CarveFeature`는 이미 PencilKit을 의존합니다.

### State / Action

```swift
@Reducer
struct ChapterCanvasFeature {
    @ObservableState
    struct State {
        var chapter: BibleChapter

        /// 전 절 측정이 완료된 단일 좌표계 레이아웃 (nil이면 입력 금지)
        var layout: ChapterLayout?
        /// DB 조회 결과. layout과 도착 순서가 보장되지 않으므로 State에 보관 (§6-4)
        var loadedDrawings: [VerseDrawingSnapshot]?
        /// 장 전환 시 이전 요청의 결과를 폐기하기 위한 토큰 (§6-4)
        var loadRequestID: UUID?
        /// 본문 fetch로 확정된 절 개수. layout 완결 판정 기준 (§6-4)
        var expectedVerseCount: Int?

        /// Canvas에 표시할 opaque drawing data
        var renderedData: Data?
        /// Coordinator가 decode할지 판단하는 기준. Data 값 비교를 대신한다
        var renderedRevision: Int = 0

        /// 현재 Canvas stroke와 절 소유권의 대응 정보
        var ownership: OwnershipSnapshot?

        /// 절별로 지금 캔버스에 합성된 BibleDrawing 행 (§8-7)
        /// 편집은 항상 이 행에만 기록된다
        var activeRowIDs: [Int: BibleDrawingRowID] = [:]

        /// 화면에 적용된 최신 편집 번호
        var editRevision: Int = 0
        /// DB 저장까지 완료된 편집 번호
        var persistedRevision: Int = 0

        /// 저장 대기열. rowID 키로 coalescing, revision 동봉 (§8-3)
        var pendingMutations: [BibleDrawingRowID: PendingDrawingMutation] = [:]
        var saveStatus: SaveStatus = .idle

        /// Pencil 입력 중 layout 교체 방지
        var isEditing = false
        /// 입력 중 도착한 layout 변경 (pencil-up 이후 적용)
        var pendingLayout: ChapterLayout?

        /// 현재 레이아웃으로 의미 있게 재배치할 수 없는 절 (§9-3-1)
        /// 표시 상태이며 DB에 기록하지 않는다
        var layoutMismatchVerses: Set<Int> = []

        var canUndo = false
        var canRedo = false
    }

    enum Action {
        /// 전 절 geometry 측정 완료
        case layoutCompleted(ChapterLayout)
        /// 절별 저장 데이터 조회 완료
        case drawingsLoaded([VerseDrawingSnapshot])

        /// 편집 시작 — before 상태를 확보한다 (§8-1)
        case editBegan(CanvasEditBeginSnapshot)
        /// 펜/지우개 입력 종료
        case editEnded(CanvasEditSnapshot)
        /// undo/redo에 의한 Drawing 변경
        case historyEditEnded(CanvasEditSnapshot)

        /// 절별 replace/clear 계산 완료
        case mutationsPrepared(revision: Int, [VerseDrawingMutation])
        /// atomic 저장 완료
        case saveFinished(revision: Int, Result<Void, DrawingRepositoryError>)
        /// 장 전환 / 백그라운드 진입 시 대기열 flush (§8-5)
        case flushPending
        /// 히스토리에서 다른 회차를 선택해 복원 — mutation을 생성하지 않는다 (§8-7)
        case verseRowRestored(verse: Int, rowID: BibleDrawingRowID)

        case undoTapped
        case redoTapped
    }

    @Dependency(\.drawingCodec) var drawingCodec
    @Dependency(\.drawingRepository) var drawingRepository
}

/// 저장 중 도착한 최신 편집을 보호하기 위해 revision을 함께 보관한다 (§8-3)
struct PendingDrawingMutation: Equatable, Sendable {
    let revision: Int
    let mutation: VerseDrawingMutation
}

enum SaveStatus: Equatable, Sendable {
    case idle
    case saving(revision: Int)
    case failed(revision: Int, retryCount: Int)
}
```

> **`renderedData`를 State에 두는 이유**
> 초안은 "Data는 Codec 캐시에 두고 State에는 revision만"을 제안했으나 철회합니다.
> TCA `@ObservableState`는 keypath 단위 관찰이므로 `Data` 필드는 **쓰기 시에만** 무효화되며,
> 매 업데이트마다 값 비교가 일어나지 않습니다. 초안의 우려는 과도했습니다.
> View가 Dependency 캐시를 직접 읽으면 상태 기반 렌더링이 약해지고 수명 관리가 불명확해지므로,
> `renderedData + renderedRevision`을 State에 유지하고 Coordinator는 **revision이 바뀐 경우에만 decode**합니다.
> 실제 프로파일링에서 병목이 확인되면 그때 token cache를 도입합니다.

---

## 5. 데이터 모델 (DTO)

```swift
/// 절 하나의 캔버스 좌표 정보
struct VerseCanvasRegion: Equatable, Sendable {
    let verse: Int
    /// 절이 차지하는 영역. **§6-3 Pass 2의 여유 높이(extraHeight)를 포함한다.**
    /// 밑줄이 그려지는 구간은 그중 텍스트 줄 수만큼이고, 나머지는 초과 band용 여유다.
    let writingRect: CGRect
    /// 획 소유권을 판정하는 영역 (인접 절과의 midpoint로 분할)
    let captureRect: CGRect
    /// 밑줄 y 좌표 (writingRect 기준 상대값)
    let underlineAnchors: [CGFloat]

    /// 저장 origin = (writingRect.minX, 첫 밑줄 y)
    var storageOrigin: CGPoint {
        CGPoint(x: writingRect.minX,
                y: writingRect.minY + (underlineAnchors.first ?? 0))
    }
}

/// 장 전체 레이아웃 — 단일 좌표계의 유일한 진실 공급원
struct ChapterLayout: Equatable, Sendable {
    let chapter: BibleChapter
    let writingWidth: CGFloat
    let totalHeight: CGFloat
    let regions: [VerseCanvasRegion]
    /// §6-5의 안정적 signature
    let signature: String
}

/// BibleDrawing 행 식별자. SwiftData PersistentIdentifier를 Feature에 노출하지 않기 위한 도메인 키
struct BibleDrawingRowID: Hashable, Sendable { let raw: String }

/// DB에서 읽어온 절 하나의 저장 상태 (행 단위)
struct VerseDrawingSnapshot: Equatable, Sendable {
    let verse: Int
    let rowID: BibleDrawingRowID
    /// 이 행이 현재 대표(main)인지
    let isPresent: Bool
    let updateDate: Date?
    let lineData: Data
    /// 좌표 형식의 단일 진실 (BibleDrawing.drawingVersion 그대로)
    /// nil / 1 = legacy, 2 = verse-local + top-left, 3 = verse-local + underline anchor
    let drawingVersion: Int?
    /// drawingVersion == 3 일 때만 존재 (스키마 V4에서 도입)
    let metadata: DrawingLayoutMetadata?
}

/// 획 ↔ 절 소유권 대응
struct OwnershipSnapshot: Equatable, Sendable {
    /// **원본 획 → verse.** canvas stroke 엔트리와 1:1이 아니다 —
    /// bitmap 지우개 조각들은 같은 IdentityKey 를 공유한다 (§7-2)
    let map: [StrokeIdentityKey: Int]
    let layoutSignature: String            // 이 소유권이 성립한 레이아웃
}

/// 편집 시작 시점 스냅샷
struct CanvasEditBeginSnapshot: Sendable {
    let revision: Int
    let drawingData: Data
    let ownership: OwnershipSnapshot
    /// pencil-down 좌표. undo/redo면 nil
    let startPoint: CGPoint?
}

/// 편집 종료 시점 스냅샷 (PencilKit 타입 없음)
struct CanvasEditSnapshot: Equatable, Sendable {
    let revision: Int
    let drawingData: Data
    let dirtyBounds: CGRect?
    let reason: EditReason
}

enum EditReason: Sendable { case ink, erase, undo, redo }

/// 저장 명령 — 절이 아니라 **행**을 주소지정한다 (U2: 히스토리 유지)
enum VerseDrawingMutation: Equatable, Sendable {
    /// 활성 행의 내용을 교체
    case replace(verse: Int, rowID: BibleDrawingRowID,
                 data: Data, metadata: DrawingLayoutMetadata)
    /// 활성 행의 내용을 비움. **행을 삭제하지 않는다** (§8-7)
    case clear(verse: Int, rowID: BibleDrawingRowID)
    /// 해당 절에 행이 하나도 없을 때. rowID는 **저장 전에 미리 발급**된다 (§8-7)
    case create(verse: Int, rowID: BibleDrawingRowID,
                data: Data, metadata: DrawingLayoutMetadata)

    var verse: Int { ... }
    /// 세 케이스 모두 rowID를 가지므로 non-optional
    var rowID: BibleDrawingRowID { ... }
}
```

> **`startPoint`는 보조 정보입니다.**
> 소유권 앵커는 각 신규 획 **자신의 첫 control point**를 사용합니다.
> 한 번의 pen-down이 복수 획을 만드는 경우와 `startPoint == nil`인 undo/redo를 모두 커버하기 위함입니다.

### captureRect — 절 사이 gap 흡수

```
Verse 1 writingRect
──────────────────── midpoint   ← captureRect 경계
Verse 2 writingRect
──────────────────── midpoint
Verse 3 writingRect
```

첫 절 위쪽과 마지막 절 아래쪽은 각각 캔버스 끝까지 확장합니다.

#### 여유 높이는 `writingRect` 안에 둡니다 ★ (rev.11 — 구현 중 확정)

§6-3 Pass 2 의 `extraHeight` 를 **절 사이 gap 으로 두면 안 됩니다.**
gap 은 midpoint 로 분할되므로 **여유 공간의 절반이 다음 절 소유가 되어** 소유권이 어긋납니다.
초과 band 는 그 절의 것이므로 `writingRect` 하단에 포함하고, `underlineAnchors` 는
텍스트 줄 수만큼만 만듭니다 ([ChapterLayoutBuilder.swift](../Domain/Domain/Sources/Layout/ChapterLayoutBuilder.swift)).

#### 캔버스 폭과 원점 — 현재 가정 (rev.11)

`ChapterLayout` 에는 캔버스 폭·원점 개념이 없고, 현재 구현은
**필사 컬럼 = 캔버스** 로 보아 `writingRect.minX == 0`, `captureRect` 는 폭 전체로 둡니다.

> ⚠️ **Phase 2 에서 재검토가 필요합니다.** 호스팅 뷰가 본문 텍스트까지 포함하는
> 컬럼보다 넓은 캔버스를 쓰면 `writingRect.minX` 와 `captureRect` 의 x 범위를
> 별도로 규정해야 합니다. §11 의 A/B 판정 결과에 달려 있습니다.

#### 그 재검토를 S4 실측으로 구체화합니다 ★ (rev.12)

**B 구조에서는 이 경고가 이미 현실입니다.** B 는 `PKCanvasView` 가 유일한 스크롤 컨테이너이므로
**캔버스가 화면 전폭**이고, 필사 컬럼은 그 안의 한 영역일 뿐입니다.
따라서 위의 `writingRect.minX == 0` 가정과 **정면으로 충돌합니다.**

S4 하네스는 `ChapterLayout` 을 고치지 않고 **평행이동 한 겹**으로 풀었습니다
([CanvasScrollSpikeHosting.swift](../Feature/CarveFeature/Sources/Debug/CanvasScrollSpikeHosting.swift)).

```
캔버스 content 좌표 = layout 좌표 + columnOrigin

columnOrigin.x = isLeftHanded ? 0 : max(0, containerWidth − writingWidth)
columnOrigin.y = 0
```

- `ChapterLayout` 은 여전히 "필사 컬럼 = 원점" 좌표계를 유지합니다 — DTO 변경이 없습니다.
- 왼손/오른손 전환은 `columnOrigin.x` 만 바뀌며, S4 통과 기준 4 는 이 상태에서 **0.000pt** 였습니다.
- A 구조는 캔버스 자체가 컬럼이므로 `columnOrigin == .zero` 입니다. **두 구조의 차이가 이 한 값에 모입니다.**

> ⚠️ **B 를 채택하면 이 평행이동의 소유자를 정해야 합니다.**
> §4 는 "좌표 **영역** 계산 = `ChapterLayoutBuilder`, **transform 적용** = `DrawingCodecClient`" 로 나눠 뒀습니다.
> `columnOrigin` 은 영역이 아니라 transform 이므로 Codec 쪽이 자연스럽지만,
> `captureRect` 로 소유권을 판정하는 §7-1 이 **캔버스 좌표의 첫 control point** 를 입력으로 받으므로
> 판정 직전에 역변환이 필요합니다. Phase 3 착수 전에 **어느 계층이 `columnOrigin` 을 아는지** 확정하십시오.

> ❓ **신규 미결 — B 의 하단 safe area 인셋 (rev.12)**
> S4 의 B 는 `contentInsetAdjustmentBehavior = .never` 라 **하단 safe area 가 반영되지 않습니다.**
> A(SwiftUI `ScrollView`)는 같은 화면에서 adjusted inset bottom 20 이 자동으로 들어갔습니다.
> 스크롤 정합에는 영향이 없었지만(양쪽 다 0.000pt), **마지막 절의 필사 영역이 홈 인디케이터에 가릴지**는
> 인셋 정책의 문제입니다. `.never` 를 유지하고 `totalHeight` 하단에 여백을 더할지,
> `.always` 로 두고 `contentOffset` 기준을 조정할지 **Phase 3 에서 정해야 합니다.**
> `.never` 를 고른 이유 자체는 유효합니다 — 자동 인셋 조정은 §11 이 경계하는 offset drift 의 원인 중 하나입니다.

> ❓ **미결 — signature 에 `chapter` 를 넣을 것인가.**
> §6-5 의 구성요소 목록에는 `chapter` 가 없어, 장이 달라도 같은 signature 가 나옵니다.
> "레이아웃 **형식** 호환성" 판정용이라면 지금이 맞고,
> "이 필사가 **이 장의** 이 레이아웃에서 그려졌다" 를 보장하려면 `chapter` 가 필요합니다.
> 현재 구현은 문서 그대로 `chapter` 를 넣지 않았습니다. §9-3 의 `layoutMismatch` 정책을
> 확정할 때 함께 결정하십시오.

---

## 6. ChapterLayout — 측정과 게이트

### 6-1. LazyVStack → VStack

전 절의 geometry가 있어야 합성이 성립하므로 비지연 `VStack`으로 전환합니다.

> **메모리는 측정 전까지 단정하지 않습니다.** Canvas 개수는 N → 1로 줄지만,
> ① 176개 Row eager 생성 비용 ② 장 전체 높이 `PKCanvasView`의 tile/Metal 리소스가
> 절약분보다 클 수 있습니다.
>
> **S0-4 실측(§18-3)으로 드러난 것:** 현재 구조의 비용은 **진입이 아니라 스크롤에 분산**되어 있습니다.
> 시편 119편 진입은 +37.4MB / CPU 0.31s 로 창세기와 거의 같지만, 전체 스크롤은 +109MB / CPU 24.7s 입니다.
> **VStack 전환은 이 스크롤 비용을 진입 시점으로 옮깁니다.**
> 따라서 통과 기준은 (C)표가 아니라 **(B)표 기준으로 잡아야 합니다.**
> 완화책 — `(chapter, sentenceSetting, writingWidth, isLeftHanded)` 키로 `ChapterLayout` 캐시.

### 6-2. 입력 게이트 (P4)

아래 조건을 모두 만족하기 전에는 **합성·입력·저장을 모두 금지**합니다.

```swift
layout.regions.count == sentences.count
&& layout.totalHeight > 0
&& layout.writingWidth > 0
```

**게이트 구현 — SDK 확인 결과**

`PKCanvasViewDrawingPolicy`는 `.default` / `.anyInput` / `.pencilOnly` **세 가지뿐**입니다
(`PKCanvasView.h:60-66`). 초안의 `.prohibited`는 **존재하지 않는 API**였으므로 다음으로 대체합니다.

```swift
canvas.drawingGestureRecognizer.isEnabled = isLayoutReady   // PKCanvasView.h:87
```

현재 `verseFrameUpdated`는 rect가 하나 들어올 때마다 재합성하여 부분 레이아웃을 정상 상태처럼 취급합니다 — 이를 금지합니다.

### 6-3. 2-pass 높이 계산

**줄 수가 줄어드는** 리플로우에서는 저장된 필사가 텍스트보다 많은 줄을 요구할 수 있습니다.

```
줄 수 감소 조건:  폭 증가 / 폰트 감소 / 자간 감소
줄 수 증가 조건:  폭 감소 / 폰트 증가 / 자간 증가
```

```
Pass 1  텍스트 기준 각 절의 밑줄 개수 / 높이 측정
Pass 2  각 절의 저장된 band 수(N_saved)와 현재 밑줄 수(N_now)를 비교
        N_saved > N_now 이면  extraHeight = (N_saved - N_now) × lineSpace
        effectiveHeight = 텍스트 높이 + extraHeight
        → 레이아웃 재계산
```

> Pass 2는 **band 개수만** 사용하므로 좌표 계산이 필요 없습니다.
> reflow 결과에 레이아웃이 의존하는 순환이 생기지 않습니다.

### 6-4. 로드 순서와 합성 게이트

다음 두 비동기 결과는 **도착 순서가 보장되지 않습니다.**

```
drawingsLoaded    ← DrawingRepository.load(chapter:)
layoutCompleted   ← 전 절 geometry 측정
```

둘 다 State에 보관하고, 양쪽 액션에서 동일한 `composeIfReady`를 호출합니다.

```swift
func canCompose(_ state: State) -> Bool {
    guard let layout = state.layout,
          state.loadedDrawings != nil,
          let expected = state.expectedVerseCount
    else { return false }
    return layout.regions.count == expected
        && layout.totalHeight > 0
        && layout.writingWidth > 0
}
```

**장 전환 시 취소:** 장을 바꾸면 새 `loadRequestID`를 발급하고,
이전 requestID로 도착한 조회 결과와 geometry 이벤트는 **폐기**합니다.
빠른 연속 장 전환에서 이전 장의 Drawing이 새 장에 합성되는 사고를 막습니다.

---

### 6-5. layoutSignature는 영속 가능한 값이어야 함

Swift `Hashable.hashValue`는 **프로세스마다 시드가 달라집니다.** 영속 metadata에 기록하면
앱 재실행 후 값이 달라져 항상 "레이아웃 불일치"로 판정됩니다.

canonical 문자열 인코딩 또는 안정적 digest(SHA256 등)를 사용하고, 다음을 포함합니다.

```
formatVersion
fontFamily.rawValue
fontSize
tracking
lineSpace
writingWidth
layoutDirection   // isLeftHanded
```

---

## 7. 획 소유권과 승계

### 7-1. 소유권 규칙 (P1)

```
신규 획의 첫 control point (canvas 좌표)
    ↓
ChapterLayout.captureRect 검색
    ↓
ownerVerse 결정
    ↓
stroke 전체를 ownerVerse Drawing에 저장 (자르지 않음)
```

**제품 정책으로 명시해야 할 문장:**

> 여러 절을 지나는 획은 **시작한 절에 속하며, 레이아웃 변경 시 시작 절과 함께 이동한다.**

**U1 결정: 시작 절에 stroke 전체 귀속 (확정).**
"4절 영역에 걸친 부분은 반드시 4절과 함께 이동" 요구가 향후 생기면 손실 없는 path 분할(보간 clipping)
또는 chapter-level stroke 모델이 필요하며, 그때는 별도 설계 대상입니다.

> ⚠️ **미결 — 앵커가 캔버스 밖일 때 (rev.11, 구현 중 발견)**
> 첫 control point 가 `captureRect` 어디에도 들어가지 않으면 소유자를 정할 수 없습니다.
> 현재 구현은 **map 에 넣지 않습니다** — "조회 실패 = 소유자 없음" 이며 `0` 같은 대체값을 만들지 않습니다
> ([StrokeOwnershipResolver.swift](../Feature/CarveFeature/Sources/Drawing/StrokeOwnershipResolver.swift)).
>
> **그 결과 소유자 없는 획은 저장에서 빠집니다 — 유실입니다.**
> 손가락이나 펜슬이 캔버스 좌·우 바깥에서 시작해 안으로 들어오는 획이 해당합니다.
> 세로는 첫 절 위/마지막 절 아래가 캔버스 끝까지 확장돼 있어 문제가 없고, **가로가 위험 구간**입니다.
>
> 선택지: ① 가장 가까운 `captureRect` 로 클램프 ② 획 전체의 `renderBounds` 중심으로 재판정
> ③ 소유자 없는 획을 별도 버킷에 보관. **Phase 3 착수 전에 결정해야 합니다.**

### 7-2. 두 종류의 키 — identity와 content signature ★

**하나의 fingerprint로는 안 됩니다.** 용도가 정반대이기 때문입니다.

```swift
/// 같은 논리적 stroke인지 판단한다 — owner 승계용.
/// bitmap 지우개가 바꾸는 mask/maskedPathRanges를 **제외**한다.
struct StrokeIdentityKey: Hashable, Sendable {
    /// PKStroke.randomSeed (iOS 16+, 배포타깃 17이므로 사용 가능)
    let randomSeed: UInt32
    /// PKStrokePath.creationDate
    let creationTime: TimeInterval
    /// PKStrokePath.count
    let pointCount: Int
}

/// 저장 내용이 변경됐는지 판단한다 — dirty 판정용.
/// mask/path/transform/ink를 **포함**한다.
struct StrokeContentSignature: Hashable, Sendable {
    let identity: StrokeIdentityKey
    let pathDigest: String
    let maskDigest: String?
    let transform: CGAffineTransform
    let inkDigest: String
}
```

```
IdentityKey 동일        → 기존 owner 승계        (§7-3)
ContentSignature 변경   → 해당 verse를 dirty 판정 (§8-2)
```

> **⚠️ `StrokeIdentityKey` 는 canvas stroke 엔트리와 1:1이 아닙니다 (S1-2).**
> bitmap 지우개가 만든 조각들은 **같은 IdentityKey 를 공유**합니다.
> 정확히 말하면 이 키는 **"원본 획 → 절"** 의 매핑이지 "canvas 엔트리 → 절" 이 아닙니다.
> 조각들의 owner 값은 서로 같으므로 `[StrokeIdentityKey: Int]` 자체는 안전하지만,
> **다음은 금지합니다.**
>
> - `map.count` 를 stroke 개수로 쓰기
> - map 을 순회해 stroke 를 열거하기
>
> stroke 열거는 **항상 `drawing.strokes` 배열을 순회하고 map 은 조회에만** 씁니다.

> **⚠️ `maskedPathRanges.isEmpty` 로 "마스크 없음" 을 판정하지 마십시오 (S1-5).**
> `mask == nil` 인 stroke 의 `maskedPathRanges` 는 빈 배열이 아니라 **path 전체 구간**(`[0.0...9.0]`)입니다.
> 또한 `mask` 는 지워진 영역이 아니라 **남은(가시) 영역**을 나타내는 clip 입니다.

> **이 분리가 없으면 D7이 재발합니다.**
> mask를 제외한 키 하나로 dirty를 판정하면, bitmap 지우개는 identity를 바꾸지 않으므로
> "owner 승계는 성공했지만 지우기가 저장되지 않는" 상태가 됩니다.

### 7-3. 승계 (reconciliation)

편집 때마다 전량 재판정하면 리플로우 후 소유권이 옆 절로 흘러갑니다. 기존 획은 소유권을 **승계**합니다.

1. `StrokeIdentityKey` 완전 일치 → 기존 owner 승계 ← **S1-2 결과, bitmap 지우개 경로는 여기서 전부 해결됨**
2. `randomSeed` 또는 `creationTime` 일치 + bounds/path 유사도 높음 → 승계
3. 공간적으로 가장 많이 겹치는 owner 승계 ← **fallback.** `.vector` 전환이나 예외 상황용
4. 대응 없음 → 첫 control point의 captureRect로 신규 귀속

> S1-4 실측: 지우개 후에도 `randomSeed` / `creationDate` / `path.count` 는 물론
> **control point 10개의 값까지 전부 불변**이었습니다. 1번 규칙의 신뢰도가 높습니다.

동일 후보가 복수일 때는 **결정적 순서**로 선택합니다.

> **rev.11 정정 — 우선순위는 "면적 → verse" 입니다.**
> 위 문장을 "verse 오름차순 → 겹침 면적 내림차순" 으로 문자 그대로 읽으면 verse 가 1차 키가 되어
> **면적이 무의미해집니다.** 실제로 필요한 것은 **겹침 면적 최대가 1차, 동점일 때 verse 최소**입니다.
> 구현은 절 번호 오름차순으로 훑으며 면적이 더 클 때만 교체하므로 두 표현이 같은 코드로 수렴합니다.

> **rev.11 보강 — 3번 규칙의 "겹침" 은 무엇과의 겹침인가.**
> 원문에 대상이 없습니다. `captureRect` 와의 겹침으로 읽으면 4번(첫 control point → captureRect)과
> 사실상 같아져 fallback 이 무의미해집니다.
> **이전 세대 stroke 의 `renderBounds` 를 owner 별로 모아 비교**하는 것으로 확정합니다.
> 그래서 승계 함수는 이전 `OwnershipSnapshot` 뿐 아니라 **이전 `PKDrawing` 도 함께** 받습니다 —
> map 만으로는 기하를 얻을 수 없고, map 순회는 §7-2 가 금지하기 때문입니다.

> `StrokeIdentityKey`는 공개 API가 보장하는 영구 ID가 **아닙니다.**
> DB에는 이미 절별로 그룹화되어 저장되므로, fingerprint는 **한 편집 세션 안에서 owner를 승계하기 위한 도구**로만 사용합니다.
> 세션이 끊기면 DB의 절별 그룹이 진실이 됩니다.

### 7-4. 지우개 모드 — `.bitmap` 유지로 확정 (U3 해소)

**S1-2 실측 결과: bitmap 지우개는 분할과 마스킹을 동시에 합니다.** 초안의 "자르지 않고 마스킹만" 은 절반만 맞았습니다.

```
BEFORE               strokes = 2
AFTER (중간만 지움)   strokes = 3        ← 획 하나를 지웠는데 엔트리가 +1
  [0] seed=956091164  cd=…7905478  pts=10  mask=(203,6,112,8)  ranges=[5.003…9.0]
  [1] seed=956091164  cd=…7905478  pts=10  mask=( 51,5,112,8)  ranges=[0.0…3.663]
  [2] seed=491497907  cd=…1357799  pts=10  mask=nil            ranges=[0.0…9.0]
```

두 조각은 `path` 의 **control point 10개 값까지 원본과 완전히 동일**합니다.
path 를 잘라 나눠 갖는 것이 아니라, **같은 path 를 공유하는 엔트리가 복제되고
`mask` / `maskedPathRanges` / `renderBounds` 만 달라집니다.** `drawing.bounds` 도 변하지 않습니다.

```
PKStroke.mask              "The mask pre-transform that is used to clip the rendering of the stroke."
PKStroke.maskedPathRanges  "parametric parameter ranges of points in strokePath
                            that intersect the stroke's mask."
```

**결론은 오히려 강화됩니다.** 조각 전부가 원본과 **같은 `StrokeIdentityKey`** 를 가지므로
§7-3 **1번 규칙(IdentityKey 완전 일치)만으로 모든 조각이 원본 owner 를 승계**합니다.
공간 겹침 매칭(3번 규칙)은 bitmap 경로에서 **필요하지 않습니다.**

`.bitmap` 유지 확정.

`.vector` 전환은 "부분 지우기" UX를 바꾸며, **단일 Canvas 전환과 함께 바꾸면 회귀 원인 분리가 어려워집니다.**
따라서 초기 구현은 `.bitmap`을 유지하고, Phase 0A의 reconciliation spike에서
승계가 실제로 불가능한 것으로 판명될 때만 별도 제품 변경으로 검토합니다.

### 7-5. "빈 절" 판정과 저장 가드 — S1-3에서 전제가 뒤집힘 ★

**초안의 전제는 틀렸습니다.**

> ❌ (초안) "완전히 마스킹된 획도 `drawing.strokes` 에는 남아 있습니다"

S1-3 실측 결과, `PKEraserTool(.bitmap)` 로 획을 **완전히** 지우면 그 stroke 는
`drawing.strokes` 에서 **제거됩니다.**

```
AFTER_FULL   strokes = 2      ← seed=491497907 (획 B) 가 통째로 사라짐
             남은 stroke 중 renderBounds 가 빈 것은 하나도 없음
```

따라서 `strokes.isEmpty` 는 **정상 동작하며**, 초안이 제안한 `isFullyMasked` 헬퍼는
bitmap 경로에서 **필요 없습니다.**

#### 그러나 초안이 지목한 증상은 실재합니다 — 원인이 정반대입니다

재현: 마지막 획을 지우고 앱을 재기동하면 **지운 획이 되살아납니다.**
(DB `length(ZLINEDATA)` 가 그대로 유지됨을 sqlite 로 확인)

> 아래 위치·행 번호는 **수정 전(rev.8 시점) 코드 기준**입니다. 현재 코드는 아래 "✅ 분리 수정 완료" 절을 보십시오.

| # | 위치 | 문제 |
|---|---|---|
| 1 | [CarveDetailFeature.swift](../Feature/CarveFeature/Sources/Presentation/Carve/CarveDetail/CarveDetailFeature.swift) (당시 206행) | `guard ... containsPKStroke == true else { return }` — 마지막 획을 지워 `strokes` 가 비면 **저장 자체를 건너뜀** |
| 2 | [CanvasView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CanvasView.swift) (당시 66-72행) | `guard now.timeIntervalSince(lastUpdate) > 0.3 else { return }` 는 **leading-edge throttle** — 제스처의 마지막 변경이 유실됨 (debounce 가 아님) |

#### 새 설계에서는 두 원인이 구조적으로 제거됩니다

- **§8-1** 편집 종료 시점(pencil-up) 저장이 throttle 을 대체
- **§8-2** dirty 집합 → `.clear` mutation 이 저장 가드를 대체 (P7)

즉 P7("빈 결과도 mutation이다")은 **판정식 문제가 아니라 저장 가드 문제**를 푸는 원칙입니다.

> ⚠️ 단, "편집 종료 시점" 을 `canvasViewDidEndUsingTool` 로 구현하면 **안 됩니다.** 아래 실측 참조.

#### 그래도 방어적으로 유지할 것

- **`renderBounds` 기반 가시성 검사** — `.vector` 지우개나 향후 OS 버전에서 동작이 달라질 수 있습니다.
  실측에서 `renderBounds` 가 가시 영역만 반영함이 확인됐습니다(264pt → 112pt).
- **`maskedPathRanges.isEmpty` 로 마스크 유무를 판정하지 말 것** (§7-2 주의 참조)

#### ✅ 분리 수정 완료 — `7ba5bc46` (rev.9)

> rev.8은 "이 버그는 현재 프로덕션에 존재하며, 단일 Canvas 전환(Phase 3)을 기다릴 필요가 없다. 별도 수정 대상으로 분리한다"고 적었습니다.
> **그 분리 수정이 실제로 수행됐습니다.** 위 표의 두 원인을 **기존 N-Canvas 구조 위에서** 고쳤습니다. 상세는 §20-2.

| # | 원인 | 조치 |
|---|---|---|
| 1 | 저장 가드 | 저장 경로를 [CarveDetailFeature.persistDrawing(_:)](../Feature/CarveFeature/Sources/Presentation/Carve/CarveDetail/CarveDetailFeature.swift) 로 분리하고 **획 유무 조건을 제거**. `setSentence`의 대표 drawing 선택에서도 같은 필터를 제거 (남아 있으면 "전부 지운 최신 기록"이 후보에서 빠져 더 오래된 기록이 대표로 승격됨) |
| 2 | leading-edge throttle | throttle은 그대로 두고 그 옆에 **trailing-edge debounce**를 추가해 제스처의 **마지막** 변경을 반드시 저장 ([CanvasView.swift:93](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CanvasView.swift)) |
| 3 | (부수) | trailing 저장이 생기면서 필사하지 않은 절까지 빈 레코드가 생기는 것이 관측되어, [CanvasFeature.swift:60](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CanvasFeature.swift) 에서 **기록이 없는 절 + 빈 canvas** 조합은 새 행을 만들지 않도록 함 |

**`containsPKStroke` 의 의미 자체는 바꾸지 않았습니다.**
`"stroke 가 있는가"` 라는 뜻은 그 자체로 옳고, 무엇보다
[DrawingDataMigrationPlan.swift:40](../Domain/Domain/Sources/SwiftData/DrawingDataMigrationPlan.swift) 의 **V1→V2 마이그레이션이
빈 레거시 레코드를 삭제하는 판단에 같은 의미를 그대로 쓰고 있습니다.**
의미를 "가시 획" 으로 바꾸면 마이그레이션 동작이 조용히 달라지므로, **호출부만** 고쳤습니다.
(비활성 상태인 `CombinedCanvasFeature` 의 호출부는 손대지 않았습니다.)

**`canvasViewDidEndUsingTool` 은 최종 저장 지점으로 쓸 수 없습니다 — 실측 확인.**
PencilKit이 획을 `drawing` 에 반영하기 **전에** 호출되어 **빈 drawing 이 저장됩니다**(시뮬레이터 확인).
그래서 pencil-up 델리게이트가 아니라 trailing-edge debounce 를 택했습니다.
이는 §8-1의 `editEnded` 계약을 구현할 때도 그대로 유효한 제약입니다 — **`canvasViewDidEndUsingTool` 을 편집 종료 저장 지점으로 삼으면 안 됩니다.**

#### Phase 3에서 이 수정이 흡수되는 방식

이번 수정은 기존 구조 위의 국소 처방이며, 새 설계가 두 축을 각각 **대체**합니다.

| 지금 (N-Canvas, `7ba5bc46`) | Phase 3 대체 | 근거 |
|---|---|---|
| trailing-edge debounce 로 마지막 변경 보장 | **§8-1** 편집 종료(`editEnded`) 계약에 의한 저장 | 시간 기반 추측이 아니라 편집 경계가 명시됨 |
| 저장 가드 제거 + stroke 0개도 그대로 저장 | **§8-2** dirty 집합 → `.clear` mutation (P7) | "빈 결과도 mutation" 을 판정이 아니라 명령으로 표현 |
| `strokes.isEmpty` 로 신규 행 생성 억제 | **§8-7** `activeRowIDs` + rowID 선발급 | 행 생성 시점이 편집 계약에 종속됨 |

→ Phase 3 도입 시 debounce 와 `strokes.isEmpty` 가드는 **삭제 대상**입니다.

---

## 8. 저장

### 8-1. 편집 계약 (begin / end)

```
Pencil down / undo·redo 시작
  → editBegan(CanvasEditBeginSnapshot)
      revision   = editRevision + 1
      drawingData, ownership   ← before 상태
      startPoint ← pencil-down 좌표 (undo/redo면 nil)
  → isEditing = true

Pencil up / undo·redo 완료
  → editEnded / historyEditEnded(CanvasEditSnapshot(revision:...))
  → isEditing = false, pendingLayout 적용
```

before ownership이 없으면 reconcile과 dirty 판정이 성립하지 않으므로 **`editBegan`은 필수**입니다.

### 8-2. mutation 계산 (P7)

```swift
// ✅ 편집 전/후 절 집합의 합집합에서 dirty를 구한다
let versesBefore = Set(ownersBefore.map.values)
let versesAfter  = Set(ownersAfter.map.values)

// dirty 판정은 IdentityKey가 아니라 **ContentSignature** 집합으로 비교한다 (§7-2)
// mask만 바뀐 bitmap 지우개를 놓치지 않기 위함
let dirty = versesBefore.union(versesAfter)
    .filter { verse in
        signatureSet(verse, ownersBefore) != signatureSet(verse, ownersAfter)
    }

let mutations: [VerseDrawingMutation] = dirty.map { verse in
    let strokes = strokeGroup(verse, ownersAfter)
    let data = localized(strokes, origin: layout.region(verse).storageOrigin)
    let meta = metadata(from: layout, verse: verse)

    // 활성 행이 없으면 rowID를 **먼저 발급하고 예약**한다 (§8-7)
    guard let rowID = state.activeRowIDs[verse] else {
        let newID = BibleDrawingRowID(raw: UUID().uuidString)
        state.activeRowIDs[verse] = newID          // 즉시 예약 — 다음 편집은 같은 행으로
        return .create(verse: verse, rowID: newID, data: data, metadata: meta)
    }
    // S1-3: 완전히 지운 stroke 는 실제로 제거되므로 strokes.isEmpty 로 충분하지만,
    // .vector 지우개/OS 변경 대비로 renderBounds 가시성까지 확인한다 (§7-5)
    guard hasVisibleStroke(strokes) else { return .clear(verse: verse, rowID: rowID) }
    return .replace(verse: verse, rowID: rowID, data: data, metadata: meta)
}
```

**저장 변환은 평행이동뿐입니다.** clipping이 없으므로 저장→복원→저장이 구조적으로 동일합니다.

### 8-3. 직렬화와 coalescing (P11, D9)

연속 편집의 저장 effect가 경쟁하면 최신 편집이 과거 편집에 덮일 수 있습니다.

**핵심 성질:** `replace`는 해당 절의 **완전한** 획 집합을 담습니다(delta가 아님).
따라서 같은 절에 대한 나중 mutation이 이전 것을 **완전히 대체**합니다.

```swift
// pendingMutations: [BibleDrawingRowID: PendingDrawingMutation] — rowID 키, last-wins
// create / replace / clear 세 케이스 모두 non-optional rowID를 가지므로 단일 큐로 처리된다
for m in newMutations {
    state.pendingMutations[m.rowID] = PendingDrawingMutation(
        revision: revision,
        mutation: m
    )
}
```

> **verse가 아니라 rowID로 키를 잡는 이유:** 히스토리 복원으로 활성 행이 바뀌면
> 아직 저장되지 않은 이전 행의 mutation이 verse 키에 덮여 유실됩니다.
> (그 위험을 이중으로 막기 위해 복원 직전 flush도 수행합니다 — §8-7)

이 coalescing만으로 같은 행의 순서 문제가 소멸합니다. 그 위에 다음을 적용합니다.

```
1. 저장은 동시에 하나만 (saveStatus == .saving 이면 큐에 쌓기만)
2. 현재 pendingMutations의 **복사본**을 batch로 캡처
3. 저장 중 도착한 새 mutation은 pendingMutations에 계속 기록 (revision 갱신)
4. batch 성공
5. pending[rowID].revision == batch[rowID].revision 인 항목만 제거
   → 더 최신 revision이면 남겨두고 다음 batch에서 저장
6. 실패: 항목 전부 유지 + saveStatus = .failed(retryCount:) → 다음 편집/flush에서 재시도
```

> **5번이 없으면 저장 중 도착한 최신 편집이 성공 콜백에 의해 삭제됩니다.**

미저장 여부의 판정 기준은 `persistedRevision`이 아니라 다음입니다.

```swift
var isFullyPersisted: Bool {
    pendingMutations.isEmpty && saveStatus == .idle
}
```

### 8-4. 실패 정책 — 화면은 되돌리지 않음

초안의 "성공 후에만 Feature 상태 확정"은 철회합니다.
Canvas에는 이미 획이 표시됐으므로 저장 실패로 화면을 과거로 되돌리는 것은 부자연스럽습니다.

```
편집 결과는 즉시 화면 상태로 확정
  ↓ 저장 시도
성공 → persistedRevision 갱신
실패 → 화면 유지 + pendingMutations 보존 + 재시도
```

undo stack은 저장 실패의 영향을 받지 않습니다(§9-5).

### 8-5. flush — 미저장 잉크 소실 방지

"화면 유지 + 재시도"만으로는 장 전환이나 앱 종료 시 잉크가 소실됩니다.

**장 전환은 요청/승인 흐름이어야 합니다.** `flushPending`을 보내는 것만으로는 장 변경을 막을 수 없습니다.

```
사용자가 다음 장 선택
  → requestChapterChange(destination)      ← 부모 Feature가 즉시 전환하지 않음
  → 현재 Canvas flush
  → 성공: Header/장 상태 변경 + 새 fetch
  → 실패: 현재 장 유지 + 오류 표시 + 재시도 / 사용자 확인 후 강행
```

- flush 실패 시 `AnalyticsClient.trackErrorShown` 기록 + 사용자 알림
  (기존 `DrawingDatabase`의 에러 트래킹 패턴 재사용)
- **background 진입은 best-effort입니다.** OS가 종료 시간을 보장하지 않습니다.
  실제 안전성은 **pencil-up마다 직렬 저장하는 기본 경로**에서 확보해야 하며,
  flush는 보조 수단입니다.
- 재시도가 계속 실패하면 사용자를 무한히 붙잡지 않도록 "계속 진행 / 취소" 선택을 제공합니다.

### 8-6. 원자적 batch (P8)

```swift
protocol DrawingRepository: Sendable {
    func load(chapter: BibleChapter) async throws -> [VerseDrawingSnapshot]
    func apply(_ mutations: [VerseDrawingMutation],
               chapter: BibleChapter) async throws   // 전부 성공 또는 전부 실패
}
```

**구현 지점:** `SwiftDatabaseActor.insert`/`update`가 각각 `save()`를 호출합니다([SwiftDatabaseActor.swift:44](../Domain/Domain/Sources/SwiftData/SwiftDatabaseActor.swift)).
변경을 모아 **마지막에 `save()` 1회**로 바꾸면 `ModelContext` 단위 트랜잭션이 성립합니다.
기존 `updateDrawings(requests:)`의 per-item 에러 삼킴을 제거하고 `async throws`로 전환합니다.

> **한계 — 로컬 원자성 ≠ CloudKit 원자성.**
> 로컬 트랜잭션이 절 3개를 한 번에 커밋해도, CloudKit에는 **CKRecord 3개로 개별 동기화**됩니다.
> 다른 기기가 일부만 먼저 받아 일시적으로 찢어진 상태를 볼 수 있습니다.
> 장 단위 단일 레코드로 바꾸지 않는 한 해결할 수 없으므로, **알려진 한계로 문서화**합니다.

### 8-7. 히스토리와 행 주소지정 (U2 결정: 기존 다중 행·히스토리 유지)

한 절은 여러 `BibleDrawing` 행(필사 회차)을 가질 수 있고, `isPresent`로 대표를 표시합니다.
단일 Canvas는 절마다 **대표 행 하나**만 합성합니다.

#### 활성 행 (activeRowIDs)

```
load:  절별 mainDrawing() → activeRowIDs[verse] = 그 행의 rowID
edit:  activeRowIDs[verse] 행에만 replace / clear
```

#### `clear`는 행을 삭제하지 않는다 ★

```
❌ 행 삭제  →  mainDrawing()이 과거 회차를 승격  →  지운 획이 되살아남
✅ 행 유지 + lineData 비움 + updateDate 갱신
```

빈 행은 **히스토리 목록에서만 숨깁니다**(가시 획 없음 기준, §7-5). 행 자체는 남깁니다.

#### 히스토리 복원 흐름

```
사용자가 회차 선택
  ↓ ① pendingMutations flush  (이전 활성 행의 미저장 변경 보존)
  ↓ ② updatePresentDrawing(chapter:verse:presentID:)  — isPresent 이전
  ↓ ③ verseRowRestored(verse:rowID:)
        · 해당 절의 기존 stroke 제거 후 복원 행을 verse rect에 합성
        · ownership 맵 갱신
        · activeRowIDs[verse] 갱신
        · undo stack clear (§9-5)
  ↓ ④ mutation 생성 없음 — DB에 이미 존재하는 내용이므로
```

#### 신규 행의 rowID는 저장 전에 발급한다 ★

`.create`에 rowID가 없으면 pending 큐(rowID 키)에 들어갈 수 없어,
빈 절에 빠르게 두 번 그으면 **행이 두 개 생깁니다.**

```
첫 편집
  → UUID 기반 rowID 발급
  → activeRowIDs[verse] 에 즉시 예약          ← 저장 완료를 기다리지 않음
  → .create 를 pendingMutations[rowID] 에 기록
후속 편집
  → 같은 rowID 의 create 내용을 교체 (coalescing)
Repository
  → 해당 rowID 를 upsert
```

이렇게 하면 create와 replace를 별도 큐로 나눌 필요가 없습니다.
저장이 영구 실패해도 `activeRowIDs`가 DB에 없는 행을 가리킬 뿐이며,
재로드 시 `mainDrawing()` 기준으로 다시 구성되므로 정합성 문제는 없습니다.

#### 새 회차 행 생성 규칙

현재 동작을 유지합니다: **해당 절에 행이 하나도 없을 때만** 생성.
편집만으로 회차가 자동 증가하지는 않습니다.

> "새 필사 시작" 같은 명시적 회차 생성 트리거는 **별도 제품 기능**이며 이 설계 범위 밖입니다.
> 현재 히스토리에 행이 거의 쌓이지 않는 것도 이 규칙 때문입니다.

#### `mainDrawing()`을 결정적으로 만들 것

```swift
// 현재: first(where: isPresent) → 배열 순서 의존
// fetch(chapter:)는 verse 기준으로만 정렬하므로 그룹 내 순서가 보장되지 않음
```

CloudKit 충돌로 `isPresent == true` 행이 복수 존재할 수 있으므로 다음으로 고정합니다.

```
1) isPresent == true 인 행들 중 updateDate 최신
2) 동률이면 rowID 사전순
3) isPresent 행이 없으면 updateDate 최신 → 동률이면 rowID 사전순
```

#### 행 식별자 정책 — 신규는 UUID, legacy는 비파괴

`BibleDrawing.id = "\(title).\(chapter).\(verse).\(Int(timestamp))"` 는 **초 단위**라
두 기기가 같은 초에 같은 절의 행을 만들면 충돌할 수 있습니다.

초안의 "legacy 행 최초 접근 시 lazy UUID 할당"은 **철회합니다.**
두 기기가 서로 다른 UUID를 부여할 수 있고, 단순 조회가 쓰기를 유발해 비파괴 원칙을 깹니다.

| 대상 | 정책 |
|---|---|
| **신규 V4 행** | 생성 **전에** UUID 발급 (§8-7 선발급과 동일한 값) → `rowUUID`에 기록 |
| **기존 legacy 행** | 기존 business `id`를 그대로 row key로 사용. **쓰기 갱신 없음** |
| 실제 중복이 관측된 경우 | 그때만 별도 repair 경로 실행 |

즉 `rowUUID`는 신규 데이터부터 확실히 적용하고, legacy는 건드리지 않습니다.

#### `drawing.id` 표현 금지 — S0-3에서 확정 ★

**S0-3 probe로 확정된 사실:**

> `drawing.id` 는 **문맥 의존 오버로드**다.
> 기대 타입이 없으면 `BibleDrawing` 자신의 저장 프로퍼티 `String!` 로,
> 기대 타입이 `PersistentIdentifier` 이면 `PersistentModel` extension 의 `id`(= `persistentModelID`)로 해석된다.
> 즉 [DrawingDatabase.swift:227](../Domain/Domain/Sources/SwiftData/DrawingDatabase.swift)의
> `actor.update(drawing.id)` 와 234행의 `drawing.id ?? ""` 는 **서로 다른 값을 가리킨다.**

검증: `let probeA: PersistentIdentifier = drawing.id` 와 `let probeB: String? = drawing.id` 가
**둘 다 컴파일**되고, `let probeC = drawing.id; let probeE: PersistentIdentifier = probeC` 는
`cannot convert value of type 'String?'` 로 실패했습니다.

**따라서 새 설계에서는 `drawing.id` 표현을 쓰지 않습니다.**

| 의도 | 사용할 표현 |
|---|---|
| SwiftData 행 참조 | `drawing.persistentModelID` (명시) |
| 도메인 문자열 키 | 별도 이름 (예: `drawing.rowKey`) |

> 지금은 리팩터링 중 한쪽 의미가 다른 쪽으로 미끄러져도 **컴파일러가 잡아주지 않습니다.**
> 과거 두 번의 롤백을 만든 유형의 함정이므로 Phase 3 Repository 전환에서 이름을 분리합니다.

---

### 8-8. 전체 흐름

```
editBegan (before drawing + ownership 확보)
  ↓ 편집
editEnded(revision)
  ↓ 화면 즉시 확정 (editRevision = revision)
  ↓ reconcile → whole stroke owner 확정
  ↓ dirty verse 집합 (before ∪ after)
  ↓ 활성 행(activeRowIDs[verse]) 확인
  ↓ 가시 획 있음 → replace(rowID) / 없음 → clear(rowID) / 행 없음 → create
  ↓ pendingMutations 에 rowID 키로 coalescing
  ↓ 단일 SwiftData transaction
성공 → persistedRevision = revision
실패 → 화면 유지 + 큐 보존 + 재시도
```

---

## 9. 복원과 reflow (G4)

### 9-1. 핵심 불변식

보존해야 할 것은 획의 절대 Y가 아니라 다음입니다.

```
verse + underline index + 해당 underline으로부터의 상대 offset
```

### 9-2. line band reflow

```
저장 stroke
  → 저장 당시 metadata의 baseUnderlineAnchors 로 band(줄) 판정
  → 현재 layout의 같은 index underline 으로 translate
  → 폭이 줄었을 때만 uniform 축소 (scale = min(1, now / base))
```

**왜 균등 세로 스케일이 아닌가** — 폰트를 키우면 같은 폭에서 줄 수가 **늘어납니다.**

```
저장 당시 (fontSize 20, 3줄)      폰트 확대 (fontSize 28 → 4줄)

──── 사랑하사 ────                균등 스케일        줄 재앵커
──── 독생자를 ────                ─ 사 랑 하 사 ─    ──── 사랑하사 ────
──── 주셨으니 ────                ─ 독 생 자 를 ─    ──── 독생자를 ────
                                  ─ 주 셨 으 니 ─    ──── 주셨으니 ────
                                                     ──── (빈 줄)  ────
                                  ↑ 절 높이에 맞춰    ↑ 글씨 크기 유지,
                                    세로로 늘어나       각 줄이 밑줄에 정렬
                                    밑줄과 어긋남
```

> **✅ rev.12 부수 확인 — reflow 는 `StrokeIdentityKey` 를 깨뜨리지 않습니다.**
> `PKDrawing.transformed(using:)` 이 `randomSeed` / `path.creationDate` / `path.count` 를
> **전부 보존**함을 실사용 fixture 5건으로 확인했습니다 (§20-3 의 blob 재사용).
> 즉 reflow 를 거친 drawing 도 §7-2 의 `StrokeIdentityKey` 가 그대로이므로
> **§7-3 의 1번 규칙(IdentityKey 완전 일치)에 의한 owner 승계가 살아남습니다.**
> reflow 후 첫 편집에서 소유권이 옆 절로 흘러가지 않는 근거가 이것입니다.
> (구현: [LineBandReflow.swift](../Feature/CarveFeature/Sources/Drawing/LineBandReflow.swift))

### 9-3. 정책 표

| 상황 | 원인 | 처리 |
|---|---|---|
| 밑줄 수·줄 구성 동일 | — | 밑줄별 분류 후 새 y로 translate |
| writing width 감소 | 폭 축소 | 종횡비 유지 uniform 축소 |
| writing width 증가 | 폭 확대 | **확대하지 않음.** 원래 크기 유지 |
| 줄 수 증가 | 폭 감소 / 폰트 증가 / 자간 증가 | 남는 밑줄은 빈 줄 |
| 줄 수 감소 | 폭 증가 / 폰트 감소 / 자간 감소 | 초과 band는 마지막 간격 연장 + §6-3의 effectiveHeight로 공간 확보 (**"마지막 간격" 정의는 아래 4번**) |
| 줄바꿈만 달라짐 | — | `textLineRanges`가 있으면 문자 범위 겹침이 가장 큰 밑줄로 이동 (**rev.12: 미구현 — 아래 참조**) |
| 매핑할 줄 없음 | — | **첫 밑줄 기준으로 보존** + `layoutMismatch` 기록. 임의로 다른 줄에 합치지 않음 (§9-3-1). **성립 조건은 아래 1번** |
| metadata 없음 (legacy) | — | 무변환 (§10-2). **출력 좌표계는 아래 3번** |

> **rev.12 — "줄바꿈만 달라짐" 은 구현하지 않았습니다.**
> 현재 줄의 문자 범위(`Input.currentTextLineRanges`)는 `Text.Layout.Run.characterIndices` **실측**이 있어야
> 채울 수 있고, 그 통로는 Phase 2 의 측정 경로에 달려 있습니다.
> 자리만 남기고 **읽지 않습니다.** 임의 구현하면 §9-3-1 로 가야 할 절이 조용히 잘못된 줄에 앉습니다.

> **✅ S2 확정: `textLineRanges` 는 실현 가능합니다. fallback 불필요.**
>
> `Text.Layout.Line` 자체에는 문자 범위가 없지만, `Line` 은 `Run` 의 Collection 이고
> **`Text.Layout.Run.characterIndices: [Text.Layout.CharacterIndex]`** (iOS 17.0+) 가 줄별 문자 인덱스를 노출합니다.
> `CharacterIndex` 는 `Strideable(Stride == Int)` 이므로 `distance(to:)` 로 **정수 offset 범위**를 만들어 영속화할 수 있습니다.
>
> ```
> Text.LayoutKey.Value = [Text.LayoutKey.AnchoredLayout]
>   AnchoredLayout { origin: Anchor<CGPoint>, layout: Text.Layout }
>     Text.Layout : Collection of Line
>       Line { origin, typographicBounds } : Collection of Run
>         Run  { characterIndices, typographicBounds, layoutDirection }
> ```
>
> 런타임 확인(창세기 1:2, 46자, 폭 180pt): 4줄 → `[0...12, 13...25, 26...39, 40...45]`
> — 빈틈·겹침 없이 전체를 분할.
> **배포 타깃 iOS 17.0 에서 그대로 사용 가능하며 `@available` 분기가 필요 없습니다.**
>
> ⚠️ 미확정: `CharacterIndex` 의 단위가 Character 기반인지 UTF-16 기반인지.
> 검증에 쓴 한글 46자는 `String.count == utf16.count` 라 구분되지 않았습니다.
> 성경 본문에 이모지·결합 문자가 없어 실사용 리스크는 낮으나, 구현 시 한 번 확인하십시오.

### 9-3-1. `layoutMismatch` — 매핑 실패 시의 확정 동작

저장된 band를 현재 밑줄에 대응시킬 수 없는 경우(줄 구성이 크게 달라졌고 `textLineRanges`도 없음)
**둘 중 하나를 고르는 것이 아니라 둘 다 수행합니다.**

```
1. 표시   절 Drawing 전체를 첫 밑줄 기준으로 보존해 배치한다
          (임의로 다른 줄에 합치거나 분산시키지 않는다)
2. 기록   해당 절을 layoutMismatch 로 표시한다
3. 저장   사용자가 그 절을 실제로 편집하기 전까지 자동 저장하지 않는다  ← P10
```

`layoutMismatch`는 **표시 상태이지 저장 상태가 아닙니다.**
`State.layoutMismatchVerses`(§4)에만 존재하며 DB에 기록하지 않습니다.

용도:

- 디버그 오버레이에서 해당 절을 표시 (Phase 2)
- 필요 시 사용자에게 "이 절의 필사 위치가 정확하지 않을 수 있습니다" 안내
- 그 절에 첫 편집이 발생하면 새 레이아웃 기준으로 저장되며 mismatch가 해소됨

> 원본을 건드리지 않으므로, 설정을 되돌리면 원래 배치로 복귀합니다.

#### 구현에서 확정한 명세 공백 4건 ★ (rev.12 — `565dfe69`)

§9-3 / §9-3-1 을 코드로 옮기면서 **문서가 답을 주지 않는 지점 4곳**이 드러났습니다.
전부 확정하며, 근거를 함께 남깁니다 ([LineBandReflow.swift](../Feature/CarveFeature/Sources/Drawing/LineBandReflow.swift)).

**1. "매핑할 줄 없음" 의 조건이 없었습니다 → 다음 셋으로 확정합니다.**

| # | 조건 | 이유 |
|---|---|---|
| ① | 저장 band 가 0개 (`baseUnderlineAnchors` 가 비어 있음) | band 판정 기준 자체가 없음 |
| ② | 현재 밑줄이 0개 | 옮겨 앉을 줄이 없음 |
| ③ | 줄 수가 **줄었는데** 마지막 간격이 0 이하 | 아래 참조 |

> ③ 을 그냥 진행하면 초과 band 가 **전부 같은 y 에 겹쳐 쌓입니다.**
> 그것은 §9-3-1 의 **"임의로 다른 줄에 합치거나 분산시키지 않는다"** 를 정확히 위반하는 결과입니다.
> 그래서 "겹쳐 쌓기" 대신 **`layoutMismatch` 로 포기하는 것**이 규정에 맞습니다.

**2. §9-3-1 에 uniform 축소를 적용할지가 불명확했습니다 → 적용합니다.**

`layoutMismatch` 로 빠진 절에도 `scale = min(1, now / base)` 를 그대로 적용합니다.

- 축소는 **절 안의 상대 배치를 바꾸지 않습니다.** 무엇이 어느 줄에 앉는지의 문제와 직교합니다.
- 적용하지 않으면 폭이 줄었을 때 **잉크가 좁아진 컬럼 밖으로 샙니다.** 표시가 더 나빠집니다.

**3. "legacy 무변환" 의 출력 좌표계가 불명확했습니다 → 좌표를 전혀 건드리지 않습니다.**

결과에 `legacyPassthrough` 표시를 달고 **입력 좌표를 그대로** 내보냅니다.

> ⚠️ **따라서 장 단위 합성에서 legacy 절의 위치는 보장되지 않습니다.**
> 다른 절은 캔버스 절대좌표인데 legacy 절만 절 로컬(또는 절대) 좌표이므로 **좌표계가 섞입니다.**
> 임의 배치를 지어내지 않은 것은 §10-2-1 때문입니다 — 휴리스틱으로 좌표계를 추측하면
> 실데이터의 71% 에서 틀립니다.
> **→ Phase 3 의 런타임 legacy 판별(§10-2 의 3번)이 이 절들의 합성보다 반드시 먼저 와야 합니다.**

**4. "마지막 간격" 이 밑줄 1개일 때 정의되지 않았습니다 → `writingRect` 상단 ~ 첫 밑줄 거리를 한 줄 높이로 봅니다.**

```
current.count >= 2 → lastGap = current[n-1] − current[n-2]
current.count == 1 → lastGap = current[0] − writingRect.minY
```

밑줄이 하나뿐이면 잴 간격이 없지만, 그 절의 "한 줄 높이" 는
**writingRect 상단부터 첫 밑줄까지** 로 이미 화면에 존재합니다. 새 상수를 만들 필요가 없습니다.
이렇게 얻은 `lastGap` 이 0 이하이면 위 1번의 ③ 으로 넘어갑니다.

---

### 9-3-2. 부수 이득 — 밑줄 offset 정밀화

`Text.Layout.Line.typographicBounds` 가 `ascent` / `descent` / `leading` / `rect` 를 직접 제공합니다(S2 확인).

현재 `VerseTextFeature.makeUnderlineOffsets` 는 `UIFont.descender` 로 **근사**하고 있습니다
([VerseTextFeature.swift:83-89](../Feature/CarveFeature/Sources/Presentation/Carve/Verse/VerseTextFeature.swift)).
이를 레이아웃 **실측값**으로 대체할 수 있습니다.

> 밑줄 위치는 `baseUnderlineAnchors` 로 영속화되어 reflow 의 기준이 되므로(§10-1),
> 근사 오차가 저장 데이터에 그대로 굳습니다. **Phase 2에서 함께 교체하는 것을 권합니다.**

---

### 9-4. 비파괴 원칙 (P10)

> reflow는 **표시 시점에만** 적용하고 저장하지 않습니다.
> 사용자가 그 절에 실제로 획을 추가/삭제할 때만 새 레이아웃 기준으로 저장합니다.
>
> → 설정 화면에서 폰트를 이리저리 바꿔보는 것만으로는 **원본이 훼손되지 않습니다.**

### 9-5. undo 정책

레이아웃 변경 후 `canvas.drawing`을 programmatic replacement하면 native undo stack의 기준이 어긋납니다.

| 상황 | undo stack |
|---|---|
| 같은 레이아웃 안의 필기·지우기 | **native undo 대상** |
| 장 변경 | **clear** |
| 설정/폭 변경으로 reflow 적용 | **clear** |
| 히스토리에서 다른 회차 복원 | **clear** (programmatic 교체이므로 native stack과 기준이 어긋남) |
| 저장 실패 | **변경 없음** |

---

## 10. 스키마 V4와 레거시

### 10-1. V4 — additive only

```swift
public enum DrawingSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    @Model final class BibleDrawing {
        // ... 기존 필드 전부 유지

        /// 좌표 형식의 단일 진실 (기존 죽은 필드를 실제로 사용)
        ///   nil / 1 = legacy, 좌표 형식 미확정
        ///   2       = verse local, verse top-left anchor
        ///   3       = verse local, underline anchor + layout metadata
        var drawingVersion: Int?

        /// DrawingLayoutMetadata Codable blob (drawingVersion == 3 일 때 존재)
        @Attribute(.externalStorage)
        var layoutMetadataData: Data?

        /// 행 식별자 (§8-7). **신규 행 생성 시에만** 발급.
        /// legacy 행은 nil로 두고 business id를 key로 사용한다 (비파괴)
        var rowUUID: String?
    }
}
```

```swift
struct DrawingLayoutMetadata: Codable, Sendable, Equatable {
    /// 이 blob 자체의 스키마 버전. 좌표 형식은 drawingVersion 이 단일 진실이므로 중복하지 않는다
    let metadataSchemaVersion: Int
    let baseWritingWidth: CGFloat
    let baseWritingHeight: CGFloat
    /// 첫 밑줄 기준 상대 y (첫 값은 0)
    let baseUnderlineAnchors: [CGFloat]
    /// Text.Layout이 노출하지 않으면 nil
    let textLineRanges: [Range<Int>]?
    /// §6-5의 안정적 signature (hashValue 금지)
    let layoutSignature: String
}
```

- 새 필드는 **전부 optional** (CloudKit 요구). lightweight migration으로 처리 가능합니다.
- 문자열 `coordinateSpace` 대신 **기존 `drawingVersion` Int**를 사용합니다.
- **좌표 버전은 `drawingVersion` 한 곳에만 둡니다.** DTO·metadata에 중복 저장하지 않습니다.

### 10-2. 레거시 판별은 migration에서 할 수 없다 ★

`normalizedForVerseRect`는 **현재 verse rect가 있어야** 동작합니다.
SwiftData schema migration 시점에는 SwiftUI 레이아웃도 Canvas rect도 존재하지 않으므로,
**V4 migration에서 tolerance 휴리스틱을 실행할 수 없습니다.**

**런타임 lazy 처리 정책:**

1. V3 → V4는 **optional 필드 추가만**. 데이터 변환 금지
2. 기존 record는 `drawingVersion == nil || == 1` → legacy로 둠
3. `ChapterLayout`이 완성된 **런타임 이후**에 판별 (이 시점에는 verse rect가 있음)
4. 판별 결과로 **표시만** 함. 원본 자동 덮어쓰기 금지
5. 해당 절을 **처음 편집할 때만** `drawingVersion = 3` + metadata로 저장
6. 절대/로컬이 확실하지 않은 절은 복구 로그 / 사용자 확인 대상으로 유지
7. Drawing bounds를 저장 당시 Canvas width로 **추정해서 확대하지 않음**

> **CloudKit 주의:** 메타데이터 없는 행은 마이그레이션 이후에도 다른 기기에서 계속 도착할 수 있습니다.
> 판별은 일회성 배치가 아니라 **"legacy 행을 만날 때마다 수행하는 런타임 경로"** 여야 합니다.

> ✅ **1.2.0은 배포됐습니다** (개발자 확인, rev.10).
> `ver1.2.0`(2025-12-08) → `ver1.2.1` 롤백(2025-12-30), **22일간 배포 상태**였습니다.
> 그 기간에 작성되고 덮어쓰이지 않은 행은 **절대좌표**입니다.

#### 10-2-1. `normalizedForVerseRect` 휴리스틱은 실데이터의 71%에서 실패합니다 ★ (rev.10)

Phase 0B fixture 작업에서 실사용 blob 225건에 판정식을 적용해 실측했습니다
([LegacyCoordinateTesting.swift](../Feature/CarveFeature/Tests/LegacyCoordinateTesting.swift)).

판정식은 **`strokes.first.renderBounds`** 가 `rect.origin` 에서 **두 축 모두** 20pt 이내일 때만
절대좌표로 간주합니다. 전체 `drawing.bounds` 가 아니라 **첫 획의 renderBounds** 입니다.

| 조건 | 건수 |
|---|---:|
| 판정 발동 (복원됨) | **66 / 225 (29%)** |
| 발동 안 함 (절대좌표 그대로 남음) | **159 / 225 (71%)** |

**두 방향으로 깨집니다.**

| # | 실패 | 결과 |
|---|---|---|
| 1 | 절대좌표인데 **탐지 안 됨** (71%) | 필사가 장 저 아래에 그려짐. **오류도 로그도 없음** |
| 2 | 로컬인데 **절대좌표로 오인** (장 상단 절) | 멀쩡한 데이터가 `rect.origin` 만큼 밀림 |

두 실패는 **방향이 반대라 `tolerance` 를 조정해도 동시에 해소되지 않습니다.**
키우면 1번이 줄고 2번이 늘고, 줄이면 반대입니다.

> **→ P3(좌표 형식을 `drawingVersion`으로 명시 기록)는 선택이 아니라 필수입니다.**
> 휴리스틱 개선으로는 이 문제를 풀 수 없습니다. 위 7단계 런타임 정책의 6번
> ("확실하지 않은 절은 복구 로그 / 사용자 확인 대상")이 **다수 경로**가 될 것을 전제해야 합니다.

### 10-3. 롤백의 의미 — forward-only ★

**V4로 마이그레이션된 store는 V3 스키마 빌드로 되돌릴 수 없습니다.**
따라서 "각 Phase 독립 배포"는 **forward-only**를 의미합니다.

| Phase | 되돌리는 수단 |
|---|---|
| 0A / 0B | 해당 없음 (배포물 없음) |
| 1 (V4 스키마) | **버전 다운그레이드 불가.** V4는 되돌릴 수 없는 지점 |
| 2 (VStack/overlay) | 새 빌드 배포 |
| 3 (단일 Canvas) | **feature flag off** — 단, V4 저장소는 유지된 채로 |
| 4 (구조 제거) | 새 빌드 배포 |

→ **필수 테스트:** V4 저장소를 유지한 채 flag를 껐을 때 **기존 N Canvas 경로가 정상 동작**해야 합니다.
Phase 3의 유일한 안전망이므로 Phase 1 배포 전에 이 경로를 확보합니다.

### 10-4. BiblePageDrawing

- 기준 데이터가 **아닙니다.** 동일 레이아웃에서만 유효한 캐시/복구용으로 격하합니다.
- **CloudKit 충돌 관점:** 절 단위 행은 서로 다른 절을 다른 기기에서 동시 편집해도 병합되지만,
  `BiblePageDrawing`은 장 전체가 레코드 1개라 last-writer-wins로 통째 덮어씁니다.
  → 장기적으로 **제거**를 권합니다.

---

## 11. UI 호스팅 — spike로 확정 (P5)

`PKCanvasView`는 SDK 상 `UIScrollView` 서브클래스입니다(`PKCanvasView.h:71`).

```
A. SwiftUI ScrollView
   └─ content-sized PKCanvasView overlay
      · 기존 시도와 동일한 구조 (검증된 실패 이력 있음)
      · StableCanvasView 수준의 contentInset/offset/zoom 정규화 필요
        (rev.12: S4 에서 이 정규화를 꺼도 통과 기준 1~6 이 전부 통과했습니다 — 아래 참조)

B. PKCanvasView가 유일한 UIScrollView
   └─ PKCanvasView의 scroll content 내부에
      UIHostingController로 텍스트/밑줄 배치
      · drawingPolicy = .pencilOnly 이면 손가락=스크롤 / 펜슬=필기를 PencilKit이 처리
      · 성공 시 StableCanvasView 대부분 제거 가능
        (§2 D5 정정 참조 — 별도 파일이 아니라 CombinedCanvasView.swift 21~458행)
```

> **금지:** PKCanvasView와 **별개인** SwiftUI 텍스트에 `contentOffset`만 전달하는 방식.
> 프레임별 동기화, bounce, safe-area, zoom 과정에서 drift가 재발합니다.
> B를 택한다면 텍스트는 반드시 **canvas의 scroll content 내부**에 있어야 합니다.

### 실험 범위

**SwiftData와 실제 사용자 Drawing을 연결하지 않습니다.** Debug 전용 하네스로 격리합니다.

```
Debug 전용 CanvasScrollSpike
 ├─ A: SwiftUI ScrollView + content-sized PKCanvas overlay
 ├─ B: PKCanvasView 단독 scroll + 내부 UIHostingController
 ├─ 동일한 176절 mock layout
 ├─ 동일한 초기 PKDrawing
 └─ 런타임 A/B 전환 가능
```

### 통과 기준

"Sim" / "Device" 는 **그 기준을 어디서 확인할 수 있는가**이고, "S4 판정" 은 **실제로 확인한 결과**입니다(rev.12).

| # | 기준 | Sim | Device | S4 판정 |
|---|---|:--:|:--:|---|
| 1 | 스크롤 전후 동일 content point의 stroke 오차 **≤ 1pt** | ✅ | ✅ | ✅ **A·B** — 왕복 9000pt, 프로브 3곳, max 0.000pt |
| 2 | 빠른 fling/rebound 후 텍스트·밑줄·Drawing 오차 없음 | ✅ | ✅ | △ **부분** — bounce 프로그램 왕복 PASS. **관성 fling 미수행** |
| 3 | Split View resize 후 재필기 위치가 맞음 | ✅ | ✅ | ✅ **근사** — 폭축소 토글 재계산 후 0.000pt. 실제 창 조작 미수행 |
| 4 | 왼손잡이 레이아웃 전환 후 좌표 정합 | ✅ | ✅ | ✅ 전환 후 0.000pt |
| 5 | 헤더 애니메이션 / 롱프레스 메뉴 / 탭 제스처 동작 | ✅ | ✅ | △ **부분** — 헤더 애니메이션 중 스크롤 PASS. 탭/롱프레스는 **구조만 확인** |
| 6 | 앱 재진입·장 변경 후 `contentOffset` 복원이 일관됨 | ✅ | ✅ | ✅ 재진입·장 전환 모두 Δ0.00 |
| 7 | live stroke가 pencil-up 순간 확대·이동하지 않음 | ❌ | ✅ | 미수행 (실기기 전용) |
| 8 | Pencil hover 중 좌표 변화 없음 | ❌ | ✅ | 미수행 (실기기 전용) |
| 9 | `.pencilOnly`에서 한 손가락 스크롤 가능 | ❌ | ✅ | 미수행 (실기기 전용) |
| 10 | `allowFingerDrawing == true`일 때 스크롤 방법이 명확함 | ❌ | ✅ | 미수행 (실기기 전용) |
| 11 | 시편 119편 layout 시간·peak memory (baseline 대비) | △ | ✅ | **미측정** — `vmmap` 권한 오류 |

△ = 시뮬레이터 수치는 절대값으로 쓸 수 없고 **A/B 상대 비교와 알고리즘 복잡도 확인**에만 사용합니다.

#### 기준 1 의 "오차" 는 무엇인가 ★ (rev.12 — 신규 보강)

**원문에 정의가 없었고, 그대로 두면 측정이 가짜 FAIL 을 만듭니다.**

오차를 **화면 절대 위치**로 잡으면 **컨테이너가 움직인 것까지 오차로 잡힙니다.**
S4 실측에서 **헤더 접힘 애니메이션만으로 105pt(헤더 높이) 짜리 가짜 FAIL** 이 났습니다 —
스크롤 정합은 완벽한데 viewport 자체가 화면에서 위로 올라간 것뿐이었습니다.

> **기준 1 이 묻는 것은 "content point → viewport 매핑이 `contentOffset` 만큼의 평행이동인가" 이지,
> viewport 가 화면 어디에 있는가가 아닙니다.**

따라서 측정은 다음 형태여야 합니다.

```
residual = (point 의 window 좌표) − viewportOriginInWindow + contentOffset
           └ 스크롤해도 불변이어야 하는 값. 그 변동폭이 곧 오차다.

viewportOriginInWindow = scrollView.convert(scrollView.bounds.origin, to: nil)
```

`viewportOrigin` 을 빼는 항이 **컨테이너 이동을 제거하는 지점**입니다.
헤더 접힘·Split View·safe area 변화는 전부 여기로 흡수됩니다.

### 판정

```
B가 기능 기준(1~6)을 모두 통과            → B 잠정 채택, 실기기에서 7~11 확인   ← ✅ 여기에 해당 (rev.12)
B에 수정 가능한 gesture 문제만 존재        → B 보완 후 재검증
B에서 text hosting / offset / render 문제  → A 검증
A도 offset drift 재현                     → 저장·Feature 구현으로 넘어가지 않고
                                            호스팅 구조 재설계
```

---

### S4 실행 결과 — Phase 0A-S4 (rev.12, `b53cbfd8`)

> 환경: **iPad mini (A17 Pro) 시뮬레이터 iOS 26.2 / Xcode 26.3**
> 176절 mock layout, 총 높이 **16184pt**. Debug 전용 하네스이며 SwiftData·실사용 Drawing 과 연결되지 않습니다.
> 하네스 구조와 측정 방법의 상세는 **§20-4**.

**8개 시나리오 전부 — A 와 B 모두 max 0.000pt PASS**

| # | 시나리오 | A | B |
|---|---|:--:|:--:|
| 1 | AUTO 시작 (모드 표시) | 0.000 | 0.000 |
| 2 | 왕복 스크롤 9000pt | 0.000 | 0.000 |
| 3 | 오버스크롤 (bounce) | 0.000 | 0.000 |
| 4 | 헤더 애니메이션 중 스크롤 | 0.000 | 0.000 |
| 5 | 왼손 레이아웃 전환 후 왕복 | 0.000 | 0.000 |
| 6 | 폭축소(resize) 후 왕복 | 0.000 | 0.000 |
| 7 | 재진입 복원 (요청 4200.0 → 실제 4200.0, Δ0.00) | 0.000 | 0.000 |
| 8 | 장 전환 왕복 복원 (동일) | 0.000 | 0.000 |

- 프로브 3곳(**v1 / v88 / v176**) 전부 0.00 — 장 상단·중간·하단 모두.
- **깊은 offset 15000 에서 166~174절의 텍스트·잉크가 정상 렌더**됐습니다.
  B 의 16184pt `UIHostingController` 가 깊은 위치에서 렌더되는지가 이 spike 의 **최대 우려**였고, 재현되지 않았습니다.
- A 는 **"A정규화"(`StableCanvasView` 수준의 매-레이아웃 offset/inset/zoom 리셋)를 꺼도** 0.000pt 였습니다.
  **이 경로에는 보정할 drift 자체가 없었습니다.**

#### ★ 이번 측정은 A 와 B 를 구별하지 못했습니다

> **가장 중요한 결론입니다. 수치만 보고 "B 가 검증됐다" 고 읽으면 안 됩니다.**
>
> A 도 정규화 없이 전부 통과했으므로, **현시점의 "B 우세" 근거는 수치가 아니라 구조**입니다.
>
> | 근거 | 내용 |
> |---|---|
> | 구조 | 스크롤 컨테이너가 1개라 **offset 동기화 코드가 0줄** — §11 이 금지한 "별개 SwiftUI 텍스트에 `contentOffset` 전달" 을 **구조적으로** 회피 |
> | 구조 | `StableCanvasView` 의 ②(offset/inset/zoom 리셋)가 **보정하던 대상 자체가 존재하지 않음** (§2 D5 정정) |
> | 수치 | **없음.** 두 구조가 같은 값을 냈습니다 |

**이것은 예상된 결과입니다.**
D5 / issue #6 의 실패는 **프로그램 스크롤에서 나오지 않습니다.**
라이브 Pencil 입력·hover·렌더 타이밍에서 나오며, 그건 **통과 기준 7·8 — 실기기 전용**입니다.

> **→ A/B 의 실질적 판정은 Phase 0A-D 의 D1/D2 로 넘어갑니다.** (§12 · §13)
> S4 가 확정한 것은 "B 에서 text hosting / offset / render 문제가 **나오지 않았다**" 까지이며,
> 위 판정 블록의 첫 번째 분기(**B 잠정 채택**)에 해당합니다.

#### 확인하지 못한 것

| 항목 | 사유 |
|---|---|
| 기준 2 의 **관성 fling** | 시뮬레이터 터치 주입 도구가 `xcode-select` 설정 때문에 사용 불가. 해소하려면 `sudo xcode-select` 가 필요해 **시스템 설정을 바꾸지 않았습니다** |
| 기준 5 의 **탭 / 롱프레스 동작** | 같은 사유. **구조만 확인** — `tapGR=1`, `longGR=3` 이 draw/pan 제스처와 **동시 활성**임을 확인했고, 실제 동작은 미확인 |
| 기준 3 의 **실제 Split View 창 조작** | 폭축소 토글로 **같은 코드 경로**(레이아웃 재계산)를 태웠습니다. 창 조작 자체는 미수행 |
| 기준 11 의 **A/B 메모리 비교** | `vmmap` 이 권한 오류로 실패 |

---

## 12. 미결 결정사항

| ID | 결정 | 선택지 | 상태 |
|---|---|---|---|
| **U1** | cross-verse 획 소유권 | **시작 절에 stroke 전체 귀속** | **확정** (§7-1) |
| **U2** | 절당 다중 행 / 히스토리 | **기존 다중 행과 히스토리 유지** → mutation을 행 주소지정으로 | **확정** (§8-7) |
| **U3** | 지우개 모드 | **`.bitmap` 유지** | **확정** (§7-4) |

미결로 남은 것은 **스크롤 구조(A/B)** 하나입니다.

> **rev.12 갱신 — B 잠정 채택, 최종 판정은 D1/D2.**
>
> | 항목 | 상태 |
> |---|---|
> | Phase 0A-S4 (시뮬레이터, `b53cbfd8`) | ✅ 완료. 기능 기준 1~6 통과 → **B 잠정 채택** |
> | 그 판정의 근거 | **구조**(스크롤 컨테이너 1개, offset 동기화 코드 0줄). **수치가 아닙니다** — A·B 모두 max 0.000pt 로 **구별되지 않았습니다** |
> | 최종 판정 | **Phase 0A-D 의 D1(Pencil hover / live stroke)·D2(`.pencilOnly` 손가락 스크롤)** 로 이월 |
>
> **"S4 통과 = A/B 확정" 이 아닙니다.** issue #6 의 실패 모드는 프로그램 스크롤이 아니라
> 라이브 Pencil 입력·렌더 타이밍이며, 시뮬레이터에는 그 입력이 없습니다 (§11 "S4 실행 결과").
> 그동안의 구현은 **B 를 전제로 진행하되**, §5 의 `columnOrigin` 평행이동과 하단 인셋 미결처럼
> **B 에서만 발생하는 규정**은 A 로 후퇴할 여지를 남겨 두고 작성해야 합니다.

### U2 결정의 파급

히스토리를 유지하므로 저장 명령이 **절 번호가 아닌 행**을 주소지정해야 합니다. §8-7에서 다음을 규정했습니다.

| 항목 | 규정 |
|---|---|
| 활성 행 추적 | `State.activeRowIDs: [Int: BibleDrawingRowID]` |
| `clear` 의미 | 행 삭제 금지, `lineData`만 비움 (삭제 시 과거 회차가 승격되어 지운 획이 되살아남) |
| 히스토리 복원 | flush → `isPresent` 이전 → `verseRowRestored` (mutation 미생성) → undo clear |
| coalescing 키 | verse가 아닌 **rowID** |
| `mainDrawing()` | 결정적 순서로 고정 (CloudKit 중복 `isPresent` 대비) |
| 새 회차 생성 | 현행 유지 — 행이 없을 때만. 자동 회차 증가 없음 |

> `BibleDrawing` 신규 행은 지금도 **"해당 절에 기존 행이 없을 때만"** 생성됩니다
> ([DrawingDatabase.swift:113](../Domain/Domain/Sources/SwiftData/DrawingDatabase.swift), [CanvasFeature.swift:56](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CanvasFeature.swift)).
> 따라서 히스토리에 회차가 쌓이려면 별도의 "새 필사 시작" 트리거가 필요하며, 이는 **별도 제품 기능**입니다.

---

## 13. 이행 계획

각 Phase는 **forward-only**로 독립 배포 가능합니다(§10-3).

### 진행 경계

| 단계 | 착수 가능 시점 |
|---|---|
| **Phase 0A-S0** | ✅ **완료** (§18) |
| **Phase 0A-S1 / S2** | ✅ **완료** (§19) |
| **Phase 0A-D · D8** | ✅ **완료** — S5 fixture 확보 (§20-3) |
| **Phase 0A-D 나머지** | ⏳ **대기** — 멤버십 재결제 완료, **활성화 전파 대기 중**. 전파되면 D1·D2(S4 하네스로 A/B 최종 판정) · D3 · D4 · D5 · D6 · D7 전부 착수 가능 |
| **Phase 0B** | ✅ **완료** — `f5206814` 레이아웃 · `0c071d29` 소유권/승계 · `565dfe69` line band reflow |
| **Phase 0A-S4** | ✅ **완료** (`b53cbfd8`) — 기능 기준 1~6 통과. **단 A/B 판정은 D1/D2 로 이월** (§11 · §12) |
| **Phase 0A-S3** | ❌ **미수행** — 아래 참조 |
| **Phase 1** | ✅ **구현 완료** (`b68b6101`) — **단 배포 가능 아님.** CloudKit 제약 미검증(D7 이월), §10-3 forward-only |
| **Phase 2** | ⚠️ **D5 이후에 착수** — `LazyVStack → VStack` 전환이 N-Canvas baseline 측정 기회를 **영구히 없앱니다**. 아래 참조 |
| Phase 3 | feature flag 뒤 **구현**까지는 가능. **기본 활성화·배포 판단은 Phase 0A-D 이후** |
| Phase 4 (구 구조 삭제) | 실기기 검증 및 안정화 후 |

> ⚠️ **Phase 2 착수 전에 D5 를 재야 합니다 (rev.13).**
> D5 는 **현재 N-Canvas 경로의 실기기 성능 baseline** 입니다. Phase 2 가 `LazyVStack` 을 걷어내는
> 순간 그 경로가 사라져 **다시는 측정할 수 없습니다.** §18-3 이 시뮬레이터 baseline 을 Phase 2 이전에
> 확보해둔 것과 같은 논리이며, 실기기 수치는 아직 없습니다.
>
> 순서: **멤버십 활성화 → D5 → Phase 2**. 이 순서를 어기면 되돌릴 방법이 없습니다.

> **Phase 1 이 "구현 완료" 이지 "배포 가능" 이 아닌 이유 (rev.13)**
> ① CloudKit 제약(전 속성 optional·unique 금지)을 **코드상으로만** 만족합니다. 시뮬레이터에
> entitlement 가 없어(§18-5) `NSPersistentCloudKitContainer` 가 V4 를 실제로 수용하는지 검증하지
> 못했습니다 — **D7 이월**.
> ② §10-3 이 V4 를 **forward-only**(되돌릴 수 없는 지점)로 규정합니다.
> → **배포 판단은 D7 확인 이후여야 합니다.**

> **S3 는 왜 여전히 미수행인가 (rev.12)**
> S4 하네스가 `ChapterLayoutBuilder` 로 176절 layout 을 만들어 `gate PASS` 를 확인했으므로
> **§6-2 게이트와 176절 규모의 좌표 계산은 부수적으로 확인**됐습니다.
> 그러나 S4 는 줄 수를 **결정적 규칙 `1 + (verse − 1) % 4` 로 고정**했습니다 —
> **실제 텍스트 측정 기반 줄 수는 여전히 확인되지 않았습니다.**
> S3 의 본질(Pass 1 측정 → `ChapterLayout` 정확성)은 Phase 2 의 측정 경로 없이는 검증할 수 없으므로,
> **Phase 2 와 함께 수행**하는 것이 자연스럽습니다.

---

### Phase 0A-S0 — 기준선 확보 (모든 spike의 선행 조건)

**✅ 실행 완료 — 결과는 [§18 부록 B](#18-부록-b--phase-0a-s0-실측-결과-실행-완료).**

**S1~S5보다 먼저 수행합니다.** 비교 대상이 없으면 이후 측정이 무의미해집니다.

| ID | 항목 | 산출물 |
|---|---|---|
| **S0-1** | `tuist install` → `tuist generate` → iPad 시뮬레이터 기동 | 실행 가능한 기준선 |
| **S0-2** | 기존 테스트 전량 통과 확인 (`xcodebuild test`, **iPad destination**) | 회귀 판정 기준 |
| **S0-3** | `DrawingDatabase.updateDrawing`의 `actor.update(drawing.id)`가 어떤 타입으로 해석되는지 **빌드로 확정** | 행 주소지정 계약 확정 (§8-7) |
| **S0-4** | **기존 N-Canvas 경로의 baseline 측정** — 시편 119편 진입 시간, 메모리, 스크롤 체감 | S4·D5의 비교 기준 |
| **S0-5** | 시뮬레이터에서 legacy 데이터를 재현할 수 있는지 (dev CloudKit 컨테이너 또는 seed) | S5 fixture 착수 가능 판정 |

> **S0-4가 특히 중요합니다.**
> §6-1의 "메모리는 측정 전까지 단정하지 않는다"를 검증하려면 **전(before) 수치**가 필요한데,
> 단일 Canvas로 바꾼 뒤에는 기존 경로를 다시 측정할 수 없습니다.
> Phase 2에서 `LazyVStack → VStack` 전환이 들어가기 전에 반드시 확보해야 합니다.

> **S0-3은 코드를 고치지 않습니다.** 현재 표현이 어떤 타입으로 해석되는지 확인만 하고,
> 실제 정리는 Phase 3의 Repository 전환에서 수행합니다.

---

### Phase 0A-S — 시뮬레이터에서 가능한 검증

S0 완료 후 수행합니다.

| ID | 항목 | 결정하는 것 |
|---|---|---|
| **S1** | **PencilKit 데이터 모델 검증** (대부분 단위 테스트로 가능) | §7-2 / §7-4 확정 |
| S1-1 | `randomSeed`가 `dataRepresentation()` 라운드트립에서 보존되는가 | IdentityKey 성립 여부 |
| S1-2 | bitmap 지우개가 stroke를 **분할하는가, mask만 다는가** | 승계 전략 (§7-3 1번 vs 3번) |
| S1-3 | 완전히 지운 stroke가 `drawing.strokes`에 남는가 | §7-5 "가시 획" 판정 필요성 |
| S1-4 | 지우개 후 `creationDate` / `randomSeed` / `path.count` 변화 | IdentityKey 구성요소 |
| S1-5 | `mask` / `maskedPathRanges`가 직렬화에서 보존되는가 | ContentSignature 성립 여부 |
| **S2** | `Text.LayoutKey.Value` probe — 줄별 문자 범위 노출 여부 | `textLineRanges` 실현 가능성 (§9-3) |
| **S3** | 레이아웃 파이프라인 — 176절 VStack `ChapterLayout` 정확성, 게이트 동작, 디버그 오버레이 | §6 전체 |
| **S4** | ✅ **완료** (`b53cbfd8`) — 스크롤 A/B 골격 + 통과 기준 1~6 (§11) | 호스팅 구조 **잠정** 결정 (B). 최종 판정은 D1/D2 |
| **S5** | legacy `lineData` 회귀 fixture 확보 (dev CloudKit 컨테이너) | Phase 0B 입력 |

> S1은 시뮬레이터에서 `drawingPolicy = .anyInput`으로 마우스 필기가 가능하므로 검증됩니다.
> **PencilKit의 데이터 모델 동작이지 펜슬 하드웨어 동작이 아니기 때문입니다.**
> 다만 실제 Pencil 지우개에서 결과가 다를 수 있으므로 D3에서 재확인합니다.

### Phase 0A-D — 실기기에서만 가능한 검증 (이후)

대상 기기: **iPad mini (A17 Pro)**, **iPad Air (M2)**

| ID | 항목 |
|---|---|
| **D1** | Apple Pencil 입력 — hover 중 offset, live stroke가 pencil-up에 확대·이동하는지 (issue #6 핵심) ← **A/B 최종 판정이 여기로 이월됨 (rev.12)** |
| **D2** | `.pencilOnly`에서 한 손가락 스크롤 / `allowFingerDrawing == true`일 때 스크롤 UX ← **A/B 최종 판정 (rev.12)** |
| **D3** | 실제 Pencil 지우개로 S1 결과 재확인 |
| **D4** | Apple Pencil 더블탭(지우개 전환), 두 손가락 더블탭(undo) |
| **D5** | 시편 119편 layout 시간·peak memory 실측, 스크롤 프레임 드랍 |
| **D6** | Stage Manager / 외부 디스플레이 (Air M2) |
| **D7** | **Phase 1 V4 스키마의 CloudKit 제약 검증** — 시뮬레이터는 entitlement가 제거되어 미러링이 전혀 동작하지 않음 (§18-5) |
| **D8** | 진짜 legacy `lineData` 1회 추출 (S5 fixture 확보, §18-4) |

**보유 기기의 사각지대 — 리스크로 관리:**

| 사각지대 | 영향 | 대응 |
|---|---|---|
| 둘 다 60Hz (ProMotion 없음) | issue #6은 렌더/스크롤 타이밍 이슈라 120Hz에서만 재현될 수 있음 | TestFlight 베타에서 iPad Pro 사용자 확인 |
| 둘 다 8GB, 저사양 기기 없음 | 배포 타깃 iOS 17에는 저메모리 iPad 포함. 시편 119편 메모리 리스크는 그쪽이 최대 | 베타 단계 검증 항목으로 이월 |

**산출물:** A/B 최종 결정, 승계 전략 확정, 메모리·성능 수치

> **rev.12 — D1/D2 의 무게가 커졌습니다.**
> S4 가 A 와 B 를 구별하지 못했으므로(§11 "S4 실행 결과"), **A/B 를 실제로 가르는 측정은 D1/D2 뿐입니다.**
> S4 하네스는 릴리즈에서 제외된 채 저장소에 남아 있으므로, D1/D2 는 새 하네스를 만들지 말고
> **같은 하네스를 실기기에서 그대로 돌려** 시뮬레이터 결과와 나란히 비교하십시오
> (`-CanvasScrollSpike`, §20-4). 그때 미수행으로 남은 기준 2 의 fling 과 기준 5 의 탭/롱프레스도 함께 해소됩니다.

### Phase 0B — 순수 로직과 회귀 fixture ✅ 완료 (rev.12)

| 항목 | 커밋 | 산출물 |
|---|---|---|
| `ChapterLayoutBuilder` (2-pass, 안정 signature 포함) | `f5206814` | [Domain/Sources/Layout/](../Domain/Domain/Sources/Layout/) — `ChapterLayout` / `ChapterLayoutSignature` / `ChapterLayoutBuilder` |
| owner resolver / reconciler | `0c071d29` | `ChapterLayoutPointQuery` · [StrokeOwnershipResolver.swift](../Feature/CarveFeature/Sources/Drawing/StrokeOwnershipResolver.swift) · `StrokeIdentityKey` / `StrokeContentSignature` / `OwnershipSnapshot` |
| line band reflow + `DrawingLayoutMetadata` DTO | `565dfe69` | [LineBandReflow.swift](../Feature/CarveFeature/Sources/Drawing/LineBandReflow.swift) · [DrawingLayoutMetadata.swift](../Domain/Domain/Sources/Layout/DrawingLayoutMetadata.swift) |
| **실제 legacy `lineData` 샘플 fixture 확보** | `0e9a8449` | §20-3 — 실사용 blob 5건 |
| UI 변경 없음 | — | 어디서도 호출되지 않는 순수 로직. **배선은 Phase 2~3** |

- SwiftData V4 스키마는 **만들지 않았습니다** — 그것은 Phase 1 입니다.
- reflow 구현에서 결정한 명세 공백 4건은 §9-3-1 하위 절에 반영했습니다.

### Phase 1 — V4 additive schema
- optional metadata 필드만 추가, **legacy 자동 변환 금지**
- **flag off 경로(기존 N Canvas)가 V4 저장소에서 동작하는지 먼저 확보** (§10-3)
- 마이그레이션 안정화에만 집중해 단독 배포

### Phase 2 — VStack + layout gate + debug overlay
- 기존 N개 Canvas 유지, 사용자 동작 변화 없음
- **debug overlay:** `writingRect` / `captureRect` / `underlineAnchors` / `dirtyBounds` 시각화
  → 이전 두 번의 시도에서 "왜 어긋나는지 볼 수단"이 없었던 것이 디버깅을 어렵게 만들었습니다

### Phase 3 — feature flag 뒤 단일 Canvas
- whole-stroke ownership, editBegan/editEnded 계약
- 행 주소지정(activeRowIDs) + 히스토리 복원 재배선
- coalescing + 직렬 저장 + atomic replace/clear/create
- 런타임 legacy 판별
- **flag off로 롤백** (V4 저장소는 유지)

### Phase 4 — 안정화 후 구 구조 제거
- `CanvasFeature` / `CanvasView`
- `SharedUndoManager`
- `clippedPrecisely` / `normalizedForVerseRect` (판별 로직만 Codec으로 이관)
- `StableCanvasView` 디버그 코드 (~400줄) — 단, **별도 파일이 아니라 `CombinedCanvasView.swift` 21~458행** (rev.12 정정)
- `VerseRowFeature` (죽은 리듀서 — `State.ID` 타입 별칭으로만 참조됨)

#### SharedUndoManager를 제거해야 하는 근거

단일 캔버스면 `canvas.undoManager`가 그대로 동작합니다. 게다가 현재 구현은 실제로 깨져 있습니다
([SharedUndoManager.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/SharedUndoManager.swift)):

- `registerUndoAction`이 캔버스를 계속 `append`만 함
- `undo()`가 액션 소유자가 아니라 `canvases.last`의 undoManager를 호출
- `guard let ... else { return }`가 `isPerformingUndoRedo = true`를 남긴 채 빠져나감

---

## 14. 테스트

### 필수 항목

**소유권·저장**
1. 경계 획이 잘리지 않고 **시작 절에 온전히** 저장되는지
2. 지우개로 절을 완전히 비우면 `clear` mutation이 발생하는지 (마스킹된 획 포함, §7-5)
3. 두 절 dirty 저장 중 하나가 실패하면 **모두 롤백**되는지
4. 동일 fingerprint 후보가 여러 개일 때 owner가 **결정적으로** 선택되는지
5. 복수 `BibleDrawing`이 있는 절에서 `clear` 후 과거 회차가 **자동 승격되지 않는지** (행 삭제 금지 검증)

**히스토리 (U2)**
5-1. 편집이 항상 `activeRowIDs[verse]` 행에만 기록되는지 (다른 회차 행이 변경되지 않는지)
5-2. 히스토리 복원이 **mutation을 생성하지 않는지**
5-3. 미저장 pending이 남은 상태에서 히스토리를 복원해도 이전 행의 변경이 유실되지 않는지
5-4. `isPresent == true` 행이 복수일 때 `mainDrawing()`이 **결정적으로** 선택하는지
5-5. 가시 획이 없는 행이 히스토리 목록에서 숨겨지되 **행 자체는 유지**되는지

**signature / 행 생성**
5-6. **mask만 달라진 stroke**가 동일 owner를 유지하면서 **dirty로 판정**되는지 (§7-2)
5-7. 신규 절 연속 편집이 **create 행 하나로 coalescing**되는지 (§8-7)

**순서·복구**
6. edit 1 저장이 지연된 상태에서 edit 2가 먼저 완료돼도 최종 DB가 edit 2인지
6-1. 저장 중 같은 rowID에 새 revision이 들어오면 **성공 콜백이 최신 mutation을 제거하지 않는지** (§8-3)
6-2. Drawing 조회와 layout 측정의 **완료 순서가 바뀌어도** 합성 결과가 같은지 (§6-4)
6-3. 장을 빠르게 변경했을 때 **이전 장의 조회 결과가 새 장에 적용되지 않는지** (§6-4)
7. 장 전환 직전 pending edit가 유실되지 않는지
8. 저장 실패 후 다음 edit가 성공하면 미저장 변경까지 함께 반영되는지

**레이아웃·복원**
9. 동일 레이아웃 load → save 라운드트립에서 구조가 보존되는지
10. layout 미완성 상태에서는 입력·저장이 발생하지 않는지
11. layout 변경 중 필기하면 **pencil-up 이후에만** reflow되는지
12. 줄 수 감소 시 다음 절과 겹치지 않도록 effective verse height가 증가하는지
13. legacy(metadata 없음) Drawing이 무변환으로 현재 rect에 배치되는지
14. reflow 적용 후 undo stack 초기화가 UI 상태와 일치하는지
15. `layoutSignature`가 앱 재실행 후에도 동일한지 (hashValue 회귀 방지)

**롤백**
16. V4 저장소를 유지한 채 feature flag를 껐을 때 기존 N Canvas 경로가 정상 동작하는지
17. undo/redo 후 앱을 재실행해도 결과가 유지되는지

### 라운드트립 판정 기준

> **"비트 단위 동일"은 기준으로 너무 강합니다.**
> `PKDrawing.dataRepresentation()`이 canonical byte serialization이라는 보장이 없습니다.

다음을 비교합니다.

- stroke 수 / control point 수
- 좌표 및 bounds (허용 오차 내)
- ink 속성, transform, `randomSeed`
- (선택) 화면 snapshot diff

### 테스트 프레임워크

기존 컨벤션대로 **Swift Testing**을 사용합니다. 위 항목 대부분은 PencilKit UI 없이
`ChapterLayoutBuilder` / resolver / reconciler / reflow 순수 계산으로 검증 가능해야 합니다.

---

## 15. 주요 리스크

| 리스크 | 완화 |
|---|---|
| whole-stroke ownership에서 장대한 획이 레이아웃 변경 시 시작 절과 통째로 이동 | 제품 정책으로 명문화 (U1) |
| 줄 수 감소 시 ChapterLayout이 2-pass가 되어 측정 비용 증가 | Pass 2는 band 개수만 사용 (좌표 계산 없음) |
| PKCanvasView 스크롤 주체 방식이 SwiftUI 제스처/헤더와 충돌 | Phase 0A spike, 실패 시 A안 후퇴 |
| 시편 119편 성능·메모리 | Phase 0A 실측, layout 캐시 |
| fingerprint가 영구 ID가 아님 | 세션 내 승계 도구로만 사용, DB의 절별 그룹이 진실 |
| **저장 effect 미직렬화 시 최신 편집이 과거에 덮임** | rowID 키 coalescing + revision 비교 드레인 (§8-3) |
| **로컬 atomic batch ≠ CloudKit 동기화 원자성** | 알려진 한계로 문서화. 다른 기기에서 일시적 부분 상태 가능 (§8-6) |
| **V4 이후 버전 다운그레이드 불가** | flag off 경로를 Phase 1 배포 전에 확보 (§10-3) |
| 히스토리 유지로 행 식별자가 핵심 경로가 됨 (`id` 초 단위 충돌 가능) | 신규 행만 `rowUUID` 발급, legacy는 business `id` 유지 (비파괴) (§8-7) |
| `clear`를 행 삭제로 구현하면 과거 회차가 승격되어 지운 획이 되살아남 | 행 유지 + `lineData` 비움으로 규정 (§8-7) |

---

## 16. 검증 상태

### SDK 헤더로 확인 완료 (iOS 26.2)

| 항목 | 결과 |
|---|---|
| `PKCanvasViewDrawingPolicy` | `.default` / `.anyInput` / `.pencilOnly` **3개뿐**. `.prohibited` 없음 → 게이트는 `drawingGestureRecognizer.isEnabled` |
| `PKCanvasView : UIScrollView` | 사실. 중첩 스크롤 진단(D5)의 근거 |
| `PKStroke.randomSeed` | iOS 16+ 존재. 배포타깃 17이므로 사용 가능. init으로 생성되어 직렬화 보존 |
| `PKStroke.mask` / `maskedPathRanges` | **API 존재만 확인.** 마스킹 방식일 것으로 **예상**되나 동작은 미확정 → S1-2 |
| `PKEraserType` | `.vector` / `.bitmap` / `.fixedWidthBitmap`(16.4+) |
| `PKStrokePath.creationDate` | 존재 |

### 헤더로 판정 **불가**한 것

| 항목 | 사유 |
|---|---|
| `Text.LayoutKey`의 노출 프로퍼티 | SwiftUI textual `.swiftinterface`가 **부분적** — `onPreferenceChange`, `padding`조차 없음. 부재의 증거가 되지 못함 → **S2** |
| `randomSeed` 라운드트립 보존 | 직렬화 동작이므로 헤더로 알 수 없음 → **S1-1** |
| bitmap 지우개의 분할 여부 | 런타임 동작 → **S1-2** |
| 완전히 지운 stroke의 잔존 여부 | 런타임 동작 → **S1-3** |

### ✅ 시뮬레이터에서 확인 완료 (Phase 0A-S0 / S1 / S2 — 결과 상세는 §18·§19 / **S4 — §11·§20-4**)

| ID | 결과 |
|---|---|
| S0-2 | 테스트 기준선 **57/57** 확보 (§18-2). 여기서 드러난 flaky 1건은 `19be99ea` 로 **해소** (§20-1) |
| S0-3 | `drawing.id` 는 **문맥 의존 오버로드** — 표현 금지 확정 (§8-7) |
| S0-4 | N-Canvas baseline 확보 (§18-3) |
| S0-5 | 현행 스키마 데이터는 시뮬레이터로 생성 가능. **진짜 legacy 는 실기기 필요** (§18-4) |
| S1-1 | `randomSeed` 라운드트립 **보존** |
| S1-2 | bitmap 지우개는 **분할 + 마스킹 동시**. 조각들이 IdentityKey 공유 (§7-4) |
| S1-3 | 완전히 지운 stroke 는 **제거됨** — §7-5 전제 반전. 여기서 드러난 프로덕션 버그는 `7ba5bc46` 으로 **수정 완료** (§20-2) |
| S1-4 | 지우개 후 IdentityKey 구성요소 **전부 불변** (control point 값까지) |
| S1-5 | `mask` / `maskedPathRanges` **보존**. 단 `mask == nil` 이면 ranges 는 전체 구간 |
| S2 | **`textLineRanges` 실현 가능** — `Run.characterIndices` (iOS 17.0+) |
| **S4** (rev.12) | **A·B 모두 8개 시나리오 max 0.000pt PASS.** 기능 기준 1·3·4·6 통과, 2·5 부분, 7~11 미수행. 깊은 offset 15000 에서 B 의 16184pt `UIHostingController` 정상 렌더. **★ 그러나 A 와 B 가 구별되지 않았습니다** — 판정은 D1/D2 로 이월 (§11 · §20-4) |

### 검증에서 파생된 기존 코드 수정 (검증 항목 자체가 아니라 그 부산물)

| 파생 항목 | 커밋 | 내용 | 문서 |
|---|---|---|---|
| **S0-2** | `19be99ea` | `DrawingWeeklySummaryFeature.topChapter` 가 동점에서 비결정적 → `TopChapterRank(Comparable)` 전순서로 해소 | §18-2, §20-1 |
| **S1-3** | `7ba5bc46` | 지우개로 전부 지운 결과가 저장되지 않던 문제 → 저장 가드 + throttle 수정 | §7-5, §20-2 |

> 둘 다 **기존 N-Canvas 구조 위의 수정**이며, 새 아키텍처 착수(Phase 0B 이후)와는 무관합니다.
> 따라서 아래 "남은 시뮬레이터 항목" 은 rev.8과 동일합니다.

### 남은 시뮬레이터 항목

- **S3** — 176절 `ChapterLayout` 정확성 및 게이트 (§6)
  > rev.12: **게이트 동작과 176절 규모 좌표 계산은 S4 하네스에서 부수적으로 확인**됐습니다(`gate PASS`).
  > 남은 것은 **실제 텍스트 측정 기반 줄 수** 입니다 — S4 는 `1 + (verse − 1) % 4` 로 고정했습니다.
  > 이 잔여분은 Phase 2 의 측정 경로와 함께 해소하십시오 (§13).
- ~~**S4** — 스크롤 A/B 통과 기준 1~6 (§11)~~ → ✅ **완료** (rev.12, `b53cbfd8`)

### 실기기에서만 확인 (Phase 0A-D)

6. Pencil hover / live stroke 스냅 (§11 기준 7~8) ← **A/B 최종 판정이 여기 있습니다 (rev.12)**
7. `.pencilOnly` 손가락 스크롤 (§11 기준 9~10) ← **A/B 최종 판정 (rev.12)**
8. 시편 119편 실제 layout 시간·peak memory (§6-1)
9. (rev.12 추가) §11 기준 2 의 **관성 fling**, 기준 5 의 **탭/롱프레스 동작** — 시뮬레이터 터치 주입 불가로 미수행 (§20-4)

### 코드 외부 확인

9. 1.2.0이 실제 배포되어 절대좌표 데이터가 존재하는가 — App Store Connect 버전 이력 (§10-2)

---

## 17. 룰 체크리스트

- [x] Canvas는 장당 하나
- [x] 저장 기준은 절별 Drawing
- [x] 좌표 영역 계산 = `ChapterLayoutBuilder`, transform 적용 = `DrawingCodecClient`
- [x] Feature에서 PencilKit/UIKit 타입 제거
- [x] SwiftData 접근은 Repository 단일 경로
- [x] 지우개 · undo/redo · 빈 절 저장 포함
- [x] 레거시 데이터 비파괴 처리 (런타임 lazy)
- [x] 레이아웃 변경은 표시 변환만 수행
- [x] atomic batch 저장
- [x] edit begin/before ownership 계약 정의
- [x] 연속 저장 직렬화 및 retry 정책 정의
- [x] 실제 존재하는 PencilKit 입력 게이트 사용
- [x] V4 이후 forward-only 롤백 의미 명문화
- [x] undo stack 정책 정의
- [x] 지우개 모드 확정 (`.bitmap`)
- [x] cross-verse stroke 소유권 확정 — 시작 절 통째 귀속 (U1)
- [x] 절당 다중 행 / 히스토리 유지 및 행 주소지정 확정 (U2)
- [x] identity key와 content signature 분리 (§7-2)
- [x] 신규 행 rowID 선발급 (§8-7)
- [x] 저장 중 도착한 최신 mutation 보호 (§8-3)
- [x] layout / drawings load 도착 순서 및 요청 취소 (§6-4)
- [x] 모듈 배치 — 순환 의존 회피 (§4)
- [x] 장 전환 요청/승인 흐름 (§8-5)
- [ ] PKCanvas 단독 스크롤 구조는 Phase 0A spike 전까지 확정하지 않음
      → rev.12: **S4 완료로 B 잠정 채택.** 여전히 미확정입니다 — S4 가 A/B 를 구별하지 못했으므로
        **최종 판정은 D1/D2** 입니다 (§11 · §12)

---

## 부록 — 삭제/격하 대상 요약

| 대상 | 처리 | Phase |
|---|---|---|
| `CanvasFeature` / `CanvasView` | 삭제 | 4 |
| `SharedUndoManager` | 삭제 (구현 자체가 깨져 있음) | 4 |
| `clippedPrecisely` / `normalizedForVerseRect` | 삭제 (판별 로직만 Codec으로 이관) | 4 |
| `StableCanvasView` | **별도 파일이 아닙니다 (rev.12 정정)** — `CombinedCanvasView.swift` 21~458행에 함께 선언된 클래스입니다. 따라서 "파일 삭제" 가 아니라 **`CombinedCanvasView` 재작성(Phase 3)에 흡수**되며, 남는 것은 디버그 덤프 제거뿐입니다. 스케일 강제 동기화(①)는 라이브 렌더 이슈 대응이라 D1 결과를 보고 존폐를 정하십시오 | 3~4 |
| `VerseRowFeature` | 삭제 (죽은 리듀서) | 4 |
| `CombinedCanvasFeature` / `CombinedCanvasView` | `ChapterCanvasFeature`로 재작성 | 3 |
| `Data.containsPKStroke` | **의미 유지 — 수정 대상 아님.** 호출부만 수정 완료 (`7ba5bc46`). V1→V2 마이그레이션이 `"stroke 가 있는가"` 의미에 의존하므로 정의를 바꾸지 않습니다 (§7-5, §20-2) | ✅ 완료 |
| `BiblePageDrawing` | 캐시/복구 전용으로 격하 → 장기 제거 | 3~ |
| `DrawingDatabase.updateDrawings(requests:)` | `DrawingRepository.apply(_:)` atomic batch로 대체 | 3 |
| `DrawingDatabase.updateDrawing(drawing:)` | 행 주소지정 정리 후 Repository로 흡수 (§8-7) | 3 |
| `BibleDrawing.mainDrawing()` | 결정적 선택 규칙으로 수정 (§8-7) | 3 |
| `VerseDrawingHistoryFeature` | **유지** — 단일 Canvas 복원 경로로 재배선 (§8-7) | 3 |

---

## 18. 부록 B — Phase 0A-S0 실측 결과 (실행 완료)

> 실행 환경: Xcode 26.3 / Swift 6.2.4 / **tuist 4.39.0** / iPad mini (A17 Pro) 시뮬레이터 iOS 26.2
> 저장소 변경 없음, 커밋 없음.

### 18-1. 재현 조건 — 주의사항

| 항목 | 값 |
|---|---|
| tuist | `PATH` 기본값은 **4.44.3**, 프로젝트 고정값은 **4.39.0** (`.mise.toml`) |
| **재현 시 반드시** | `mise x -- tuist ...` 로 실행. 아니면 다른 버전이 쓰임 |
| iPad 시뮬레이터 런타임 | **iOS 26.2 하나뿐** (iPad Pro 11" M5, iPad mini A17 Pro). iOS 17/18 iPad 런타임 없음 |

### 18-2. S0-2 — 테스트 기준선 (회귀 판정 기준)

`xcodebuild test -scheme Carve-Workspace`, iPad destination → **57/57 통과, 실패 0**

| 번들 | 개수 |
|---|---|
| DomainTest | 31 |
| CarveFeatureTest | 8 |
| CarveToolkitTest | 6 |
| ChartFeatureTest | 6 |
| SettingsFeatureTest | 3 |
| UIComponentsTest | 3 |

> **이후 어느 단계에서든 57 미만 통과 또는 실패 1건 이상이면 회귀입니다.**
> (이 57은 **rev.8 시점의 기록**입니다. 이후 테스트가 추가되어 현재 선언 수는 다릅니다 — §19-4.)

> ⚠️ **(rev.8 기록) 단, 이 기준선은 항상 재현되지 않았습니다.**
> `ChartFeatureTest / DrawingWeeklySummaryStateTesting` 의
> `"현재 주의 일별 권별 횟수를 합산해 가장 많이 필사한 권을 반환한다"` 가 **flaky** 였습니다 (S1에서 발견, 5회 중 1회 실패).
> 원인: [DrawingWeeklySummaryFeature.swift](../Feature/ChartFeature/Sources/Chart/DrawingWeeklySummaryFeature.swift) 의 (당시 71행)
> `merged.max(by: { $0.value < $1.value })` 가 **동점 시** Dictionary 순회 순서에 의존하고,
> Swift 해시 시드는 프로세스마다 달라 비결정적이었습니다.
> rev.8은 **"회귀 판정 시 이 1건은 별도로 취급하고, 결정적 tie-break 를 넣어 먼저 해소하는 것을 권합니다"** 라고 적었습니다.

> ✅ **rev.9 — 해소됨 (`19be99ea`).**
> `TopChapterRank(Comparable)` 를 도입해 **전순서(total order)** 로 1위를 선택합니다
> ([DrawingWeeklySummaryFeature.swift:78](../Feature/ChartFeature/Sources/Chart/DrawingWeeklySummaryFeature.swift)).
> 우선순위는 **① 합계 내림차순 → ② 성경 순서(`BibleTitle.allCases` 인덱스) 오름차순 → ③ 장 번호 오름차순** 입니다.
> **회귀 판정 시 별도 취급하던 예외가 사라졌습니다.** 상세는 §20-1.

### 18-3. S0-4 — N-Canvas 경로 baseline ★

**측정 방법 (재측정 시 그대로 반복)**

```
메모리  vmmap --summary <pid> | grep "Physical footprint"
        ※ ps RSS는 시뮬레이터 공유 페이지 때문에 320~480MB로 요동 → 비교 지표로 부적합
CPU     ps -o time= 누적 CPU time 델타, 0.25s 간격 샘플링
장 지정  UserDefaults "title" 키에 BibleChapter JSON을 -data 로 시드 후 재기동
스크롤  동일 flick 11회, (372,900) → (372,200), 0.2s  (iPad mini 744×1133pt)
기준점  cold launch 후 8초 settle
```

**(A) Cold launch (스크롤 없음)**

| 장 | 절 수 | Physical footprint | peak |
|---|---:|---:|---:|
| 창세기 1장 | 31 | **78.2 MB** | 84.6 MB |
| 시편 119편 | 176 | **86.2 MB** | 87.8 MB |

**(B) 앱 내 장 전환 진입**

| 전환 | 절 수 | footprint 전 → 후 | 증분 | CPU time |
|---|---:|---|---:|---:|
| 창세기 1장 → 2장 | 25 | 80.2 → **105.8 MB** | +25.6 MB | 0.25 s |
| 시편 118편 → 119편 | 176 | 80.9 → **118.3 MB** | +37.4 MB | 0.31 s |

**(C) 장 전체 스크롤 (flick 11회, 끝까지 도달 확인)**

| 장 | 절 수 | footprint 전 → 후 | 증분 | peak | CPU time | CPU>50% 샘플 |
|---|---:|---|---:|---:|---:|---|
| 창세기 1장 | 31 | 78.2 → **128.1 MB** | +49.9 MB | 130.8 MB | **9.99 s** | 49 / 348 |
| 시편 119편 | 176 | 86.2 → **195.2 MB** | +109.0 MB | 197.2 MB | **24.70 s** | 105 / 348 |

선형 근사: **증분 ≈ 37 + 0.41·N (MB)** — 절당 약 0.41 MB, 고정비 약 37 MB

**(D) 메모리 회수 — 되지 않음**

| 시점 | footprint |
|---|---:|
| 시편 119편 스크롤 완료 | 195.2 MB |
| 시편 120편(7절) 진입 6초 후 | **209.3 MB** |
| 추가 25초 대기 | **209.5 MB** |

작은 장으로 옮겨도 회수되지 않고 오히려 증가합니다.
**이는 단일 Canvas 전환 이전부터 존재하는 현상이므로, Phase 3 이후 메모리가 안 줄어든다고 해서 새 설계 탓으로 귀결시키면 안 됩니다.**

**체감**

- 진입은 절 수에 **거의 무관** (LazyVStack이 보이는 절만 생성). 시편 119편도 즉시 뜸
- 비용은 **진입이 아니라 스크롤에 분산**되어 있음. flick 중 한 코어 95~100% 점유 구간 반복

**측정 못 한 것 (코드 변경 필요 → Phase 2 이월)**

- 정밀 레이아웃 소요 시간 (`os_signpost` 필요)
- 프레임 드랍 / hitch time ratio (`CADisplayLink` 또는 Instruments 필요)
- PencilKit 캔버스 1개당 실제 점유 메모리

### 18-4. S0-5 — legacy fixture 확보 경로

| 대상 | 시뮬레이터 가능? |
|---|---|
| **현행 V3 스키마의 새 필사 데이터** | ✅ 가능. `allowFingerDrawing=true` → 마우스 필기 → `Carve.dev.sqlite`에 `BibleDrawing` 행 생성 확인 (재기동 후 영속성도 확인) |
| **§10-2가 말하는 진짜 legacy `lineData`** (V1 `DrawingVO` / 구 PencilKit 인코딩) | ❌ 불가. 지금 그리면 현재 스키마·현재 PencilKit으로 저장될 뿐 |

**진짜 legacy 확보 경로 두 가지**

```
(a) 실기기에서 dev CloudKit 컨테이너로 내려받기   ← 시뮬레이터는 entitlement가 제거되어 불가
(b) 실기기/실사용자의 Carve.sqlite 를 시뮬레이터 컨테이너에 파일 복사 후 마이그레이션 태우기
```

> ⚠️ **rev.9 정정 — (a)는 성립하지 않습니다.**
> Debug 빌드는 dev CloudKit 컨테이너(`iCloud.Carve.SwiftData.iCloud.dev`)에 붙는데
> ([Project.swift:36](../App/CarveApp/Project.swift)), **실사용자의 legacy 데이터는 prod 컨테이너**
> (`iCloud.Carve.SwiftData.iCloud`)에 있습니다. dev 컨테이너를 채운 적이 없으므로 (a)로는 아무것도 내려오지 않습니다.
> **실제로 성립하는 경로는 (b) 파일 복사뿐입니다.** 절차는 [phase-0a-d-device-test.md](./phase-0a-d-device-test.md) §6-1.

> ⚠️ **`lineData` 는 `@Attribute(.externalStorage)` 입니다** ([DrawingSchemaV3.swift](../Domain/Domain/Sources/SwiftData/Model/DrawingSchemaV3.swift)).
> 큰 블롭은 sqlite 파일 **바깥**에 별도 파일로 저장되므로, `Carve.sqlite` 하나만 복사하면 필사 데이터가 누락됩니다.
> **`Library/Application Support/` 디렉터리 전체**를 가져와야 합니다.

> **S5는 "실데이터 1회 추출"만 실기기 의존이고, 파일만 확보되면 이후 반복·자동화는 시뮬레이터에서 가능합니다.**

저장소 위치: `<data container>/Library/Application Support/Carve.dev.sqlite`
(Debug는 `CLOUDKIT_CONTAINER_ID`에 `dev`가 있어 `Carve.dev.sqlite`로 분기 — [SwiftDataContextProvider.swift:26](../Domain/Domain/Sources/SwiftData/SwiftDataContextProvider.swift))

### 18-5. S0에서 나온 후속 영향

| # | 발견 | 영향 |
|---|---|---|
| 1 | **시뮬레이터는 CloudKit 미러링이 전혀 동작하지 않음** — 빌드 entitlement가 비어 있고(`codesign -d --entitlements` → `<dict></dict>`) `CKAccountStatusNoAccount` | **Phase 1 V4 스키마의 CloudKit 제약(전 속성 optional 등)은 시뮬레이터로 검증 불가.** → **Phase 0A-D로 이월** |
| 2 | Phase 2의 `LazyVStack → VStack`은 비용을 **스크롤에서 진입으로 이동**시킴 | S3/S4 통과 기준을 (C)표가 아니라 **(B)표 기준으로 엄격히** 잡아야 함. 진입 시 +37MB / 0.31s 가 현재 값 |
| 3 | 장 전환 시 메모리 미회수는 **기존부터 존재** | 새 설계 평가 시 이 baseline을 빼고 판단할 것 |
| 4 | iPad 시뮬레이터 런타임이 iOS 26.2뿐 | "저사양 iOS 17 iPad" 리스크는 **시뮬레이터로도 보완 불가**. 필요 시 해당 런타임에 iPad 디바이스를 별도 생성해야 함 |
| 5 | `undoManager is deprecated` 경고 3건 잔존, `CombinedCanvasView`는 주석 처리 상태 | 과거 롤백의 잔해. Phase 3 착수 전 정리 판단 필요 |
| 6 | tuist PATH 버전(4.44.3) ≠ 프로젝트 고정(4.39.0) | CI/재현 환경에서 어느 쪽이 쓰이는지 확인 필요 |

### 18-6. 시뮬레이터에 남은 상태

S0-5 검증으로 만든 `BibleDrawing` 행 1개(창세기 1:1, lineData 388B)가
시뮬레이터 `Carve.dev.sqlite`에 남아 있습니다. 제거하려면:

```bash
xcrun simctl uninstall <UDID> kr.co.carve.leetaek
```

---

## 19. 부록 C — Phase 0A-S1 / S2 실측 결과

> 환경: Xcode 26.3 / tuist 4.39.0 / iPad mini (A17 Pro) 시뮬레이터 iOS 26.2
> 앱 코드 변경 없음, 커밋 없음. 신규 테스트 2파일 추가(미커밋).

### 19-1. 결과 요약

| ID | 결과 | 설계 영향 |
|---|---|---|
| S1-1 | ✅ `randomSeed` 라운드트립 보존 | `StrokeIdentityKey` 성립 |
| S1-2 | ⚠️ **분할 + 마스킹 동시** | §7-4 전제 절반 반전. 단 결론은 강화 |
| S1-3 | ⚠️ 완전히 지운 stroke는 **제거됨** | §7-5 전제 반전 → 저장 가드 문제로 재정의 |
| S1-4 | ✅ IdentityKey 구성요소 전부 불변 | §7-3 1번 규칙 신뢰도 상승 |
| S1-5 | ✅ `mask` / `maskedPathRanges` 보존 | `ContentSignature` 성립 |
| S2 | ✅ **`textLineRanges` 실현 가능** | §9-3 fallback 불필요 |

### 19-2. S1-4 — 지우개 전후 비교 (실측)

| 항목 | 지우기 전 | 지우기 후 (두 조각 모두) |
|---|---|---|
| `randomSeed` | 956091164 | 956091164 (동일) |
| `path.creationDate` | 1788508117.7905478 | 동일 |
| `path.count` | 10 | 10 |
| control points | — | **10개 전부 값까지 동일** |
| `transform` | identity | identity |
| `renderBounds.width` | 264 pt | 112 / 112 pt (**축소**) |
| `mask` | nil | 각각 다른 clip 영역 |

### 19-3. S2 — `Text.LayoutKey` 타입 구조

바이너리 swiftmodule 에서 symbol graph 추출로 확정
(`xcrun swift-symbolgraph-extract -module-name SwiftUICore`).
**textual `.swiftinterface` 로는 판정 불가**했습니다.

| 타입 | 노출 멤버 | availability |
|---|---|---|
| `Text.LayoutKey.Value` | `= [Text.LayoutKey.AnchoredLayout]` | iOS 17.0 |
| `AnchoredLayout` | `origin: Anchor<CGPoint>`, `layout: Text.Layout` | iOS 17.0 |
| `Text.Layout` | Collection of `Line`, `count`, `isTruncated`(iOS 18) | iOS 17.0 |
| `Text.Layout.Line` | `origin`, `typographicBounds`, Collection of `Run` — **문자 범위 없음** | iOS 17.0 |
| **`Text.Layout.Run`** | **`characterIndices`**, `typographicBounds`, `layoutDirection` | **iOS 17.0** |
| `Text.Layout.RunSlice` | `characterIndices`, `run`, `indices: Range<Int>` | iOS 17.0 |
| `Text.Layout.CharacterIndex` | `Strideable`(Stride = Int) · `Comparable` · `Hashable` · `Sendable` | iOS 17.0 |
| `Text.Layout.TypographicBounds` | `origin`, `width`, `ascent`, `descent`, `leading`, `rect` | iOS 17.0 |

런타임 검증 (창세기 1:2, 46자, 폭 180pt, system 17pt):

```
lines = 4
ranges = [0...12, 13...25, 26...39, 40...45]     ← 빈틈·겹침 없이 0..45 전체 분할
lineOrigins = [(0,16.0), (0,36.287), (0,56.574), (0,76.861)]
```

### 19-4. 추가된 테스트

| 파일 | 테스트 수 | 내용 |
|---|---|---|
| `Feature/CarveFeature/Tests/PencilKitDataModelTesting.swift` | 8 | S1-1 ~ S1-5. 실측 블롭 3개(690B/1266B/1083B)를 base64 상수로 내장 |
| `Feature/CarveFeature/Tests/TextLayoutKeyProbeTesting.swift` | 2 | S2. `lineCharacterRanges(from:)` 는 §9-3 구현에 그대로 재사용 가능 |

전체 테스트: **67/67 통과** (기준선 57 + 신규 10). SwiftLint 위반 0.

> **rev.9 정정:** 파일별 분포는 **8 / 2** 입니다. rev.8 표의 `7 / 3` 은 오기였습니다 —
> 두 파일은 `eef5ac1c` 이후 변경된 적이 없고, 그 커밋 시점에도 `@Test` 선언은 8과 2였습니다.
> **합계 10과 "67/67 통과" 라는 당시 실행 기록 자체는 그대로 유효합니다.**

> 블롭을 base64 상수로 내장한 이유: 테스트 타깃에 resource 설정이 없어
> **프로젝트 설정 변경을 피하기 위함**입니다 (AGENTS.md: 빌드 설정 변경 금지).

### 19-4-1. rev.9 — 그 이후 추가된 테스트 ★

> 아래 표는 저장소의 `@Test` / `func test_` 선언을 직접 센 값입니다.
> (`.build` 및 동기화 충돌 사본인 `"… 2.swift"` 파일은 집계에서 제외했습니다.)
> **선언 수 76은 이후 전량 실행으로 확정됐습니다 — §19-4-2.**

| 커밋 | 파일 | 증분 |
|---|---|---|
| `7ba5bc46` | `Feature/CarveFeature/Tests/DrawingErasePersistenceTesting.swift` (신규) | **+6** |
| `19be99ea` | `Feature/ChartFeature/Tests/DrawingWeeklySummaryStateTesting.swift` (3 → 6) | **+3** |

**번들별 선언 수**

| 번들 | rev.8 기준선 | 현재 선언 |
|---|---:|---:|
| DomainTest | 31 | 31 |
| CarveFeatureTest | 8 | **24** |
| CarveToolkitTest | 6 | 6 |
| ChartFeatureTest | 6 | **9** |
| SettingsFeatureTest | 3 | 3 |
| UIComponentsTest | 3 | 3 |
| **합계** | **57** | **76** |

```
76 = 기준선 57 + S1/S2 검증 10 + 지우개 회귀 6 + 동점 규칙 3
```

**각 커밋이 남긴 그 시점의 실행 기록** (전체 76건을 한 번에 돌린 기록은 **없습니다**):

| 커밋 | 실행 범위 | 결과 |
|---|---|---|
| `19be99ea` | `-scheme ChartFeatureTest`, iPad mini (A17 Pro) / iOS 26.2, 7회 반복 | 9 tests 전부 통과 |
| `7ba5bc46` | `CarveFeatureTest` | 18 → 24. 수정 전 코드로 되돌리면 저장/대표선택/trailing 저장 테스트가 실제로 실패함을 확인 |

### 19-4-2. rev.9 — 76건 전량 실행 결과 ★ 새 회귀 기준선

> 실행 환경: **Xcode 26.3 (Build 17C529) / Swift 6.2.4 / tuist 4.39.0 /
> iPad mini (A17 Pro) 시뮬레이터 iOS 26.2** — §18-1 기록 환경과 동일.
> `DerivedData` 삭제 후 클린 빌드, `xcodebuild test -scheme Carve-Workspace`.

```
** TEST SUCCEEDED **     실패 0
```

| 번들 | rev.8 기준선 | 실행 결과 |
|---|---:|---:|
| DomainTest | 31 | **31** (Swift Testing 29 + XCTest 2) |
| CarveFeatureTest | 8 | **24** |
| CarveToolkitTest | 6 | **6** |
| ChartFeatureTest | 6 | **9** |
| SettingsFeatureTest | 3 | **3** |
| UIComponentsTest | 3 | **3** |
| **합계** | **57** | **76** |

> 76 은 rev.9 시점 기록입니다. **현재 기준선은 82 입니다 — 아래 참조.**
> §18-2의 57은 rev.8 시점 기록으로 보존합니다.

**rev.10 — Phase 0B fixture 추가 후: 82/82** ★

| 번들 | rev.9 | rev.10 | 증분 |
|---|---:|---:|---|
| CarveFeatureTest | 24 | **30** | +6 (legacy 좌표계 fixture, §20-3) |
| 그 외 5개 번들 | 52 | 52 | — |
| **합계** | **76** | **82** | **+6** |

82 는 rev.10 시점 기록입니다.

**rev.11 — Phase 0B 진행에 따른 누적** ★

| 번들 | rev.10 | +`ChapterLayoutBuilder` | +소유권/승계 |
|---|---:|---:|---:|
| DomainTest | 31 | 44 | **54** |
| CarveFeatureTest | 30 | 30 | **47** |
| 그 외 4개 번들 | 21 | 21 | 21 |
| **합계** | **82** | **95** | **122** |

커밋별: `f5206814` 82 → 95 (+13) · `0c071d29` 95 → 122 (+27).

122 는 rev.11 시점 기록입니다.

**rev.12 — Phase 0B 완료 · S4 후: 155/155** ★

| 번들 | rev.11 (122) | +reflow (`565dfe69`) | +S4 (`b53cbfd8`) |
|---|---:|---:|---:|
| DomainTest | 54 | **63** (Swift Testing 61 + XCTest 2) | 63 |
| CarveFeatureTest | 47 | **71** | 71 |
| CarveToolkitTest | 6 | 6 | 6 |
| ChartFeatureTest | 9 | 9 | 9 |
| SettingsFeatureTest | 3 | 3 | 3 |
| UIComponentsTest | 3 | 3 | 3 |
| **합계** | **122** | **155** | **155** |

커밋별 누적: 82 → 95 (`f5206814`) → 122 (`0c071d29`) → **155** (`565dfe69`) → 155 유지 (`b53cbfd8`).

> `b53cbfd8` 은 **테스트를 추가하지 않았습니다.** S4 하네스는 Debug 전용 UI 이고,
> 그 판정은 단위 테스트가 아니라 **하네스 자체의 HUD 측정**으로 얻습니다 (§20-4).
> 대신 같은 커밋에서 **릴리즈 누출 확인**(CarveFeature Release 빌드의 spike `.o` 7개에 실제 심볼 0개)을 했습니다.

155 는 rev.12 시점 기록입니다.

**rev.13 — Phase 1 (V4 스키마) 추가 후: 175/175** ★

| 번들 | rev.12 | +V4 스키마 (`b68b6101`) |
|---|---:|---:|
| DomainTest | 63 | **83** (Swift Testing 81 + XCTest 2) |
| 그 외 5개 번들 | 92 | 92 |
| **합계** | **155** | **175** |

증분 20건은 V3 → V4 마이그레이션 검증 11건 + §10-3 등가 검증 9건입니다.

> **현재 회귀 기준선은 175/175 입니다.** 이후 어느 단계에서든 175 미만 통과 또는 실패 1건 이상이면 회귀입니다.
> 실행 환경은 위와 동일 (Xcode 26.3 / Swift 6.2.4 / iPad mini (A17 Pro) iOS 26.2).
> 구성은 **Swift Testing 173 + XCTest 2** 입니다.

**같이 확인된 것**

- §18-2의 flaky 예외가 사라졌습니다. 다만 이번은 **1회 실행**이므로, 비결정성 부재의 근거는
  반복 실행이 아니라 `TopChapterRank` 가 전순서라는 **구조적 성질**입니다 (§20-1).
  `19be99ea` 당시 7회 반복 통과 기록이 별도로 있습니다.
- 로그의 `error:` 3건은 전부 런타임 노이즈입니다 — PencilKit 필기인식 권한
  (`com.apple.corehandwriting Code=-1003`), CoreData persistent history 정리.
  빌드·테스트 실패가 아닙니다.

**전량 실행에서 드러난 기존 결함 1건 (별도 수정)**

`UIComponentsTest` 만 테스트 타깃에 프레임워크 의존성이 빠져 있어
(`makeTestTarget` 의 `dependencies` 기본값이 `[]`), 클린 빌드에서
`@testable import UIComponents` 가 해석되지 않았습니다.
나머지 6개 모듈은 모두 `dependencies: [.target(name: projectName)]` 를 넘깁니다.
증분 빌드에서는 다른 타깃이 먼저 만들어 둔 프레임워크를 찾아 우연히 통과하다가
클린 빌드에서 드러난 잠복 결함입니다. 같은 패턴으로 맞췄습니다
([Supports/UIComponents/Project.swift](../Supports/UIComponents/Project.swift)).

> ⚠️ **툴체인 주의 — Xcode 26.3 이 아니면 빌드되지 않습니다.**
> TCA 는 `Tuist/Package.swift` 에 `exact: "1.20.2"` 로 고정돼 있는데,
> 이 버전은 **Swift 6.3.3 이상에서 컴파일되지 않습니다**
> (`WritableKeyPath<Root, BindingState<Value>>` 의 `Sendable` 미충족 — Xcode 26.6 에서 실측).
> Xcode 27 은 여기에 더해 의존성 배포 타깃(iOS 12/13, macOS 10.15)을 거부합니다.
> **§18·§19 의 모든 수치는 Xcode 26.3 / Swift 6.2.4 기준입니다.**

### 19-5. S1에서 확인하지 못한 것

- **실제 Apple Pencil 지우개** — 시뮬레이터 마우스(`.anyInput`) 입력으로만 확인 → **D3에서 재확인**
- **`PKEraserTool(.vector)` 동작** — 이번 범위 밖. 위 결론은 `.bitmap` 한정
- **`CharacterIndex` 의 단위** (Character vs UTF-16) — 한글 46자에서 `String.count == utf16.count` 라 구분 불가
- **빈 `PKDrawing` fixture** — §7-5의 저장 가드 때문에 DB에 도달하지 않아 확보 실패
  > ✅ **rev.9 해소:** `7ba5bc46` 이 저장 가드를 제거해 stroke 0개인 drawing 도 DB에 도달합니다.
  > 커밋이 남긴 실측: 획 1개일 때 `ZBIBLEDRAWING(verse 3)` `length 515 / strokes 1` → 전부 지운 뒤 **`length 317 / strokes 0`**
  > (수정 전에는 515 그대로였음). 빈 `PKDrawing` 블롭 fixture 를 이제 시뮬레이터에서 확보할 수 있습니다.

---

## 20. 부록 D — rev.9에서 반영한 코드 수정 2건

> Phase 0A-S0 / S1 검증 과정에서 **드러난** 기존 코드 버그를, 새 아키텍처를 기다리지 않고 먼저 고친 기록입니다.
> 둘 다 **기존 N-Canvas 구조 위의 수정**이며, §4~§11의 새 설계는 여전히 미구현입니다.

> **제목은 rev.9 시점의 것입니다.** 이후 §20-3(rev.10, D8 legacy 추출)과 §20-4(rev.12, S4 하네스)가
> 덧붙었습니다. 절 번호를 바꾸면 문서 안 상호 참조가 깨지므로 번호는 그대로 두고 뒤에 이어 붙입니다.

| 커밋 | 파생 | 제목 |
|---|---|---|
| `19be99ea` | S0-2 | 주간 요약 topChapter 동점 시 비결정적 결과 수정 |
| `7ba5bc46` | S1-3 | 지우개로 전부 지운 필사 내용이 저장되지 않던 문제 수정 |
| `0e9a8449` | D8 | 실기기 legacy 데이터 추출과 Phase 0B fixture (rev.10, §20-3) |
| `b53cbfd8` | S4 | 스크롤 A/B spike 하네스 (rev.12, §20-4) — 버그 수정이 아니라 **검증 산출물**입니다 |

### 20-1. `19be99ea` — 주간 요약 동점 tie-break (S0-2 파생)

**증상.** §18-2의 회귀 기준선(57/57)을 재현할 때
`ChartFeatureTest / DrawingWeeklySummaryStateTesting` 의 1건이 5회 중 1회꼴로 실패했습니다.

**원인.** `merged.max(by: { $0.value < $1.value })` 는 최댓값이 **동점**이면
`Dictionary` 순회 순서에 결과가 좌우되고, Swift 해시 시드는 프로세스마다 달라 비결정적입니다.
당시 테스트 데이터가 우연히 동점(창세기 2+3=5, 요한복음 1+4=5)이었습니다.

**수정.** 정렬 키 `TopChapterRank(Comparable)` 를 도입해 **전순서(total order)** 로 1위를 뽑습니다
([DrawingWeeklySummaryFeature.swift:78](../Feature/ChartFeature/Sources/Chart/DrawingWeeklySummaryFeature.swift)).

```
① 합계 내림차순
② 성경 순서 오름차순   (BibleTitle.allCases 인덱스)
③ 장 번호 오름차순
```

> ②를 고른 이유: 성경 순서는 이미 `BibleTitle.allCases` 나열 순서로 도메인에 정의돼 있어
> 새 규칙을 만들 필요가 없고, 사용자가 목록·네비게이션에서 보는 순서와도 일치해
> "동점이면 앞쪽 권" 이라는 결과를 설명하기 쉽습니다.

**테스트.** 기존 테스트 데이터를 동점이 아니게 조정해 "합산 1위" 자체를 검증하도록 바꾸고,
동점 규칙은 **별도 3건**으로 명시 검증합니다 (성경 순서 tie-break / 같은 권 내 장 번호 tie-break /
삽입 순서를 50회 섞어도 결과 동일).

**설계 문서와의 관계.** 이 수정은 §18-2의 회귀 기준선 예외를 제거할 뿐이며,
단일 Canvas 설계 자체에는 영향이 없습니다. 다만 §7-3의
**"동일 후보가 복수일 때는 결정적 순서로 선택한다"** 와 §8-7의
**"`mainDrawing()` 을 결정적으로 만들 것"** 이 요구하는 것과 **같은 유형의 결함**이므로,
새 구현에서도 Dictionary/Set 순회 순서에 결과를 맡기지 않도록 주의해야 합니다.

### 20-2. `7ba5bc46` — 지우개 저장 누락 (S1-3 파생)

**증상.** 한 절의 획을 지우개로 전부 지운 뒤 앱을 재기동하면 지웠던 획이 되살아납니다
(§7-5에 기록된 그 버그).

**원인.** §7-5 표의 두 곳이 겹쳐 있었습니다 — 저장 가드(`containsPKStroke`)와 leading-edge throttle.

**수정 요약.** 상세 표는 §7-5의 "✅ 분리 수정 완료" 절에 있습니다. 핵심 판단 세 가지만 다시 적습니다.

| 판단 | 내용 |
|---|---|
| `containsPKStroke` **의미 불변** | `"stroke 가 있는가"` 는 그 자체로 옳고, [DrawingDataMigrationPlan.swift:40](../Domain/Domain/Sources/SwiftData/DrawingDataMigrationPlan.swift) 의 V1→V2 마이그레이션이 **빈 레거시 레코드 삭제 판단에 같은 의미를 사용**합니다. 정의를 "가시 획" 으로 바꾸면 마이그레이션 동작이 조용히 달라지므로 **호출부만** 수정 |
| `canvasViewDidEndUsingTool` **사용 불가** | PencilKit이 획을 `drawing` 에 반영하기 **전에** 호출되어 빈 drawing 이 저장됨을 시뮬레이터에서 확인. 그래서 pencil-up 델리게이트 대신 **trailing-edge debounce** 를 사용 |
| 대표 drawing 선택 필터 제거 | `setSentence` 가 획 유무로 후보를 거르면 "전부 지운 최신 기록" 이 후보에서 빠지고 더 오래된 기록이 대표로 승격되어 **지운 결과가 되살아난 것처럼 보임**. 선택 규칙을 도메인 `mainDrawing()`(isPresent 우선 → updateDate 최신)과 일치시킴 |

> 세 번째 항목은 §8-7의 **"`clear` 는 행을 삭제하지 않는다 ★"** 와 **정확히 같은 함정**입니다.
> 그때는 "행 삭제 → 과거 회차 승격" 이었고, 여기서는 "필터로 후보 제외 → 과거 회차 승격" 이었습니다.
> 원인이 삭제냐 필터냐만 다를 뿐 결과가 동일하므로, Phase 3 구현에서도
> **"빈 것을 후보에서 빼는" 모든 경로를 의심**해야 합니다.

**변경 파일**

| 파일 | 변경 |
|---|---|
| [CarveDetailFeature.swift](../Feature/CarveFeature/Sources/Presentation/Carve/CarveDetail/CarveDetailFeature.swift) | 저장 경로를 `persistDrawing(_:)`(233행)으로 분리, 획 유무 조건 제거. `setSentence`(116행) 후보 필터 제거 |
| [CanvasView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CanvasView.swift) | `debounceInterval` → `throttleInterval` 로 이름을 실제 동작에 맞추고, `scheduleTrailingSave(for:)`(93행) 추가. **undo 등록은 trailing 경로에서 하지 않음** (기존 undo 동작 유지) |
| [CanvasFeature.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CanvasFeature.swift) | `saveDrawing` 에서 **기록이 없는 절 + 빈 canvas** 조합은 새 행을 만들지 않도록 함(60행). trailing 저장 도입으로 필사하지 않은 절에까지 빈 레코드가 생기는 것을 시뮬레이터에서 확인해 함께 차단 |
| `DrawingErasePersistenceTesting.swift` | 회귀 테스트 6건 신규 |

**손대지 않은 것**

- 비활성(주석 처리) 상태인 `CombinedCanvasFeature` 의 `containsPKStroke` 호출부
  ([CombinedCanvasFeature.swift:141](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasFeature.swift)) —
  Phase 3에서 `ChapterCanvasFeature` 로 재작성될 파일입니다(부록 표).

**Phase 3에서의 흡수** — §7-5의 "Phase 3에서 이 수정이 흡수되는 방식" 표 참조.
trailing debounce 는 §8-1(편집 종료 저장)로, 저장 가드 제거는 §8-2(`.clear` mutation, P7)로,
`strokes.isEmpty` 신규 행 억제는 §8-7(rowID 선발급)로 각각 대체됩니다.

### 20-3. `0e9a8449` — D8 실기기 legacy 데이터 추출과 Phase 0B fixture (rev.10)

**경로.** 개발자 인증서가 폐기되고 유료 멤버십이 만료돼 기기에 개발 빌드를 설치할 수 없었습니다.
게다가 `devicectl` / Xcode *Download Container* 는 **개발 서명으로 설치된 앱**만 접근할 수 있어,
추출 대상인 App Store 판은 애초에 대상 밖이었습니다.
→ **Finder 비암호화 로컬 백업에서 파일을 꺼내는 방식**으로 수행했습니다.
절차는 [phase-0a-d-device-test.md](./phase-0a-d-device-test.md) §6-1.

**추출 결과** (2026-09-05, iPad mini A17 Pro / iOS 27.0 beta)

| 항목 | 값 |
|---|---|
| `ZBIBLEDRAWING` | **225행**, 2025-02-13 ~ 2026-03-23 |
| `ZDRAWINGVERSION` | **전부 1** — D3 "죽은 필드" 진단 실증 |
| `ZLINEDATA` | 인라인 224행(최대 111KB) + 외부저장 1행 |
| `ZBIBLEPAGEDRAWING` | **0행** |
| 디코드 | **225/225 성공** — 현행 PencilKit 으로 전부 읽힘 |
| 파일 누락 | 0 |

**설계에 주는 영향**

| 발견 | 영향 |
|---|---|
| `ZBIBLEPAGEDRAWING` 0행 | `BiblePageDrawing` 은 실사용 데이터가 **전무**합니다. 부록의 "캐시/복구 전용 격하 → 장기 제거" 를 **마이그레이션 부담 없이** 수행할 수 있습니다 |
| `drawingVersion` 전부 1 | D3 대로 죽은 필드입니다. P3 가 이 필드에 의미를 부여할 때 **기존 값 1을 legacy 표식으로 쓸 수 있습니다** |
| 225건 전부 디코드됨 | PencilKit 인코딩 호환성 문제 없음. Phase 0B 라운드트립 입력으로 그대로 사용 가능 |
| 빈 drawing 0행 | §7-5 "빈 절" fixture 는 **실데이터로 확보하지 못했습니다.** `PKDrawing()` 합성으로 대체해야 합니다 |

**확보하지 못한 것 — §10-2 는 여전히 미해결**

225건은 **전부 절 로컬 좌표**입니다. 1.2.0 배포 기간(2025-12-08 ~ 2025-12-30)에
이 기기로 필사한 기록이 **0건**이기 때문입니다 (월별 분포에서 2025-12 이 비어 있음).
따라서 절대좌표 fixture 는 실데이터가 아니라
`LegacyDrawingFixture.absoluteVariant(of:verseRect:)` 로 **합성**합니다.
합성식은 `normalizedForVerseRect` 자신의 역변환이므로 형식은 정확하지만,
**"실사용자에게 절대좌표 데이터가 실제로 얼마나 있는가" 는 답하지 못합니다.**

> 다만 1.2.0 이 22일간 배포됐던 것은 확인됐으므로(§10-2), **존재한다고 가정하고 설계해야 합니다.**

**파생 산출물**

| 파일 | 내용 |
|---|---|
| `Feature/CarveFeature/Tests/LegacyDrawingFixture.swift` | 실사용 blob 5건 (base64 내장, 본문 정보 제거) + 절 rect 시나리오 3종 |
| `Feature/CarveFeature/Tests/LegacyCoordinateTesting.swift` | 테스트 6건 — 인코딩 호환성 2 · 정상 복원 1 · **D3 실패 모드 2** · 오탐 없음 1 |

D3 실패 모드 2건의 실측 근거는 §10-2-1 을 보십시오.

> **개인정보:** 추출 원본은 실사용자의 필사 기록입니다. 저장소 밖(`~/carve-device-dump/`)에 두고
> 커밋하지 않았습니다. fixture 에 넣은 5건은 권·장·절·날짜 등 식별 메타를 제거했습니다.

### 20-4. `b53cbfd8` — Phase 0A-S4 스크롤 A/B spike 하네스 (rev.12)

> 실행 환경: **Xcode 26.3 / iPad mini (A17 Pro) 시뮬레이터 iOS 26.2.**
> 176절 mock layout, 총 높이 **16184pt**. 측정 결과 요약은 §11 "S4 실행 결과".

#### 하네스 구조

Debug 전용이며 **SwiftData·실사용 Drawing 과 연결되지 않습니다**(§11 "실험 범위").
파일 단위 `#if DEBUG` 로 릴리즈 빌드에서 완전히 제외됩니다.

| 파일 | 역할 |
|---|---|
| [CanvasScrollSpikeView.swift](../Feature/CarveFeature/Sources/Debug/CanvasScrollSpikeView.swift) | 루트 화면. 모드 전환·토글·헤더 애니메이션 |
| [CanvasScrollSpikeHosting.swift](../Feature/CarveFeature/Sources/Debug/CanvasScrollSpikeHosting.swift) | **A / B 두 호스팅 구조의 실체** |
| [CanvasScrollSpikeMetrics.swift](../Feature/CarveFeature/Sources/Debug/CanvasScrollSpikeMetrics.swift) | 자체 측정기 (아래) |
| [CanvasScrollSpikeContent.swift](../Feature/CarveFeature/Sources/Debug/CanvasScrollSpikeContent.swift) | mock layout·drawing 생성 |
| [CanvasScrollSpikeColumn.swift](../Feature/CarveFeature/Sources/Debug/CanvasScrollSpikeColumn.swift) | 텍스트 컬럼 + 프로브 마커 |
| [CanvasScrollSpikeStore.swift](../Feature/CarveFeature/Sources/Debug/CanvasScrollSpikeStore.swift) | 상태 + launch argument 파싱 + 무인 시나리오 |
| [CanvasScrollSpikeHUD.swift](../Feature/CarveFeature/Sources/Debug/CanvasScrollSpikeHUD.swift) | 측정값·게이트·판정 표시 |

```
A  SwiftUI ScrollView + content-sized PKCanvasView overlay
   캔버스는 isScrollEnabled = false, inset/offset 0, zoom 1 고정.
   StableCanvasView 수준의 매-레이아웃 정규화는 "A정규화" 토글로 분리해 유무를 비교할 수 있다.

B  PKCanvasView 가 유일한 UIScrollView.
   텍스트는 UIHostingController 로 캔버스의 scroll content **내부**에 삽입.
   → offset 동기화 코드가 한 줄도 없다.
     §11 이 금지한 "별개 SwiftUI 텍스트에 contentOffset 전달" 을 구조적으로 회피한 지점이다.
```

진입점은 [App.swift](../App/CarveApp/Sources/App/App.swift) 의 `WindowGroup` 안 `#if DEBUG` 분기 1건입니다
(하네스 외부에서 수정한 **유일한** 기존 파일).

```bash
xcrun simctl launch <UDID> kr.co.carve.leetaek -CanvasScrollSpike
```

#### 측정을 하네스가 직접 합니다

통과 기준 1("스크롤 전후 동일 content point 오차 ≤ 1pt")은 **눈대중으로 판정할 수 없습니다.**
HUD 가 매 프레임 델타를 계산해 표시하고 peak 를 누적하며, 임계 초과 시 색으로 구분합니다.

> **측정에 `contentOffset` 산술을 쓰지 않습니다 — 그것이 검증 대상이기 때문입니다.**
> 세 값(잉크 / 텍스트 마커 / viewport 원점) 모두 **UIKit `convert(_:to:)`** 로만 얻습니다.
> 컨테이너 이동은 `viewportOrigin` 을 빼서 제거합니다. 이 항이 없으면 헤더 접힘 애니메이션만으로
> **105pt 짜리 가짜 FAIL** 이 납니다 — 그 근거와 기준 1 의 정의는 §11 에 적었습니다.

| 프로브 | 위치 |
|---|---|
| v1 / v88 / v176 | 장 상단·중간·하단. 세 곳 전부 0.00 |

#### launch argument 무인 시나리오

터치 주입 수단이 없어 시나리오를 인자로 구동합니다. 결과가 HUD 로그로 남아
**스크린샷 한 장에 시나리오 전체 판정이 찍힙니다.**

| 인자 | 뜻 |
|---|---|
| `-CanvasScrollSpike` | 하네스 진입 (필수) |
| `-CanvasScrollSpikeMode A` / `B` | 호스팅 구조 선택 (기본 B) |
| `-CanvasScrollSpikeAuto` | 8개 시나리오 무인 실행 |
| `-CanvasScrollSpikeJump <pt>` | 지정 offset 으로 이동해 정지 (깊은 위치 렌더 확인) |
| `-CanvasScrollSpikeLeftHanded` | 통과 기준 4 |
| `-CanvasScrollSpikeNarrow` | 통과 기준 3 (필사 컬럼 폭 축소) |
| `-CanvasScrollSpikeAnyInput` | `.anyInput` ↔ `.pencilOnly` |
| `-CanvasScrollSpikeNormalizeA` | A 의 "A정규화" 활성화 |

#### ⚠️ 환경 제약 2건 — 고치지 않고 기록합니다

| # | 제약 | 영향 | 왜 해소하지 않았는가 |
|---|---|---|---|
| 1 | 시뮬레이터 **터치 주입 도구가 `xcode-select` 설정 때문에 사용 불가** | §11 기준 2 의 **관성 fling**, 기준 5 의 **탭/롱프레스 동작** 미검증 (기준 5 는 `tapGR=1`·`longGR=3` 이 draw/pan 과 동시 활성임을 **구조로만** 확인) | 해소하려면 `sudo xcode-select` 로 **시스템 설정을 바꿔야** 합니다. 검증 목적으로 개발 머신의 전역 툴체인 선택을 변경하지 않았습니다 |
| 2 | **`vmmap` 권한 오류** | §11 기준 11 의 A/B **상대 메모리 비교 미측정** | 시뮬레이터 수치는 애초에 △(상대 비교 전용)이고, 절대값은 D5 에서 실기기로 얻습니다 |

> 두 제약 모두 **실기기(Phase 0A-D)에서는 성립하지 않습니다.** D1/D2 를 수행할 때
> 같은 하네스를 실기기에서 그대로 돌리면 fling·탭/롱프레스·메모리가 함께 해소됩니다 (§13).

#### 이 커밋이 설계에 남긴 것

| 항목 | 반영 위치 |
|---|---|
| A/B 가 수치로 구별되지 않음 → **판정 D1/D2 로 이월** | §11 · §12 · §13 |
| 기준 1 의 "오차" 정의 (컨테이너 이동 배제) | §11 |
| B 의 캔버스 좌표 = layout 좌표 + `columnOrigin` | §5 |
| B 의 하단 safe area 미반영 (`contentInsetAdjustmentBehavior = .never`) | §5 (신규 미결) |
| `StableCanvasView` 가 별도 파일이 아니라는 정정 | §2 D5 · 부록 |
| S3 잔여분이 "실측 줄 수" 로 좁혀짐 | §13 · §16 |

### 20-5. `b68b6101` — Phase 1 V4 additive schema (rev.13)

**범위.** §13 이 규정한 대로 optional 필드만 추가하고 legacy 자동 변환은 하지 않습니다.
UI·Canvas 구조 배선 없음.

| 추가 필드 | 형태 | 설계 |
|---|---|---|
| `layoutMetadataData` | `Data?` · `@Attribute(.externalStorage)` | §10-1 — `DrawingLayoutMetadata` blob |
| `rowUUID` | `String?` | §8-7 — **신규 행에만** 발급. legacy 행은 `nil` 유지 |

> **`drawingVersion` 은 새 필드가 아닙니다.** §10-1 의 코드 블록이 추가 필드처럼 적어 두었으나
> V2 부터 존재하며, §20-3 이 "죽은 필드" 로 진단한 그것입니다. V4 는 새로 만들지 않고
> **의미만 확정**했습니다 (nil/1 = legacy, 2 = verse local + top-left, 3 = verse local + underline anchor).

**마이그레이션은 `MigrationStage.lightweight` 한 줄입니다.**
`drawingVersion` 을 읽거나 쓰는 코드, 좌표를 만지는 코드가 한 줄도 없습니다 (§10-2).
legacy 행에 `rowUUID` 를 소급 발급하지도 않습니다 — 두 기기가 서로 다른 UUID 를 부여할 수 있고,
단순 조회가 쓰기를 유발해 비파괴 원칙(§9-4)을 깨기 때문입니다.

**typealias 이동.** `BibleDrawing` / `BiblePageDrawing` 별칭과 `Array.mainDrawing()` 확장을
V3 파일에서 V4 파일로 옮겼습니다. 별칭은 "현재 스키마" 를 가리키는 표현이지 V3 의 일부가 아니며,
V3 에 두면 그 파일이 V4 타입을 조용히 재지정하는 모양이 됩니다.
이제 V3 는 V1·V2 와 마찬가지로 **동결된 과거 스키마 정의**만 담습니다.

> §8-7 이 요구하는 **결정적 `mainDrawing()`**(updateDate → rowID 사전순 tie-break)은
> 적용하지 않았습니다. 행 주소지정 재배선과 함께 가야 의미가 있어 **Phase 3 범위**입니다.

#### 마이그레이션을 실제로 태워 검증했습니다

스키마만 정의하고 "lightweight 니까 되겠지" 로 끝내지 않았습니다.
임시 파일에 **V3 스키마로** store 를 만들어 데이터를 넣고 닫은 뒤,
**같은 파일을 앱과 동일한 표현으로** 다시 열었습니다.

| 확인 | 결과 |
|---|---|
| 기존 행 생존 · 필드 보존 | ✅ |
| `lineData` 바이트 동일 | ✅ 실사용 legacy blob 이 마이그레이션 후에도 `PKDrawing` 으로 디코드됨 |
| `.externalStorage` 경로 | ✅ **1,869,327 byte blob 이 `_EXTERNAL_DATA` 로 실제 승격**된 것을 확인하고 마이그레이션 후 파일 생존까지 단언 |
| 새 필드 | ✅ 둘 다 `nil` |
| **`drawingVersion` 불변** | ✅ 1은 1로, nil은 nil로. 2/3 이 나타나지 않음을 별도 확인 |

> 부수 실측: `.externalStorage` **승격 임계값은 1MB 근방**입니다 (934KB 는 인라인으로 남음).

#### §10-3 등가 검증 — Phase 1 의 존재 이유

> "V4 저장소를 유지한 채 flag 를 껐을 때 기존 N Canvas 경로가 정상 동작해야 한다.
> Phase 3 의 유일한 안전망이다."

feature flag 가 아직 없으므로 **"flag off = 기존 코드 경로"** 로 치환하고,
저장소는 새로 만든 V4 가 아니라 **V3 에서 실제로 마이그레이션된 V4** 를 썼습니다
— flag off 상황이 정확히 그 상태이기 때문입니다.

그 컨테이너에 기존 `DrawingDatabase` API 를 전부 태웠습니다 (fetch 5종 · `updateDrawings(requests:)` ·
`updateDrawing` · `updateDrawings` · `updatePresentDrawing` · page drawing 2종),
앱 재기동에 해당하는 **재오픈 시 재마이그레이션 없음**까지 확인했습니다.

특히 `updateDrawings(requests:)` 가 legacy 행을 갱신할 때
`drawingVersion == 1` · `layoutMetadataData == nil` · `rowUUID == nil` 이 유지되는지 단언했습니다 —
**기존 경로의 쓰기가 좌표 형식을 거짓말하거나 legacy 행에 rowUUID 를 소급 발급하지 않음**을 고정한 것입니다.

#### ⚠️ CloudKit 미검증 — D7 이월

시뮬레이터에 entitlement 가 없어(§18-5) `cloudKitDatabase` 컨테이너로는 **테스트 자체가 불가능**합니다.
모든 검증은 로컬 파일 store 로 했습니다. 다음은 미검증입니다.

| # | 미검증 항목 |
|---|---|
| 1 | `NSPersistentCloudKitContainer` 가 V4 스키마를 실제로 수용하는지 (optional-only · no-unique 를 **코드상으로만** 만족) |
| 2 | `layoutMetadataData` 의 `.externalStorage` 가 CKAsset 으로 미러링되는지 |
| 3 | 마이그레이션 이후 다른 기기에서 계속 도착하는 **메타데이터 없는 행**의 동작 |
| 4 | `isPresent == true` 복수 존재 충돌 |

> §10-3 이 V4 를 forward-only 로 규정하므로 **배포 판단은 D7 확인 이후여야 합니다.**

#### 남겨둔 것

- **런타임 legacy 판별 경로 전체** (§10-2 7단계) — 지금은 `drawingVersion` 이 legacy 표식으로 읽힐 준비만 됨
- **`layoutMetadataData` 쓰기 경로** — 필드와 라운드트립만 확보. 실제 인코딩·저장은 §8-2 mutation 과 함께 Phase 3
- **`drawingVersion = 3` 승격** — 절을 실제로 편집해 저장할 때만 일어나야 함 (§10-2 정책 5번). 현재 어떤 경로도 2/3 을 쓰지 않음
- **`rowUUID` 선발급 + `activeRowIDs`** 배선 — Phase 3.
  ⚠️ 현재 지정 이니셜라이저의 `rowUUID` 기본값이 `UUID().uuidString` 이라 **새 행은 자동으로 UUID 를 갖습니다**(§10-1 "신규 행 생성 시에만 발급" 과 일치).
  다만 Phase 3 은 저장 **전에** 선발급해 pending 큐 키로 쓰므로, 그 경로에서 기본값 생성에 맡기면 **큐 키와 행 값이 어긋납니다.** 반드시 선발급 값을 인자로 넘겨야 합니다
- **`BiblePageDrawing` 제거 판단** — §20-3 실측상 실데이터 0행이라 부담이 없으나 additive-only 원칙에 따라 Phase 1 에서는 유지. Phase 4 후보
