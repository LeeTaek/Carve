
# PencilKit Rules (Carve)

## Goal
- PencilKit(UIKit)을 "UI 구현 세부"로 제한하고, 리듀서는 **상태/이벤트/저장 흐름**만 다룬다.
- 절 단위 필사 저장/복원/히스토리를 안정적으로 관리한다.
- iPad 회전/리사이즈/스크롤 환경에서도 **입력 좌표와 렌더링이 어긋나지 않게** 만든다.
- 원본은 설계 `docs/single-canvas-design.md` 다(§3 원칙 · §4 아키텍처 경계 · §5 DTO · §7 소유권 · §8 저장 · §9 복원 · §11 호스팅).
  이 문서는 그 요약이고, 둘이 다르면 설계를 따르고 이 문서를 고친다.

---

## Non-negotiables
**경계는 모듈이 아니라 리듀서다** (설계 §3 P9 · §4). `CarveFeature` 모듈은 PencilKit 을 의존하지만, 리듀서(State · Action · reduce 본문)는 PencilKit 을 모른다.

1) 리듀서에 PencilKit · UIKit 타입(`PKCanvasView` · `PKDrawing` · `PKTool` · `PKInkingTool.InkType` · `UIColor` · `UIImage` · `UIFont` · `UIApplication` · `UIView` 등)을 두지 않는다.
   캔버스 내용은 `Data` 와 Domain DTO(`ChapterLayout` · `VerseDrawingSnapshot` · `VerseDrawingMutation` 등)로 오가고, 편집 결과는 `CanvasEditSnapshot`(`Data`)으로 올라온다.
   - 기계 검사: `reducer_no_pencilkit_import`(리듀서 파일의 `import PencilKit`) · `reducer_no_ui_types`(리듀서 파일의 `PK*` · UIKit 타입 이름)
2) 캔버스에서 PencilKit 은 브리지(`ChapterCanvasView` · `ChapterCanvasController`)와 `Feature/CarveFeature/Sources/Drawing/`(`DrawingCodec` · `DrawingCodecClient` · `StrokeOwnershipResolver` · `LineBandReflow` 등)만 안다.
   리듀서에 주입되는 의존성 중 PencilKit 을 아는 것은 `DrawingCodecClient` 하나다. 리듀서가 아닌 읽기 전용 렌더 · Debug 하네스는 아래 「Allowed」.
3) UIKit 사용은 import 가 아니라 **타입 이름**으로 판정한다. SwiftUI 가 UIKit 을 다시 내보내므로 `import UIKit` 이 없어도 UIKit 타입을 쓸 수 있다.
   주석 속 이름은 판정하지 않는다. CoreGraphics 값 타입(`CGFloat` · `CGPoint` · `CGRect`)은 UIKit 타입이 아니다 — DTO(`ChapterLayout` · `columnOrigin`)가 쓴다.
4) UIKit delegate 이벤트는 브리지에서 Action 으로 바꿔 Store 로 보낸다(단방향).
5) 드로잉 저장/복원은 Dependency(`drawingRepository`) + Effect 로만 한다. View · 브리지는 직접 I/O 하지 않는다.
6) 좌표 **영역**은 `ChapterLayoutBuilder`(Domain)가 계산하고, 드로잉에 **transform 을 적용**하는 곳은 `DrawingCodec` 하나다(설계 §4 「좌표 관련 책임 분리」).
7) Domain 소스는 UIKit · SwiftUI · PencilKit 을 새로 import 하지 않는다. 쓰지 않는 import 는 지운다.
   - 기계 검사: `domain_no_ui_framework_import`

### 이행 중 예외 (늘리지 않는다)
지금 위 규칙을 어기는 곳이다. lint 는 규칙별 `excluded` 로 동결하고, 고치면 예외에서 뺀다. 펜 종류 · 색은 Domain 값 타입으로 바꾸는 것이 고치는 방향이다.

| 무엇 | 어디 |
|---|---|
| 펜 종류 `PKInkingTool.InkType` | `CarveDetailFeature.State.lastUsedPencil`(펜슬 더블탭 전환) · `PencilPalatteFeature`(State · Action) · Domain `PencilPalatte.pencilType` |
| 색 `UIColor` | `ColorPalatteFeature`(Action `setColor` · `defaultColors`) · `PencilPalatteFeature`(Action) · Domain `CodableColor` |
| N-Canvas 경로 — flag off 롤백용, 설계 §13 Phase 4 에서 삭제 | `CanvasFeature`(Action 에 `PKDrawing` · `PKCanvasView`) · `CanvasView` · `SharedUndoManager` |
| 설정 URL `UIApplication.openSettingsURLString` | `CarveDetailFeature+VerseImage`(사진 권한 알림의 「설정 열기」 effect) |
| 광고 뷰 `UIView` | UIComponents `SponsorAdSlotFeature.State.adView`(파일 `AdSlotFeature.swift` — `nativeAdClient.view(for:)` 가 돌려준 AdMob 뷰) |
| Domain 의 UI 프레임워크 타입 | `CodableColor`(UIKit `UIColor`) · `PencilPalatte`(PencilKit `InkType`) · `SentenceSetting`(SwiftUI 로 받은 `UIFont`) |

---

## Architecture boundary

### Allowed
- 브리지: `ChapterCanvasView`(`UIViewControllerRepresentable`)가 `ChapterCanvasController`(`PKCanvasView` 소유 · `PKCanvasViewDelegate`)를 띄우고 Store 와 단방향으로 소통한다.
- 리듀서는 `drawingCodec`(`DrawingCodecClient`)에 `Data` 와 DTO 를 넘겨 합성(`compose`) · 저장 명령(`mutations`)을 받는다.
- 리듀서가 아닌 읽기 전용 렌더와 Debug 하네스는 저장된 `Data` 를 `PKDrawing` 으로 풀어 그릴 수 있다 —
  절 이미지 `VerseImageCard` · 썸네일 `CarveInkThumbnail`(UIComponents) · 위젯 `AppGroupWidgetVerseClient`(App) · 팔레트 뷰 `PencilPalatteView` · `Feature/CarveFeature/Sources/Debug/`.
- `Data` 를 받아 값만 돌려주는 도우미 — CarveToolkit `Data.containsPKStroke`(Domain `DrawingContentRule` 이 쓴다).

### Forbidden
- 리듀서에서 `PKCanvasView` · `PKDrawing` 접근, UIKit API 호출 (이행 중 예외 제외)
- View · 브리지에서 SwiftData 저장 호출
- `DrawingCodec` 밖에서 드로잉 좌표 변환 — 예외: N-Canvas 가 v3 행을 표시할 때의 첫 밑줄 평행이동(설계 §10-3)

권장 구조(지금 이름)
- 리듀서: `ChapterCanvasFeature` (상태 · 액션 · 저장 조율). 리듀서 하나를 `ChapterCanvas*.swift` 여러 파일로 나눈다(`ChapterCanvasSaveFeature.swift` · `ChapterCanvasEraseFeature.swift` · `ChapterCanvasDraftFeature.swift` 등).
- UI 브리지: `ChapterCanvasView` + `ChapterCanvasController` (UIKit ↔ Action 변환)
- 코덱: `DrawingCodecClient`(`DrawingCodec`) — 합성 · 소유권 승계 · reflow · transform 적용
- Domain 저장소: `DrawingRepository`(`SwiftDataDrawingRepository`) — 원자적 batch 저장/조회

---

## Save strategy (when to persist)
단일 Canvas 의 저장은 설계 §8 이 원본이다.

- **편집 계약:** 브리지가 `canvasViewDidBeginUsingTool` → `editBegan`, `canvasViewDrawingDidChange` → trailing debounce 0.3 s → `editEnded(CanvasEditSnapshot)` 로 보낸다.
  다음 획이 시작되면 직전 획의 보고를 취소한다. `canvasViewDidEndUsingTool` 은 획이 `drawing` 에 반영되기 전에 불리므로 최종 저장 지점으로 쓰지 않는다(§7-5 · §8-1).
- **계산과 저장의 분리:** 순수 계산(소유권 승계 · dirty 절 · localize)은 `DrawingCodec.mutations` 가, 저장은 effect 의 `DrawingRepository.apply` 가 한다.
- **빈 결과도 저장 명령이다**(P7) — dirty 집합을 먼저 구하고 `clear` 를 명시 생성한다.
- **한 편집의 모든 절 저장은 단일 트랜잭션이다**(P8, §8-6). 저장은 동시에 하나 · 한 batch 는 한 장이고, 미저장 명령은 rowID 키로 last-wins 병합한다(§8-3).
- **실패:** 화면은 되돌리지 않고 큐를 보존해 다음 편집 · flush · 장 전환에서 재시도한다(P11, §8-4 · §8-5).
- "그리는 중"에는 레이아웃 · `columnOrigin` · 복원 재합성을 보류한다(`isEditing`).

---

## 절 단위 저장과 좌표계

### 저장 원칙 (필수)
- **획은 자르지 않는다**(P1). 한 획은 통째로 한 절에 귀속된다 — 새 획은 첫 control point 가 속한 절(`captureRect`)이 갖고, 여러 절을 지나도 시작한 절에 속한다(U1).
- **소유권은 편집 시점에 정하고 승계한다**(P2) — 기하로 매번 다시 판정하지 않는다(`StrokeOwnershipResolver`, §7-3).
- 저장 단위는 절별 Drawing(행)이다. 저장 변환은 평행이동뿐이다 — 절 로컬 원점(`storageOrigin` = `writingRect.minX`, 첫 밑줄 y)으로 옮겨 저장하고,
  저장 시점의 레이아웃 메타데이터(`DrawingLayoutMetadata`)를 함께 남긴다(P6).
- 좌표 형식은 `drawingVersion` 으로 명시 기록한다(P3) — nil · 1 = legacy, 2 = 절 로컬 + 좌상단(N-Canvas 형식), 3 = 절 로컬 + 첫 밑줄 원점 + metadata.

### Layout 변경 원칙 (필수)
- 레이아웃 변경은 **표시 변환일 뿐, 저장을 덮어쓰지 않는다**(P10). 사용자가 그 절을 실제로 편집할 때만 새 레이아웃 기준으로 저장한다.
- 복원은 line band reflow(`LineBandReflow`, §9-2)다 — 저장 당시 밑줄(band)마다 현재 같은 index 밑줄로 옮기고, 폭이 줄었을 때만 균등 축소한다(**확대하지 않는다**).
  잉크가 현재 줄 수보다 많은 band 에 걸치면 절 전체를 같은 비율로 줄여 현재 줄 묶음 안에 넣는다. 매핑할 줄이 없으면 첫 밑줄 기준으로 통째 보존하고 `layoutMismatch` 로 기록한다(§9-3-1).

> 목표: 레이아웃이 바뀌어도 "그려둔 위치 의미"(절 + 밑줄 index + 그 밑줄로부터의 상대 offset)가 유지되고, 과도한 확대/왜곡이 생기지 않게 한다.

### 좌표계 정의
- **content 좌표**: 캔버스(`PKCanvasView`) 좌표. `content = layout + columnOrigin`(`columnOrigin.y = 0`)
- **layout 좌표**: `ChapterLayout` 의 좌표 — 원점은 필사 컬럼 좌상단(`writingRect.minX == 0`). 장 전체 레이아웃의 유일한 진실 공급원이다
- **writingRect**: 절의 필사 영역. 텍스트 줄 수(실측 높이)만큼이며, 저장된 필사가 더 많은 줄에 걸쳐 있어도 늘지 않는다
- **captureRect**: 획 소유권을 판정하는 영역. 인접 절과의 midpoint 로 나눠 절 사이 gap 까지 덮는다
- **underlineAnchors**: 밑줄 y(`writingRect` 기준 상대값). 텍스트 줄 수만큼만 만든다
- **절 로컬(저장)**: `storageOrigin` 원점
- `columnOrigin` 은 호스팅이 실측해 올리고, 리듀서는 보관 · 전달만 한다. 적용은 `DrawingCodec` 한 곳이다(U5).

### N-Canvas (flag off 롤백 경로)
- 절마다 `PKCanvasView` 를 두고 바깥 SwiftUI `ScrollView` 로 스크롤한다. `SingleCanvasFlag` 를 끄면 이 경로로 돌아간다(설계 §10-3).
- 옛 clip 도우미(`PKDrawing+Extension.swift` 의 `clippedPrecisely` · `normalizedForVerseRect`)는 제품 코드에서 부르지 않는다 — Phase 4 삭제 대상이고 새 코드에서 쓰지 않는다.

---

## Layout/scroll/rotation (iPad)
- **스크롤 컨테이너는 하나다**(P5 · U4). `ChapterPKCanvasView`(`PKCanvasView`)가 화면의 유일한 `UIScrollView` 이고, 텍스트 컬럼(`UIHostingController`)은 그 scroll content 안 · 잉크 아래에 둔다. 스크롤 동기화 코드는 없다.
- **금지:** `PKCanvasView` 와 별개인 SwiftUI 텍스트에 `contentOffset` 만 전달하는 방식 — 프레임별 동기화 · bounce · safe-area · zoom 에서 drift 가 재발한다(§11).
- 텍스트 컬럼은 세로로 늘어나면 안 된다 — 컬럼 상단이 레이아웃 원점이고 컬럼 높이가 좌표 스케일이다(§11 R16).
- `contentInsetAdjustmentBehavior = .never` 를 유지하고 `contentInset` 을 직접 넣는다. 콘텐츠 좌표는 인셋과 무관하다(U6).

---

## Performance & safety
- 합성은 레이아웃이 전량 준비되고 장의 필사를 다 읽은 뒤에만 한다 — 그 전에는 합성 · 입력 · 저장을 막는다(P4, §6-2 · §6-4).
- 저장 명령은 dirty 절만 만든다(§8-2). 변경 판정은 `drawing.dataRepresentation()` 바이트 비교가 아니라 `StrokeContentSignature`(§7-2)로 한다.
- `dataRepresentation()` · 디코드는 비용이 있으므로 필요한 때만 한다 — 브리지는 `renderedRevision` 이 바뀔 때만 디코드해 `drawing` 에 넣는다.

---

## Debugging hooks
- 레이아웃 오버레이 · HUD: Debug 실행 인자 `-ChapterLayoutOverlay`(단일 Canvas 는 `-SingleCanvas -ChapterLayoutOverlay`). 판독법과 표시 진단 인자는 `docs/device-simulator-verification.md`.
- 오버레이 · HUD · 진단 인자는 실행 인자로 켜고 끄며 `#if DEBUG` 안에서만 읽는다 — 출시 구성에 들어가지 않는다.

---

## Testing recommendations
PencilKit 자체는 UI 테스트가 어려우므로, 핵심은 **순수 계산 로직**을 분리해 단위 테스트한다.
- 좌표 영역 · captureRect: `ChapterLayoutBuilderTesting`(Domain)
- 소유권 판정 · 승계: `StrokeOwnershipResolverTesting`
- reflow: `LineBandReflowTesting`
- 코덱 합성 · 저장 명령 왕복: `DrawingCodecTesting`
- 리듀서 상태 전이: `DrawingCodecClient` 의 클로저를 스텁으로 바꿔 코덱 없이 고정한다(`ChapterCanvasFeatureTesting`)

---

## Definition of done
- [ ] 리듀서(State · Action · reduce 본문)에 PencilKit · UIKit 타입이 새로 없다 — `reducer_no_pencilkit_import` · `reducer_no_ui_types` error 0
- [ ] Domain 에 UIKit · SwiftUI · PencilKit import 가 새로 없다 — `domain_no_ui_framework_import` error 0
- [ ] 캔버스 내용은 `Data` 와 Domain DTO 로만 오가고, PencilKit 은 브리지 · `Drawing/` 안에 있다
- [ ] 이행 중 예외가 늘지 않았다(고쳤으면 표와 lint `excluded` 에서 뺐다)
- [ ] 저장/복원은 Dependency + Effect 로 분리됨
- [ ] 좌표계 기준이 문서화되어 있고, 변환은 `DrawingCodec` 한 곳에서 수행됨
- [ ] 회전/리사이즈/스크롤 환경에서 입력 오프셋이 재현 가능하고, debug 도구로 확인 가능
- [ ] 순수 계산 로직에 대한 단위 테스트 포인트가 정의됨
