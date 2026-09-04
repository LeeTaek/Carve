# CarveFeature 단일 Canvas 전환 설계

> 상태: **설계안 (미구현)** · 대상: `Feature/CarveFeature`, `Domain`
> rev.6 — Phase 0A-S0(기준선) 추가. 0A-S / 0B 착수 가능. PencilKit·SwiftData API는 iOS 26.2 SDK 헤더로 확인함.
> 코드 변경·빌드·테스트는 수행하지 않았습니다.
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
| D5 | **스크롤 컨테이너 2개** — `PKCanvasView`는 `UIScrollView`(SDK 확인)인데 SwiftUI `ScrollView` 안에 넣어 offset drift. `StableCanvasView` 460줄과 issue #6의 원인 | [CombinedCanvasView.swift:21](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasView.swift) |
| D6 | **레이아웃 메타데이터 없음** — 어떤 폭/폰트에서 그려졌는지 기록이 없어 G4가 원리적으로 불가능 | [DrawingSchemaV3.swift](../Domain/Domain/Sources/SwiftData/Model/DrawingSchemaV3.swift) |
| D7 | **지우개/undo 저장 누락** — stroke 수 증가시에만 변경 영역 계산, 빈 결과는 skip → 마지막 획 삭제가 DB에 반영 안 됨 | [CombinedCanvasView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasView.swift), [CombinedCanvasFeature.swift:186](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasFeature.swift) |
| D8 | **저장이 원자적이지 않음** — 요청마다 개별 `save()`, 에러를 per-item으로 삼킴 → 부분 갱신 상태 발생 | [DrawingDatabase.swift:97](../Domain/Domain/Sources/SwiftData/DrawingDatabase.swift) |
| D9 | **편집 순서 미보장** — 연속 편집의 비동기 저장이 직렬화되지 않으면 최신 편집이 과거 편집에 덮일 수 있음 | 신규 |

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
    /// 밑줄이 실제 표시되는 영역
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
    let map: [StrokeIdentityKey: Int]      // 획 → verse
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

---

## 6. ChapterLayout — 측정과 게이트

### 6-1. LazyVStack → VStack

전 절의 geometry가 있어야 합성이 성립하므로 비지연 `VStack`으로 전환합니다.

> **메모리는 측정 전까지 단정하지 않습니다.** Canvas 개수는 N → 1로 줄지만,
> ① 176개 Row eager 생성 비용 ② 장 전체 높이 `PKCanvasView`의 tile/Metal 리소스가
> 절약분보다 클 수 있습니다. **Phase 0A에서 실측합니다.**
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

> **이 분리가 없으면 D7이 재발합니다.**
> mask를 제외한 키 하나로 dirty를 판정하면, bitmap 지우개는 identity를 바꾸지 않으므로
> "owner 승계는 성공했지만 지우기가 저장되지 않는" 상태가 됩니다.

### 7-3. 승계 (reconciliation)

편집 때마다 전량 재판정하면 리플로우 후 소유권이 옆 절로 흘러갑니다. 기존 획은 소유권을 **승계**합니다.

1. `StrokeIdentityKey` 완전 일치 → 기존 owner 승계
2. `randomSeed` 또는 `creationTime` 일치 + bounds/path 유사도 높음 → 승계
3. 지우개 분할 후보 → 기존 획과 **공간적으로 가장 많이 겹치는** owner 승계
4. 대응 없음 → 첫 control point의 captureRect로 신규 귀속

동일 후보가 복수일 때는 **결정적 순서**(verse 오름차순 → 겹침 면적 내림차순)로 선택합니다.

> `StrokeIdentityKey`는 공개 API가 보장하는 영구 ID가 **아닙니다.**
> DB에는 이미 절별로 그룹화되어 저장되므로, fingerprint는 **한 편집 세션 안에서 owner를 승계하기 위한 도구**로만 사용합니다.
> 세션이 끊기면 DB의 절별 그룹이 진실이 됩니다.

### 7-4. 지우개 모드 — `.bitmap` 유지로 확정 (U3 해소)

SDK 헤더로 확인된 것은 **API의 존재**이며, 다음 동작은 **구조상 예상되는 것**입니다.
bitmap 지우개가 획을 자르지 않고 마스킹할 것으로 보입니다 — **Phase 0A-S1에서 확인합니다.**

```
PKStroke.mask              "The mask pre-transform that is used to clip the rendering of the stroke."
PKStroke.maskedPathRanges  "parametric parameter ranges of points in strokePath
                            that intersect the stroke's mask."
```

즉 지운 뒤에도 `path` / `creationDate` / `randomSeed`가 보존될 **가능성이 높으며**,
그렇다면 `.bitmap`이 whole-stroke ownership과 충돌하지 않습니다.
분할이 실제로 일어난다면 §7-3의 3번 규칙(공간 겹침)이 주 경로가 됩니다.

`.vector` 전환은 "부분 지우기" UX를 바꾸며, **단일 Canvas 전환과 함께 바꾸면 회귀 원인 분리가 어려워집니다.**
따라서 초기 구현은 `.bitmap`을 유지하고, Phase 0A의 reconciliation spike에서
승계가 실제로 불가능한 것으로 판명될 때만 별도 제품 변경으로 검토합니다.

### 7-5. "빈 절" 판정 — `strokes.isEmpty`를 쓰면 안 됨 ★

완전히 마스킹된 획도 `drawing.strokes`에는 **남아 있습니다.**
따라서 `.clear` 판정을 `strokes.isEmpty`로 하면 "다 지웠는데 clear가 안 나가는" 문제가 생깁니다.

```swift
// ❌ 마스킹된 획이 남아 항상 false
strokes.isEmpty

// ✅ 가시 획 존재 여부
strokes.contains { !$0.renderBounds.isEmpty && !isFullyMasked($0) }
```

> 현재 `containsPKStroke`도 `!drawing.strokes.isEmpty`를 사용합니다
> ([Data+Extension.swift:18](../Supports/CarveToolkit/Sources/Extension/Data+Extension.swift)).
> **기존 코드의 잠재 버그이며, 새 설계에서 함께 고쳐야 합니다.**

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
    // §7-5: strokes.isEmpty 가 아니라 "가시 획 없음"
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

> **정리 대상:** `DrawingDatabase.updateDrawing`은 `actor.update(drawing.id)`를 사용하는데
> 같은 함수 안에서 `drawing.id ?? ""` 로도 씁니다
> ([DrawingDatabase.swift:227,234](../Domain/Domain/Sources/SwiftData/DrawingDatabase.swift)).
> `BibleDrawing`이 `var id: String!` 을 선언해 `PersistentModel`의 `id: PersistentIdentifier`
> (`SwiftData.swiftinterface:555`)와 이름이 겹치면서, 같은 표현이 문맥에 따라 다르게 해석되는 상태로 보입니다.
> 다른 호출부는 모두 `persistentModelID`를 씁니다. **확인 필요이며 Repository 전환 시 정리합니다.**

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

### 9-3. 정책 표

| 상황 | 원인 | 처리 |
|---|---|---|
| 밑줄 수·줄 구성 동일 | — | 밑줄별 분류 후 새 y로 translate |
| writing width 감소 | 폭 축소 | 종횡비 유지 uniform 축소 |
| writing width 증가 | 폭 확대 | **확대하지 않음.** 원래 크기 유지 |
| 줄 수 증가 | 폭 감소 / 폰트 증가 / 자간 증가 | 남는 밑줄은 빈 줄 |
| 줄 수 감소 | 폭 증가 / 폰트 감소 / 자간 감소 | 초과 band는 마지막 간격 연장 + §6-3의 effectiveHeight로 공간 확보 |
| 줄바꿈만 달라짐 | — | `textLineRanges`가 있으면 문자 범위 겹침이 가장 큰 밑줄로 이동 |
| 매핑할 줄 없음 | — | **첫 밑줄 기준으로 보존** + `layoutMismatch` 기록. 임의로 다른 줄에 합치지 않음 (§9-3-1) |
| metadata 없음 (legacy) | — | 무변환 (§10-2) |

> **검증 필요 (Phase 0A-S2):** SwiftUI `Text.LayoutKey.Value`의 line 원소가 줄별 **문자 범위**를 노출하는지.
> 현재 코드는 `$0.origin.y`만 사용합니다([VerseTextFeature.swift:83](../Feature/CarveFeature/Sources/Presentation/Carve/Verse/VerseTextFeature.swift)).
>
> **SDK 헤더로는 판정할 수 없습니다.** SwiftUI의 textual `.swiftinterface`는 부분적이며
> (`onPreferenceChange`, `padding`조차 포함되지 않음) `LayoutKey`도 나타나지 않습니다.
> "없다"의 근거가 되지 못하므로 시뮬레이터 probe로 확인합니다.
>
> 노출하지 않으면 `textLineRanges`는 `nil`로 두고 **index 기반 매칭**으로 fallback합니다.

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

> **확인 필요:** 1.2.0이 실제 사용자에게 배포됐는지 (App Store Connect 버전 이력).
> 배포됐다면 그 기간에 작성되고 덮어쓰이지 않은 행은 **절대좌표**입니다.

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

B. PKCanvasView가 유일한 UIScrollView
   └─ PKCanvasView의 scroll content 내부에
      UIHostingController로 텍스트/밑줄 배치
      · drawingPolicy = .pencilOnly 이면 손가락=스크롤 / 펜슬=필기를 PencilKit이 처리
      · 성공 시 StableCanvasView 대부분 제거 가능
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

| # | 기준 | Sim | Device |
|---|---|:--:|:--:|
| 1 | 스크롤 전후 동일 content point의 stroke 오차 **≤ 1pt** | ✅ | ✅ |
| 2 | 빠른 fling/rebound 후 텍스트·밑줄·Drawing 오차 없음 | ✅ | ✅ |
| 3 | Split View resize 후 재필기 위치가 맞음 | ✅ | ✅ |
| 4 | 왼손잡이 레이아웃 전환 후 좌표 정합 | ✅ | ✅ |
| 5 | 헤더 애니메이션 / 롱프레스 메뉴 / 탭 제스처 동작 | ✅ | ✅ |
| 6 | 앱 재진입·장 변경 후 `contentOffset` 복원이 일관됨 | ✅ | ✅ |
| 7 | live stroke가 pencil-up 순간 확대·이동하지 않음 | ❌ | ✅ |
| 8 | Pencil hover 중 좌표 변화 없음 | ❌ | ✅ |
| 9 | `.pencilOnly`에서 한 손가락 스크롤 가능 | ❌ | ✅ |
| 10 | `allowFingerDrawing == true`일 때 스크롤 방법이 명확함 | ❌ | ✅ |
| 11 | 시편 119편 layout 시간·peak memory (baseline 대비) | △ | ✅ |

△ = 시뮬레이터 수치는 절대값으로 쓸 수 없고 **A/B 상대 비교와 알고리즘 복잡도 확인**에만 사용합니다.

### 판정

```
B가 기능 기준(1~6)을 모두 통과            → B 잠정 채택, 실기기에서 7~11 확인
B에 수정 가능한 gesture 문제만 존재        → B 보완 후 재검증
B에서 text hosting / offset / render 문제  → A 검증
A도 offset drift 재현                     → 저장·Feature 구현으로 넘어가지 않고
                                            호스팅 구조 재설계
```

---

## 12. 미결 결정사항

| ID | 결정 | 선택지 | 상태 |
|---|---|---|---|
| **U1** | cross-verse 획 소유권 | **시작 절에 stroke 전체 귀속** | **확정** (§7-1) |
| **U2** | 절당 다중 행 / 히스토리 | **기존 다중 행과 히스토리 유지** → mutation을 행 주소지정으로 | **확정** (§8-7) |
| **U3** | 지우개 모드 | **`.bitmap` 유지** | **확정** (§7-4) |

미결로 남은 것은 **스크롤 구조(A/B)** 하나이며 Phase 0A spike에서 확정합니다.

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
| **Phase 0A-S0** | **지금** — 나머지 전부의 선행 조건 |
| **Phase 0A-S, Phase 0B** | S0 완료 후 (0B는 S0-1만 있으면 병행 가능) |
| Phase 1 · 2 | 시뮬레이터 검증(0A-S)과 migration 테스트 통과 후 |
| Phase 3 | feature flag 뒤 **구현**까지는 가능. **기본 활성화·배포 판단은 Phase 0A-D 이후** |
| Phase 4 (구 구조 삭제) | 실기기 검증 및 안정화 후 |

---

### Phase 0A-S0 — 기준선 확보 (모든 spike의 선행 조건)

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
| **S4** | 스크롤 A/B 골격 + 통과 기준 1~6 (§11) | 호스팅 구조 잠정 결정 |
| **S5** | legacy `lineData` 회귀 fixture 확보 (dev CloudKit 컨테이너) | Phase 0B 입력 |

> S1은 시뮬레이터에서 `drawingPolicy = .anyInput`으로 마우스 필기가 가능하므로 검증됩니다.
> **PencilKit의 데이터 모델 동작이지 펜슬 하드웨어 동작이 아니기 때문입니다.**
> 다만 실제 Pencil 지우개에서 결과가 다를 수 있으므로 D3에서 재확인합니다.

### Phase 0A-D — 실기기에서만 가능한 검증 (이후)

대상 기기: **iPad mini (A17 Pro)**, **iPad Air (M2)**

| ID | 항목 |
|---|---|
| **D1** | Apple Pencil 입력 — hover 중 offset, live stroke가 pencil-up에 확대·이동하는지 (issue #6 핵심) |
| **D2** | `.pencilOnly`에서 한 손가락 스크롤 / `allowFingerDrawing == true`일 때 스크롤 UX |
| **D3** | 실제 Pencil 지우개로 S1 결과 재확인 |
| **D4** | Apple Pencil 더블탭(지우개 전환), 두 손가락 더블탭(undo) |
| **D5** | 시편 119편 layout 시간·peak memory 실측, 스크롤 프레임 드랍 |
| **D6** | Stage Manager / 외부 디스플레이 (Air M2) |

**보유 기기의 사각지대 — 리스크로 관리:**

| 사각지대 | 영향 | 대응 |
|---|---|---|
| 둘 다 60Hz (ProMotion 없음) | issue #6은 렌더/스크롤 타이밍 이슈라 120Hz에서만 재현될 수 있음 | TestFlight 베타에서 iPad Pro 사용자 확인 |
| 둘 다 8GB, 저사양 기기 없음 | 배포 타깃 iOS 17에는 저메모리 iPad 포함. 시편 119편 메모리 리스크는 그쪽이 최대 | 베타 단계 검증 항목으로 이월 |

**산출물:** A/B 최종 결정, 승계 전략 확정, 메모리·성능 수치

### Phase 0B — 순수 로직과 회귀 fixture
- `ChapterLayoutBuilder` (2-pass, 안정 signature 포함)
- owner resolver / reconciler / line band reflow
- **실제 legacy `lineData` 샘플 fixture 확보** ← 회귀 판정의 기준
- UI 변경 없음

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
- `StableCanvasView` 디버그 코드 (~400줄)
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

### 시뮬레이터에서 확인 (Phase 0A-S)

1. S1 — PencilKit 데이터 모델 5항목 (§7-2 / §7-4 / §7-5 확정)
2. S2 — `Text.LayoutKey` probe (§9-3)
3. S3 — 176절 `ChapterLayout` 정확성 및 게이트 (§6)
4. S4 — 스크롤 A/B 통과 기준 1~6 (§11)
5. `DrawingDatabase.updateDrawing`의 `actor.update(drawing.id)`가 어떤 타입으로 해석되는지 (§8-7)
   — `BibleDrawing.id: String!` 와 `PersistentModel.id: PersistentIdentifier` 이름 충돌 → **S0-3**
6. 기존 N-Canvas 경로의 시편 119편 baseline (진입 시간·메모리) → **S0-4**
   — 단일 Canvas 전환 후에는 측정 불가하므로 **지금 확보해야 함**

### 실기기에서만 확인 (Phase 0A-D)

6. Pencil hover / live stroke 스냅 (§11 기준 7~8)
7. `.pencilOnly` 손가락 스크롤 (§11 기준 9~10)
8. 시편 119편 실제 layout 시간·peak memory (§6-1)

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

---

## 부록 — 삭제/격하 대상 요약

| 대상 | 처리 | Phase |
|---|---|---|
| `CanvasFeature` / `CanvasView` | 삭제 | 4 |
| `SharedUndoManager` | 삭제 (구현 자체가 깨져 있음) | 4 |
| `clippedPrecisely` / `normalizedForVerseRect` | 삭제 (판별 로직만 Codec으로 이관) | 4 |
| `StableCanvasView` 디버그 dump | 삭제 (~400줄) | 4 |
| `VerseRowFeature` | 삭제 (죽은 리듀서) | 4 |
| `CombinedCanvasFeature` / `CombinedCanvasView` | `ChapterCanvasFeature`로 재작성 | 3 |
| `Data.containsPKStroke` | "가시 획" 판정으로 수정 (§7-5) | 3 |
| `BiblePageDrawing` | 캐시/복구 전용으로 격하 → 장기 제거 | 3~ |
| `DrawingDatabase.updateDrawings(requests:)` | `DrawingRepository.apply(_:)` atomic batch로 대체 | 3 |
| `DrawingDatabase.updateDrawing(drawing:)` | 행 주소지정 정리 후 Repository로 흡수 (§8-7) | 3 |
| `BibleDrawing.mainDrawing()` | 결정적 선택 규칙으로 수정 (§8-7) | 3 |
| `VerseDrawingHistoryFeature` | **유지** — 단일 Canvas 복원 경로로 재배선 (§8-7) | 3 |
