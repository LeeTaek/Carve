
# PencilKit Rules (Carve)

## Goal
- PencilKit(UIKit)을 “UI 구현 세부”로 제한하고, Feature는 **상태/이벤트/저장 흐름**만 다룬다.
- verse 단위 드로잉 저장/복원/히스토리를 안정적으로 관리한다.
- iPad 회전/리사이즈/스크롤 환경에서도 **입력 좌표와 렌더링이 어긋나지 않게** 만든다.

---

## Non-negotiables
1) Feature는 `PKCanvasView`, `PKDrawing`, `PKTool` 등 PencilKit/UIKit 타입에 직접 의존하지 않는다.  
2) UIKit delegate 이벤트는 Adapter(Coordinator)에서 Action으로 변환해 Store로 전달한다.  
3) 드로잉 저장/복원은 Dependency(Repository/Client) + Effect로만 수행한다. View/Coordinator는 직접 I/O 금지.  
4) 좌표계 변환(스크롤/스케일/회전)은 한 곳(예: Layout/Geometry Engine)에서만 수행한다.

---

## Architecture boundary

### Allowed
- `UIViewRepresentable` + `Coordinator`가 `PKCanvasView`를 소유하고 Store와 단방향으로 소통
- Feature는 “그림 변경 이벤트”와 “저장/복원 요청”만 처리

### Forbidden
- Feature에서 `PKCanvasView` 접근
- Reducer에서 UIKit API 호출
- View/Coordinator에서 SwiftData 저장 호출

권장 구조(개념)
- Feature: `CombinedCanvasFeature` (상태/액션/리듀서)
- UI Bridge: `CombinedCanvasView` + `Coordinator` (UIKit ↔ Action 변환)
- Domain/Client: `DrawingDatabase` 또는 `DrawingRepository` (저장/조회)

---

## Save strategy (when to persist)
드로잉 저장 트리거는 반드시 정책으로 고정한다.

권장 옵션
- **End-of-stroke 저장**: 입력 종료 시점(또는 안정 구간)에서 저장
- **Debounce 저장**: `canvasViewDrawingDidChange`를 0.2~0.5s debounce 후 저장

원칙
- “그리는 중”에는 무거운 작업(rebuild/merge/save)을 피한다.
- 저장은 다음 두 단계로 분리한다.
  1) 순수 계산: affected verse 판단, clip rect 계산, 로컬 좌표 변환
  2) effect: SwiftData/파일 저장

---

## Verse-based clipping & coordinate system

### 저장 원칙 (필수)
- `drawingData`는 **각 verse의 underline 영역에 맞게 clipping**한 뒤, **verse별로 분리 저장**한다.
- 페이지 단위 full drawing은 “초기 표시/캐시” 목적에 한해 저장할 수 있으나,
  레이아웃 변경 시 기준은 항상 **verse 단위 drawing**이다.

### Layout 변경 원칙 (필수)
- 앱의 window(회전/리사이즈/창 모드) 변경으로 underline rect가 변경되거나 개행이 바뀌면,
  저장된 verse drawing은 다음을 수행해야 한다.
  - **re-scale**: 현재 underline/content 폭에 맞게 축소(필요 시)한다.
  - **re-position**: 시작 위치(앵커/offset)를 새 underline 기준에 맞게 이동한다.

> 목표: 레이아웃이 바뀌어도 “그려둔 위치 의미”가 유지되고, 과도한 확대/왜곡이 발생하지 않도록 한다.

### Coordinate system definitions (문서화 필수)
- **Canvas local**: PKCanvasView 좌표계 기준
- **Verse rect**: 특정 verse(underline/content)의 캔버스 로컬 좌표 rect
- **Underline rect**: 실제 밑줄/텍스트 라인을 나타내는 rect(또는 라인별 rect 집합)
- **Changed rect**: 새 stroke들의 `renderBounds` union

### Affected verse 판정
- changedRect가 어떤 verse에 속하는지 판단할 때, 단순 intersects만으로 누락될 수 있으므로
  verse 사이 gap까지 커버하는 **capture rect**(midpoint split 등) 전략을 사용한다.

### Clipping rule
- 저장 시에는 underline/content 기준으로 **clip rect**를 만든다.
- clip rect에는 최소한의 padding(예: `clipTopPadding`)과 수평 inset(예: underline inset)을 적용해
  밑줄 주변 여백까지 자연스럽게 포함되도록 한다.

### Localize rule (저장)
- verse 단위 저장은 “verse 로컬 좌표(0,0 기준)”로 변환해 저장한다.
- 저장 시 필요한 메타데이터(권장)
  - `baseWidth` / `baseHeight`: 저장 당시 underline/content 기준 크기
  - `baseFirstUnderlineOffset`: 첫 underline 기준 앵커(선택)

### Restore rule (복원)
- 복원 시에는 현재 레이아웃 rect에 맞춰 scale/translate 한다.
- re-scale 정책
  - 기본은 **축소만 허용**한다(확대는 지양)
  - 기준은 underline/content 폭(수평)과 앵커(수직)이다.

### Baseline/anchor
- underline 첫 라인 기준(y offset)을 anchor로 저장/복원에 활용할 수 있다.
- anchor 사용 시 확대는 최소화하고, 필요한 경우 축소만 허용해 “그림이 커지는 문제”를 방지한다.

---

## Layout/scroll/rotation (iPad)
- iPad는 회전/윈도우 리사이즈가 잦으므로, 다음을 원칙으로 한다.
  - canvas 내부 스크롤은 비활성화하고, 부모(SwiftUI ScrollView)의 스크롤 상태를 동기화할 수 있다.
  - `contentSize/contentOffset/contentInset/zoomScale` 등 UIScrollView 상태는 update cycle에서 정규화한다.
  - 회전/리사이즈 감지 시 `layoutIfNeeded()` 등으로 라이브 스트로크 오프셋을 완화한다.

---

## Performance & safety
- `drawing.dataRepresentation()` 비교는 비용이 있으므로
  - 필요한 경우에만 수행하거나
  - 뷰 업데이트 빈도를 낮추는 정책(debounce)과 함께 사용한다.
- clip/merge/rebuild는 stroke 수가 많을수록 비싸므로
  - 전체 rebuild는 “필요 조건(모든 rect 준비 등)”이 충족될 때만 실행
  - 특정 verse만 부분 교체(replace)할 수 있으면 부분 교체를 우선한다.

---

## Debugging hooks
- Debug overlay(선택):
  - verse rect / underline rect / changedRect를 표시
  - affected verse 목록, clip stroke 수를 로그로 출력
- Debug 모드는 쉽게 on/off 가능해야 한다.

---

## Testing recommendations
PencilKit 자체는 UI 테스트가 어려우므로, 핵심은 **순수 계산 로직**을 분리해 단위 테스트한다.
- changedRect → affected verse 매핑
- capture rect 생성 로직
- clip rect(패딩/인셋) 계산
- localize/restore transform 계산

---

## Definition of done
- [ ] Feature에서 PencilKit/UIKit 타입 직접 참조 없음
- [ ] 저장/복원은 Dependency + Effect로 분리됨
- [ ] 좌표계 기준이 문서화되어 있고, 변환은 단일 소스에서 수행됨
- [ ] 회전/리사이즈/스크롤 환경에서 입력 오프셋이 재현 가능하고, debug 도구로 확인 가능
- [ ] 순수 계산 로직에 대한 단위 테스트 포인트가 정의됨
