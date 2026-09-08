# D9 H — 회전 후 이전 필기가 표시되는 결함

작성: 2026-09-08 · 조사 시작 HEAD: `0c01b32c` (`feat/canvas`)

## 1. 현재 수정 상태

**정식 수정은 아직 적용하지 않았다.** 원인 분리용 계측과 Debug 비교 모드가 구현되어 있고, 비교 모드에서는 실기기 가로 → 세로 → 가로 회전이 정상임을 확인했다. 실행 인자 없는 기본 경로와 Release에는 해결 처리가 들어가지 않았다. 다음 세션은 §5의 구현안과 §6의 검증 기준에 따라 정식 수정을 수행한다.

| 구분 | 상태 |
|---|---|
| 기본 경로의 결함 | 실기기에서 재현, 미해결 |
| 원인 분리 | 완료: 데이터 전달 이후, 기존 획 재사용에 따른 표시 갱신 경로로 좁힘 |
| 수동 정상화 | 빈 drawing 경유 재대입 / 같은 속성의 새 획 객체 생성 모두 성공 |
| 자동 비교 모드 | `-CanvasFreshStrokesOnApply`, Debug에서 회전 왕복 정상 |
| 정식 수정·Release 검증 | 미수행 |
| 긴 장 성능·다양한 잉크·실제 편집 후 저장 | 정식 수정의 후속 검증으로 남음 |

관련 문서: [전환 설계](./single-canvas-design.md) §5·§9·§14·§20-15, [D9 런북](./phase-0a-d-device-test.md) §6-9·§8-7, [실기기 조작 절차](./device-debugging-cli.md).

## 2. 증상과 기존 진단의 정정

시편 120편에서 가로 → 세로 → 가로로 회전하면 본문과 밑줄은 새 레이아웃으로 갱신되지만 필기는 이전 방향의 합성물처럼 표시된다. `Δ max 0.00`, `compose SYNC`, `guard OPEN`이어도 발생한다.

사용자가 제공한 `IMG_0884.PNG` → `IMG_0885.PNG` → `IMG_0886.PNG`에서 **두 번째 이미지부터 잘못 표시된다.** 첫 두 원본 이미지의 ‘여호와여’ 검사 영역에서 검은 픽셀의 x 범위는 모두 1148~1375px였다. 이 값은 검사 영역의 픽셀 범위이며 전체 drawing bounds가 아니다. HUD의 `columnX`는 556.34pt → 366.70pt로 바뀌는데 해당 필기는 같은 화면 위치에 남았다. 기존 인계 기록의 “세로는 정상, 가로 복귀만 실패” 판정은 정정한다.

또한 다음 계측을 구분해야 한다.

- `legInk`: 코덱이 절별 변환 직후 계산한 **legacy 절만의** bounds. 모든 획을 병합·직렬화한 뒤의 최종 데이터 검증값이 아니다.
- `canvas.drawing.bounds`: **전체 획**의 bounds. `legInk`와 직접 등치 비교하지 않는다.
- `appliedRevision`: 컨트롤러의 대입 세대. 실제 화면 렌더 완료를 뜻하지 않는다.
- `canvasViewDidFinishRendering`: 새 drawing 대입뿐 아니라 스크롤·확대에서도 올 수 있고 revision을 전달하지 않는다. 콜백 시점의 applied를 “완료된 세대”로 기록하면 안 된다.
- `Δ max`: 행 레이아웃 일치 여부다. 0이라는 이유로 남은 결함을 저장 경로 문제라고 단정할 수 없다.

## 3. 실기기 실험 결과

### 환경과 데이터 비교

2026-09-08, iPad mini (A17 Pro, iPad16,2), iPadOS 27.0 beta `24A5408d`, USB `wired`, Xcode 26.3 `17C529`. 시편 120편의 기존 44개 획을 사용했으며 새 필기는 입력하지 않았다. 화면 판정은 각 실험 직후 사용자가 실기기를 보고 답한 결과다. CLI 로그와 화면 판정을 별개의 증거로 취급한다.

회전 중 동일 컨트롤러가 유지되었다. 한 수집 세션의 ID는 `21E093FA`였고 다음 값이 관찰됐다. bounds는 `(x, y, width, height)` 형식의 전체 content 좌표다.

| 상태 | Store / 전달 / applied | 최종 데이터 디코딩 및 canvas bounds | 획별 비교 |
|---|---|---|---|
| 가로 진입 | 2 / 2 / 2 | `(573, 71, 389, 410)` | 일치 |
| 세로 | 3 / 3 / 3 | `(378, 79, 255, 564)` | 일치 |
| 가로 복귀 | 4 / 4 / 4 | `(573, 71, 389, 410)` | 일치 |

획별 비교는 순서가 같은 전체 획의 `renderBounds`, `transform`, `randomSeed`, `path.count`를 비교했다. 모든 픽셀·모든 필기 속성의 완전한 동등성 검사라고 해석하지 않는다. `contentOffset.x=0`, `zoomScale=1`, `canvas.transform=identity`였고, 조사한 내부 UIView의 공개 frame/bounds/transform에서도 지속적인 가로 이동은 관찰되지 않았다. 렌더 완료 콜백도 도착했다.

### 표시만 바꾸는 비교 실험

| 순서 | 작업 | 화면 결과 |
|---|---|---|
| 1 | 기본 경로로 가로 → 세로 | 오른쪽으로 밀림 |
| 2 | `setNeedsDisplay` + `setNeedsLayout` + `layoutIfNeeded` | 변화 없음 |
| 3 | 현재의 같은 `canvas.drawing` 재대입 | 변화 없음 |
| 4 | 빈 `PKDrawing()` 대입 직후 같은 drawing 복원 | 정상화 |
| 5 | 다시 가로 회전 | 왼쪽 본문으로 밀림 |
| 6 | 같은 ink/path/transform/mask/randomSeed로 새 `PKStroke` 생성 | 정상화 |
| 7 | 앱 재실행 후 매 apply에 새 획 생성, 세로 회전 | 추가 복구 명령 없이 정상 |
| 8 | 위 모드에서 가로 복귀 | 정상 유지 |

조사 종료 시 앱은 `-SingleCanvas -ChapterLayoutOverlay -CanvasFreshStrokesOnApply`로 실행했다. 로그 수집과 원격 실험 모드는 종료했다. 이 실행 상태가 영구 설정이나 Release 수정이라는 뜻은 아니다.

### 확인 범위와 추론

**확인한 사실:** 이번 실기기 재현에서는 최종 데이터가 컨트롤러와 drawing까지 도착했고, 같은 좌표를 유지한 표시 교체 방식만 바꿔도 정상화됐다. 컨트롤러 재생성과 합성 좌표 전달 누락으로 이번 증상을 설명할 수 없다.

**가장 잘 맞는 설명:** 기존 획의 정체성을 재사용하는 재합성 경로에서 PencilKit의 렌더 캐시 또는 표시 갱신이 이전 결과를 유지한다. 새 획 객체 생성과 빈 drawing 경유 교체가 해당 재사용을 끊는 것으로 해석된다.

Apple 내부 캐시 키, 내부 UUID, 실패한 프레임워크 함수는 확인하지 않았다. Swift 값 타입 `PKStroke`의 “객체 재사용”은 기존 획에서 파생된 표현의 재사용을 가리키는 설명이며, 동일 Swift 메모리 주소를 측정했다는 뜻이 아니다. 단독 PKCanvasView 최소 재현이나 다른 iPadOS 버전 비교도 수행하지 않았으므로 iPadOS 27 전체의 일반 결함으로 단정하지 않는다.

## 4. 현재 구현된 진단 코드

| 파일 | 역할 |
|---|---|
| [ChapterCanvasDisplayProbe.swift](../Feature/CarveFeature/Sources/Debug/ChapterCanvasDisplayProbe.swift) | 0.5초 간격의 읽기 전용 상태·drawing 비교. 별도 인자가 있을 때만 명시적 실험 명령 수신 |
| [ChapterCanvasView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/ChapterCanvas/ChapterCanvasView.swift) | 진단 실행 인자 확인 및 프로브 연결 |
| [ChapterCanvasController.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/ChapterCanvas/ChapterCanvasController.swift) | apply/렌더 계측, 수동 실험, Debug 자동 비교 모드 |
| [ChapterCanvasControllerTesting.swift](../Feature/CarveFeature/Tests/ChapterCanvasControllerTesting.swift) | 실험 시 편집 보고 억제 및 획 좌표·소유권 식별자 보존 테스트 |

`-CanvasFreshStrokesOnApply`는 `applyDrawing` 안에서만 작동한다. 디코딩한 drawing의 각 획을 `PKStroke(ink:path:transform:mask:randomSeed:)`로 다시 구성한다. `path`를 그대로 넘겨 생성 시각과 control point를 유지한다. 이 처리는 `#if DEBUG`와 실행 인자 뒤에 있으므로 **그대로 두면 정식 앱에는 해결책이 적용되지 않는다.**

## 5. 다음 세션의 정식 구현안 — 아직 미구현

### 후보 비교와 권장 순서

| 후보 | 확보한 근거 | 채택 전 확인할 점 |
|---|---|---|
| **새 획 생성 후 표시** | 수동 정상화와 자동 회전 왕복 모두 성공 | 모든 필요한 필기 속성·마스크 보존, 긴 장의 할당·렌더 비용 |
| 빈 drawing을 거쳐 같은 drawing 대입 | 수동 정상화 성공 | 연속 회전, 비동기 delegate, 깜빡임, undo 및 추가 렌더 비용. 자동 회전 적용은 아직 미검증 |
| setNeedsDisplay / 같은 drawing 재대입 | 효과 없음 | 단독 수정안으로 채택하지 않음 |
| 컨트롤러 또는 PKCanvasView 재생성 | 이번 조사에서 시험하지 않음 | 스크롤·편집·undo 수명 영향을 늘리므로 우선안 아님 |

**새 획 생성 방식을 우선 검증한다.** 공개 속성만으로 충실히 재구성할 수 없는 잉크/SDK 속성이 발견되면 빈 drawing 경유 방식으로 비교한다. 새 속성 손실 가능성을 무시하고 Debug 코드를 그대로 Release로 옮기지 않는다.

### 구현 순서

1. 작업 시작 시 현재 diff를 확인한다. 이 세션의 진단 코드 4개 파일은 미커밋 변경일 수 있으므로 지우거나 중복 구현하지 않는다. 현재 정식 동작과 Debug 비교 모드의 차이를 먼저 확인한다.
2. `ChapterCanvasController.applyDrawing`의 **디코딩 후, canvas.drawing 대입 직전**에 표시용 획 재구성 helper를 둔다. Feature/코덱/DB의 좌표 계산이나 저장 데이터 마이그레이션으로 옮기지 않는다.
3. `ink`, `path`, `transform`, `mask`, `randomSeed`와 사용 SDK의 추가 공개 필기 속성을 감사한다. `StrokeIdentityKey`가 쓰는 생성 시각·seed·point 수를 포함해 기존 owner 연결이 유지되어야 한다. `PKStroke` 내부 식별자를 앱의 소유권 키로 채택하지 않는다.
4. 실제 `renderedRevision` 교체 시에만 실행한다. 일반 `updateUIViewController`, 스크롤, 도구 설정 변경, 사용자 획 delegate마다 전체 획을 재생성하지 않는다.
5. 기존 순서를 보존한다: 이전 세대 미보고 편집 flush → 데이터 디코드/표시 준비 → `isApplyingDrawing` 보호 안에서 교체 → 기존 undo 초기화·다음 턴 보고. 실험 테스트가 잡은 것처럼 프로그램 대입을 사용자 편집으로 보고하면 저장 오류가 된다.
6. 검증이 끝난 방식을 정식 경로로 승격하고 실험 분기를 정리한다. 특정 OS 버전만 적용할지는 추가 비교 결과로 결정한다. 근거 없이 정확한 OS 버전 조건이나 런타임 캐시 결함 탐지 로직을 만들지 않는다.
7. 진단 프로브의 유지 범위를 정한다. 원격 실험 명령은 Debug의 명시적 opt-in 뒤에만 남기거나 조사 종료 시 제거한다. Release에 빈 진단 delegate나 폴링이 생기지 않게 한다.
8. §6 통과 후 이 문서의 상태와 설계·런북을 “정식 수정 완료”로 갱신한다. 그전에는 D9 H를 종결하지 않는다.

### 변경하지 않을 계약

- TCA + MicroArchitecture 경계, `ChapterCanvasFeature.State.isReady` 합성 게이트.
- `ChapterCanvasView.hostedColumn`의 `.fixedSize(horizontal: false, vertical: true)`.
- N-Canvas 저장, legacy 승격 정책, DB 마이그레이션, 의존성·서명·빌드 설정.
- 회전 이후 전체 경로가 검증되기 전 단일 Canvas 기본 활성화.

## 6. 검증 계획과 완료 조건

### 이번 세션에서 완료한 검증

- Xcode 26.3 실기기 Debug 빌드, Tuist generate, 변경 Swift 파일 SwiftLint, `git diff --check` 통과.
- iPad mini(A17 Pro), iOS 26.2에서 전체 **296개** 통과: Swift Testing 294개 + XCTest 2개. 세부: CarveFeature 167, Domain 107(XCTest 2 포함), CarveToolkit 6, ChartFeature 9, SettingsFeature 4, UIComponents 3.
- 인계 기준 295개에서 진단 안전성 테스트 1개 추가. 테스트를 extension으로 옮긴 뒤 컨트롤러 스위트 13개 재검증 통과.
- 변이: 진단 명령의 `isApplyingDrawing` 억제를 제거하자 새 테스트가 `editEnded` 발생으로 실패(3 issues). 변이 복원 완료.
- 함수 단위 `only-testing`이 0개를 선택한 실행은 검증으로 세지 않았다. 스위트 전체로 재실행했다.

이 테스트는 **진단 명령의 데이터·편집 계약**을 검증한다. PencilKit의 실제 화면 버그를 자동 검출하는 렌더 회귀 테스트는 아직 없다. 기존 배선 테스트도 drawing 속성까지 검사하므로 이 버그를 배제하지 못한다.

### 정식 수정에서 추가할 검증

- 변환된 여러 획, 다양한 잉크·마스크·지우개 조각의 경계·control point·seed·생성 시각·소유권 보존. 빈 drawing과 디코드 실패의 기존 처리 유지.
- 같은 revision의 도구/스크롤 갱신은 drawing과 undo를 교체하지 않는지 확인.
- 회전 직전 미보고 획이 이전 세대로 정확히 flush되고, 프로그램 표시 교체는 저장 mutation을 만들지 않는지 확인. 새 테스트에는 적절한 변이를 넣어 실제 실패를 확인.
- 실기기에서 기본 실행 조건으로 가로 → 세로 → 가로를 최소 3왕복. `-CanvasFreshStrokesOnApply` 없이 정상이어야 정식 수정의 통과다. 스크롤 중 회전, 글꼴/행간 변경, 좌우 필사 위치도 확인.
- **증거 표본인 시편 120편 legacy 2·4절에는 새 획을 입력하지 않는다.** 별도 테스트 장/복제 표본에서 새 필기·부분 지우개·undo/redo·장 이동·재실행 복원·N-Canvas 왕복을 검증한다.
- 시편 119편처럼 긴 장에서 진입/재합성 시간과 physical footprint를 수정 전후 동일 조건으로 비교. 기준은 설계 §18-3 및 런북 D9-8을 사용하고 미측정 수치를 합격으로 기록하지 않는다.
- 좁은 관련 테스트 → 전체 iPad 시뮬레이터 테스트(현재 296 이상) → Release 빌드까지 확인. 진단 테스트 삭제로 수가 줄면 제거 이유와 대체 정식 회귀 테스트를 명시한다.

## 7. 로그와 인계

원본 로그는 조사 Mac의 `/tmp/carve-d9-display-evidence.log`, `/tmp/carve-d9-full-tests.log`, `/tmp/carve-d9-mutation.log`, `/tmp/carve-d9-final-controller-tests.log`에 있다. **임시 파일이므로 다른 세션·머신에서 존재한다고 가정하지 않는다.** 핵심 결과는 위 표에 남겼다. 원본 로그를 공유할 때는 인증값·개인정보가 섞이지 않았는지 확인하고, 전체 콘솔 대신 필요한 계측만 추린다.

다음 세션에 전달할 요청:

> 이 문서의 §5 구현안에 따라 D9 H 정식 수정을 구현한다. 현재 해결 처리는 Debug 실행 인자 뒤에만 있다. 기존 미커밋 진단 변경을 보존하며 활용하고, 표시 교체 경계에서 수정한다. §6의 데이터·저장·실제 화면·성능 검증을 수행한다. 실기기 조작은 device-debugging-cli.md를 따른다. 검증되지 않은 항목을 완료로 기록하거나 D9 전체를 통과로 바꾸지 않는다.
