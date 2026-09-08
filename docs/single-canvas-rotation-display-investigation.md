# D9 H — 회전 후 이전 필기가 표시되는 결함

작성: 2026-09-08 · 조사 시작 HEAD: `0c01b32c` (`feat/canvas`)

## 1. 현재 수정 상태

**정식 수정을 적용했고 실기기 A/B 로 인과를 확인했다** (`ef053111`). `applyDrawing` 의 디코딩 후·대입 직전에서 같은 공개 속성으로 획을 새로 만들어 넣는 것이 정식 경로다. **다만 §6 의 나머지 검증(편집·저장 왕복, 긴 장 성능, 스크롤 중 회전 등)이 남아 있어 D9 H 를 아직 종결하지 않는다.**

| 구분 | 상태 |
|---|---|
| 기본 경로의 결함 | ✅ **해소** — 재구성이 정식 경로 (Release 포함) |
| 원인 분리 | 완료: 데이터 전달 이후, 기존 획 재사용에 따른 표시 갱신 경로 |
| 수동 정상화 | 빈 drawing 경유 재대입 / 같은 속성의 새 획 객체 생성 모두 성공 |
| **실기기 A/B (2026-09-08)** | ✅ **인자 없이 가로↔세로 3왕복 전부 정상** · ✅ **`-CanvasReuseStrokesOnApply` 로 결함 재현(양성 대조)** |
| Release 유출 | ✅ 바이너리 심볼로 확인 — 진단·플래그 0건 |
| 편집·저장 왕복 · 긴 장 성능 · 스크롤 중 회전 · 글꼴 변경 | ⚠️ **미수행** (§6) |

관련 문서: [전환 설계](./single-canvas-design.md) §5·§9·§14·§20-15·§20-16, [D9 런북](./phase-0a-d-device-test.md) §6-9·§8-7, [실기기 조작 절차](./device-debugging-cli.md).

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

조사 종료 시 앱은 `-SingleCanvas -ChapterLayoutOverlay -CanvasFreshStrokesOnApply`로 실행했다 (당시의 opt-in 인자 — **지금은 없다.** §4). 로그 수집과 원격 실험 모드는 종료했다.

### 정식 수정 후 A/B (2026-09-08, `ef053111`)

같은 기기·같은 빌드에서 실행 인자만 바꿔 대조했다. **계측은 두 실행이 구분되지 않는다** —
`store/delivered/applied` 가 매 세대 일치하고 `canvas` bounds 도 기대값과 같으며
`storeDiff=0 deliveredDiff=0`, `offset=(0,-112)`, `zoom=1.0`, `transform=identity`,
컨트롤러 동일(`C9C20DC9`)이다. **화면 판정만 갈린다.**

| 실행 | 조작 | `applied` | canvas bounds | 화면 |
|---|---|---:|---|---|
| 기본 (재구성) | 가로 진입 | 2 | (573, 71, 389, 410) | 정상 |
| 〃 | 1왕복 세로 | 3 | (378, 79, 255, 564) | **정상** |
| 〃 | 1왕복 가로 | 4 | (573, 71, 389, 410) | **정상** |
| 〃 | 2왕복 세로·가로 | 5·6 | 동일 | **정상** |
| 〃 | 3왕복 세로·가로 | 7·8 | 동일 | **정상** |
| **대조** `-CanvasReuseStrokesOnApply` | 가로 진입 | 2 | (573, 71, 389, 410) | 정상 |
| 〃 | 세로 | 3 | (378, 79, 255, 564) | ❌ **밀림 — 결함 재현** |

**양성 대조가 성립했다.** 계측이 동일한데 화면만 갈리므로, 재구성이 이 증상의 처방이라는
귀속이 확인된다. 회전은 `devicectl device orientation set` 으로, 화면 판정은 사용자 확인으로
얻었다 (절차: [실기기 CLI](./device-debugging-cli.md)).

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

표시용 획 재구성은 `applyDrawing` 안에서만 작동한다. 디코딩한 drawing의 각 획을 `PKStroke(ink:path:transform:mask:randomSeed:)`로 다시 구성하고, `path`를 그대로 넘겨 생성 시각과 control point를 유지한다. **이것이 지금의 정식 경로다(Release 포함).** 조사 당시의 `-CanvasFreshStrokesOnApply`(수정을 켜는 opt-in)는 사라졌고, 남은 `-CanvasReuseStrokesOnApply`는 **수정을 끄고 결함을 재현하는** Debug 전용 opt-out이다 — 양성 대조와 성능 비교에만 쓴다.

## 5. 정식 구현안 — ✅ 적용 완료 (`ef053111`)

### 후보 비교와 채택 근거

| 후보 | 확보한 근거 | 판정 |
|---|---|---|
| **새 획 생성 후 표시** | 수동 정상화 · 자동 회전 왕복 · 실기기 3왕복 + 양성 대조 모두 통과 | ✅ **채택** |
| 빈 drawing을 거쳐 같은 drawing 대입 | 수동 정상화 성공 | 미채택 — 연속 회전·비동기 delegate·깜빡임·undo·추가 렌더 비용이 미검증 |
| setNeedsDisplay / 같은 drawing 재대입 | 효과 없음 | 미채택 |
| 컨트롤러 또는 PKCanvasView 재생성 | 시험하지 않음 | 미채택 — 스크롤·편집·undo 수명 영향이 크다 |

### 구현 결과 — 지켜진 제약

1. `ChapterCanvasController.applyDrawing`의 **디코딩 후, `canvas.drawing` 대입 직전**에 표시용 획 재구성 helper를 뒀다. Feature/코덱/DB의 좌표 계산이나 저장 데이터 마이그레이션은 건드리지 않았다.
2. **속성 감사 완료 (iOS 26 SDK).** 지정 가능 속성은 `ink`·`path`·`transform`·`mask`·`randomSeed` 다섯뿐이고 전부 그대로 넘긴다. `renderBounds`·`maskedPathRanges`·`requiredContentVersion`은 읽기 전용 파생값이라 지정 수단이 없다. **손실되는 지정 가능 속성은 없다.** `path`를 통째로 넘기므로 `StrokeIdentityKey`가 쓰는 `randomSeed`+`creationDate`+`path.count`가 보존돼 소유권 승계가 유지된다.
3. 실제 `renderedRevision` 교체 시에만 실행한다. 일반 `updateUIViewController`·스크롤·도구 설정 변경·사용자 획 delegate에서는 재생성하지 않는다.
4. 기존 순서를 보존했다: 이전 세대 미보고 편집 flush → 디코드/표시 준비 → `isApplyingDrawing` 보호 안에서 교체 → undo 초기화·다음 턴 보고.
5. OS 버전 조건이나 런타임 캐시 결함 탐지 로직은 **만들지 않았다** — 근거가 없다.

> ⚠️ **알려진 부작용 — 지우개 조각 절이 1회 재저장된다.** `mask != nil` 인 획을 재구성하면 파생값 `maskedPathRanges`가 재계산되며 미세하게 달라진다(실측 차이 약 6.7e-4). `StrokeContentSignature`는 반올림을 금지하므로(설계 §7-2) 그 절이 한 번 dirty로 잡혀 `.replace`가 한 번 나간다. **저장 내용(획 수·좌표·`StrokeIdentityKey`·`ownership.map`)은 원본과 동일**하고, 재합성하면 mutation이 없는 **고정점**이라 회전마다 되풀이되지 않는다. 다만 `updateDate`가 바뀌므로 히스토리 순서·주간 통계에 영향이 있을 수 있다. (설계 §20-16)

### 남은 정리 항목

- 진단 프로브(`ChapterCanvasDisplayProbe`)와 `-CanvasDisplayExperiments` 원격 실험 명령은 **Debug opt-in 뒤에 남겨 뒀다.** 조사 종료 시 제거할지는 §6 잔여 검증이 끝난 뒤 결정한다. Release에 빈 진단 delegate나 폴링이 생기지 않았음은 바이너리 심볼로 확인했다.

### 변경하지 않을 계약

- TCA + MicroArchitecture 경계, `ChapterCanvasFeature.State.isReady` 합성 게이트.
- `ChapterCanvasView.hostedColumn`의 `.fixedSize(horizontal: false, vertical: true)`.
- N-Canvas 저장, legacy 승격 정책, DB 마이그레이션, 의존성·서명·빌드 설정.
- 회전 이후 전체 경로가 검증되기 전 단일 Canvas 기본 활성화.

## 6. 검증 계획과 완료 조건

### ✅ 완료한 검증

- Xcode 26.3 실기기 Debug 빌드, Tuist generate, 변경 Swift 파일 SwiftLint, `git diff --check` 통과.
- 시뮬레이터 전량 **302개** 통과 (설계 §19-4-2 기준선). rev.23 의 296에서 정식 수정 회귀 6건 추가 — 표시용 재구성의 속성·소유권 보존 · 마스크 파생값 고정점 · 지우개 절 1회 dirty · 빈/디코드 실패 · 같은 revision 무교체 · 회전 flush.
- 변이 테스트: 진단 명령의 `isApplyingDrawing` 억제를 제거하자 새 테스트가 `editEnded` 발생으로 실패(3 issues). 변이 복원 완료.
- 함수 단위 `only-testing`이 0개를 선택한 실행은 검증으로 세지 않았다. 스위트 전체로 재실행했다.
- **실기기 A/B (§3)** — 인자 없이 가로↔세로 3왕복 정상, `-CanvasReuseStrokesOnApply`로 결함 재현.

이 테스트들은 **데이터·편집 계약**을 검증한다. PencilKit의 실제 화면 버그를 자동 검출하는 렌더 회귀 테스트는 **여전히 없다** — 이 결함은 사람이 화면을 봐야만 판정된다.

### ❓ 남은 검증 — 이것이 끝나야 D9 H 종결

| # | 항목 | 상태 |
|---|---|---|
| 1 | 편집·저장 왕복 — 별도 테스트 장/복제 표본에서 새 필기·부분 지우개·undo/redo·장 이동·재실행 복원·N-Canvas 왕복 | ❓ 미수행 |
| 2 | 회전 직전 미보고 획이 이전 세대로 flush되고, 프로그램 표시 교체가 저장 mutation을 만들지 않는지 **실기기에서** 확인 | ❓ 미수행 |
| 3 | 긴 장(시편 119편)의 진입/재합성 시간과 physical footprint를 수정 전후 동일 조건 비교. 기준은 설계 §18-3-a 및 런북 §6-9 D9-8 | ❓ 미수행 |
| 4 | 스크롤 중 회전 | ❓ 미수행 |
| 5 | 글꼴/행간 변경, 좌우 필사 위치 — **E-4 재판정이 여기에 달려 있다** (런북 §8-7) | ❓ 미수행 |

> **증거 표본인 시편 120편 legacy 2·4절에는 새 획을 입력하지 않는다.** 미측정 수치를 합격으로 기록하지 않는다. 진단 테스트를 지워 기준선이 줄면 제거 이유와 대체 정식 회귀 테스트를 명시한다.

## 7. 로그와 인계

원본 로그는 조사 Mac의 `/tmp/carve-d9-display-evidence.log`, `/tmp/carve-d9-full-tests.log`, `/tmp/carve-d9-mutation.log`, `/tmp/carve-d9-final-controller-tests.log`에 있다. **임시 파일이므로 다른 세션·머신에서 존재한다고 가정하지 않는다.** 핵심 결과는 위 표에 남겼다. 원본 로그를 공유할 때는 인증값·개인정보가 섞이지 않았는지 확인하고, 전체 콘솔 대신 필요한 계측만 추린다.

다음 세션에 전달할 요청:

> §5 정식 수정은 이미 적용됐고(`ef053111`) 실기기 A/B로 인과까지 확인했다. 남은 일은 **§6 의 미수행 5건**이다 — 편집·저장 왕복, 회전 직전 flush 의 실기기 확인, 긴 장 성능 비교, 스크롤 중 회전, 글꼴/행간 변경(E-4 재판정). 실기기 조작은 device-debugging-cli.md를 따르고, 기본 검증은 `-CanvasReuseStrokesOnApply` **없이** 돈다. 검증되지 않은 항목을 완료로 기록하거나 D9 전체를 통과로 바꾸지 않는다.
