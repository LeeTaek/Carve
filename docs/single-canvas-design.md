# CarveFeature 단일 Canvas 전환 설계

> **상태 (rev.25):** Phase 0A~3 **구현 완료.** 단일 Canvas 는 feature flag `singleCanvasEnabled` 뒤에 있고 **기본 off** 입니다.
> 남은 것은 **실기기 검증 D9** (기본 활성화·배포 판단의 선행 조건, §16) 와 **Phase 4** (구 구조 제거) 입니다.
> D9 의 실행 절차와 기록 양식은 [런북 §6-9 · §8-7](./phase-0a-d-device-test.md) (rev.10) 에 있습니다.
>
> ✅ **종결:** R13 · R16 · R19 · **D9 H**(회전 표시) · **E-4**(결함 아님, D9 H 와 동일) · **R23**(flag off 로 열기만 해도 v3→v2 강등) · **R24**(같은 장 재로드가 기하 실측을 버려 잉크 미표시·R13 재발·Δ 실명) — 전부 수정·실기기 재확인 완료. §20-13 · §20-14 · §20-16 · 런북 §8-7.
> ✅ **D9-CK③ 완료 (2026-09-09)** — 운영 컨테이너 Production 에 `CD_layoutMetadataData` · `CD_rowUUID` 를 승격했습니다. **기본 활성화의 하드 블로커가 없습니다.**
> ⚠️ **출시 전 판단이 필요한 것:** **R25**(롱프레스 메뉴 교체 — 오탭이 전 획 선택으로) · **R22**(세로에서 redo 접근 불가) · **R28**(구버전 기기가 v3 행을 잘못 다룸 — 해석·강등 규칙이 미출시라 **위험 확정**) · **R27**(기존 행의 `rowUUID` 가 서버에 없어 중복 가능) · **R20**(저메모리 미검증).
> ✅ **정지 상태 메모리는 단일 Canvas 가 N-Canvas 보다 ~440 MiB 가볍습니다** (R21, 시편 119편 실측).
> ✅ **MetricKit 을 붙였습니다** — 보유하지 않은 저메모리·ProMotion 기기의 실태는 배포 후 `mk_daily` · `mk_memory_kill` 이벤트로 받습니다. ⚠️ **매핑 경로는 아직 한 번도 실행되지 않았습니다** (payload 는 하루 한 번, 기기에 과거 payload 도 0건). Xcode 의 **Debug → Simulate MetricKit Payloads** 로 한 번 태워 확인해야 합니다.
> ⚠️ **그 밖에 살아 있는 항목:** **R20**(회전 시 전이 메모리 peak 1.8 GiB — 저메모리 기기 미검증) · **R17**(Δ 가 R16 계열 미검출) · **R18**(N-Canvas 신규 행이 v1) · **R22**(팔레트 폭). 전부 §16 "남은 것".
> D9-1 · D9-2 · D9-3-1·2·4 · D9-4-1·4 · **D9-5** · **D9-6**(R23·R24 수정 후 재검증) · D9-7-1·3·4 · D9-8 · **D9-CK②·③** 통과. **D9-7-2 만 ❓ 미수행**(Pencil 입력이 필요해 자동화 불가) (런북 §8-7).
> ⚠️ Δ 0.00 은 실제 필기 표시의 정상 판정이 **아닙니다** — 계측은 "값이 도달했는가" 만 말합니다 (§20-16).
> [D9 H 분석](./single-canvas-rotation-display-investigation.md) · [실기기 조작](./device-debugging-cli.md).
> 회귀 기준선 **312** (§19-4-2). 대상: `Feature/CarveFeature`, `Feature/SettingsFeature`, `Domain`.
>
> **읽는 법.** §1~§17 이 설계이고 §18~§20 은 실측·변경 기록입니다. 절 번호는 코드 주석과 AGENTS.md 가 참조하므로 **바꾸지 않습니다.**
> 결정이 끝난 항목은 결정만 남기고 논의 과정은 지웠습니다 (rev.19 · rev.25 정리). 과정이 필요하면 git 이력(`git log -- docs/single-canvas-design.md`)을 보십시오.

| rev | 내용 | 참조 |
|---|---|---|
| 8 | 설계 초안 | — |
| 9 | S0/S1/S2 실측. §7-4·§7-5 전제 반전. 기존 코드 버그 2건 수정 | §18 · §19 · §20-1 · §20-2 |
| 10 | D8 legacy 데이터 추출. `normalizedForVerseRect` 가 실데이터 71% 에서 실패 | §10-2-1 · §20-3 |
| 11~12 | Phase 0B (레이아웃 · 소유권/승계 · reflow) · S4 스크롤 A/B 하네스 | §9-3-1 · §11 · §20-4 |
| 13 | Phase 1 V4 additive schema | §10 · §20-5 |
| 14 | 실기기 D1~D7. **스크롤 구조 B 확정** · CloudKit 스키마 승격 함정 | §2 · §11 · §12 · §18-3-a · §20-6 · §20-7 |
| 15 | Phase 2 — `VStack` + 실측 파이프라인 + 게이트 + 오버레이 | §6 · §20-8 |
| 16 | Phase 3 (1/3 · 2/3) — 저장 계층 · 코덱 · 리듀서 · B 호스팅 + flag | §8 · §11 · §20-9 |
| 17 | (2/3) 리뷰 결함 15건 수정 — 편집 세대 · 재합성 출구 · v3 행 호환 | §20-10 |
| 18 | (3/3) — 히스토리 메뉴 재설계 · 설정 토글 | §20-11 |
| 19 | 승계 규칙 3 을 규칙 2 의 전제 위에서만 적용 (U1 보장) · 문서 정리 | §7-3 · §20-12 |
| 20 | **D9 실기기 검증에서 레이아웃 결함 2건** — 절당 0.5pt 누적(R13) · 장 전환 시 컬럼 신장(R16) | §11 · §15 · §16 · §20-13 |
| 21 | **R13 종결** — 행 높이 실측을 레이아웃 입력으로 승격 · Δ 안전망 · D9-1 보류 해제 | §14 · §15 · §16 · §20-14 |
| 22 | D9-1~D9-6 통과. 합성 프로브 추가 · E-4 를 "결함 아님"으로 판정(**rev.25 에서 미확정으로 되돌림**) · R18 | §14 · §16 · 런북 rev.7 |
| 23 | D9 H 회전 표시 결함 원인 분리 · Debug A/B 왕복 통과 · **정식 수정 미적용** · 기준선 296 | §19-4-2 · §20-15 · 런북 rev.8 |
| 24 | **D9 H 정식 수정** — 표시용 획 재구성 승격 · 실기기 3왕복 + 양성 대조 통과 · 기준선 302. **§6 잔여 검증은 남음** | §19-4-2 · §20-16 |
| 25 | 문서 정리 (런북 rev.10) — 낡은 상태 서술 정정 · 살아 있는 항목(D9 H · E-4 · R17 · R18 · R19)을 §16 에 모음 · rev.19 원칙으로 과정 압축 | §16 · §20-15 |
| 26 | **D9 H · E-4 종결** — 조사 §6 잔여 5건 실기기 수행(글꼴/행간 · 스크롤 중 회전 · 좌우 필사 · 편집 저장 왕복 · 회전 직전 flush · 긴 장 성능). 매 항목 양성 대조 동반. ⛔ **그 과정에서 N-Canvas 롤백 경로의 선재 결함 R23 · R24 발견 — 기본 활성화 차단.** 성능 R20 · R21, UI R22 추가. 기준선 302 유지 | §16 · 런북 §8-7 · [조사 §3·§6](./single-canvas-rotation-display-investigation.md) |
| 27 | **R23 수정** — flag off 로 장을 열기만 해도 v3 절이 v2 로 강등되던 결함을 `isApplyingDrawing` 억제로 닫음(설계 §10-3 준수). 회귀 2건 · 변이 확인 · 실기기 170행 불변. **기준선 302 → 304.** ⛔ **R24 는 별개 결함으로 남음** | §16 · §19-4-2 · 런북 §8-7 |
| 28 | **R24 수정** — 같은 장 재로드가 기하 실측을 버려 ① 잉크 미표시 ② 실측 높이 → 예측식 후퇴(R13 재발) ③ Δ 안전망 실명을 함께 만들던 결함을 닫음. 회귀 4건 · 변이 확인 · 실기기 재확인. **기준선 304 → 308.** **D9-6 은 ✅ 통과로 복귀** | §6 · §16 · §19-4-2 · 런북 §8-7 |
| 29 | **R21 종결** — 같은 절차로 N-Canvas 를 재어 비교. 단일 Canvas 가 정점 ~435 MiB · 안정 ~440 MiB **더 가볍다**(N-Canvas 는 스크롤할수록 캔버스가 쌓임). D5 와의 차이는 절차 차이였다. 코드 변경 없음, 기준선 308 유지 | §16 · 런북 §8-7 D9-8 |
| 30 | **단일 Canvas 기본 전환 (Phase 3 완료)** — `SingleCanvasFlag.defaultValue` 도입, 읽는 쪽 둘의 기본값 일치. 명시적 off 는 유지(§10-3). **R20 실측**: 한도 3376 MB · 회전 peak 1839.2 MB · N-Canvas 정지 1322 MB 대비 재해석. 기준선 **310** | §10-3 · §16 · §19-4-2 |
| 31 | **R26 수정** — 장 전환에서 이전 본문 컬럼을 놓는다. 긴 장을 떠난 뒤 **945 → 124.4 MB**. 회전 전이는 콘텐츠 넓이에 비례함을 실측(짧은 장은 전이 0). 기준선 310 → **312** | §5 · §16 · 런북 §8-7 |
| 32 | **D9-CK③ 완료** — CloudKit 운영 컨테이너에 `CD_layoutMetadataData` · `CD_rowUUID` 승격. 배포 전 죽은 필드 3개와 `CD_BiblePageDrawing` 정리. **기본 활성화 하드 블로커 해소.** R27 · R28 신설 | §10-1-a · §16 · 런북 §8-7 |
| **33** | **롤백된 옛 단일 Canvas 구현 제거** — `CombinedCanvasFeature`·`CombinedCanvasView` 967줄. 살아 있는 참조가 0건이었고 삭제 후 312 통과. 낡은 deprecation 문구도 실제 대체재(단일 Canvas / `delegatesUndoToCanvas`)로 정정 | §11 · §16 |

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
| D5 | **스크롤 컨테이너 2개** — `PKCanvasView`는 `UIScrollView`(SDK 확인)인데 SwiftUI `ScrollView` 안에 넣어 offset drift. `StableCanvasView`와 issue #6의 원인 | [CombinedCanvasView.swift:21](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasView.swift) |
| D6 | **레이아웃 메타데이터 없음** — 어떤 폭/폰트에서 그려졌는지 기록이 없어 G4가 원리적으로 불가능 | [DrawingSchemaV3.swift](../Domain/Domain/Sources/SwiftData/Model/DrawingSchemaV3.swift) |
| D7 | **지우개/undo 저장 누락** — stroke 수 증가시에만 변경 영역 계산, 빈 결과는 skip → 마지막 획 삭제가 DB에 반영 안 됨 | [CombinedCanvasView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasView.swift), [CombinedCanvasFeature.swift:186](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CombinedCanvasFeature.swift) |
| D8 | **저장이 원자적이지 않음** — 요청마다 개별 `save()`, 에러를 per-item으로 삼킴 → 부분 갱신 상태 발생 | [DrawingDatabase.swift:97](../Domain/Domain/Sources/SwiftData/DrawingDatabase.swift) |
| D9 | **편집 순서 미보장** — 연속 편집의 비동기 저장이 직렬화되지 않으면 최신 편집이 과거 편집에 덮일 수 있음 | 신규 |

**`StableCanvasView` 는 별도 파일이 아니라 `CombinedCanvasView.swift` 21~458행의 클래스**입니다. 하는 일은 ① scale 강제 동기화 ② `contentSize/inset/offset/zoom` 리셋 ③ 디버그 덤프 셋뿐입니다.

#### D5 의 실체 — 오차는 바깥 `ScrollView` 의 `contentOffset` 입니다 (실기기 D1, §11)

| 관측 | 해석 |
|---|---|
| 구조 A 에서 hover 할 때 **시스템이 그리는 펜슬 그림자는 정상 위치**에 뜨는데 **PencilKit 이 그리는 hover 잉크 점만 어긋난다** | 그림자는 윈도우 좌표계, 잉크 점은 **캔버스 자신의 content 좌표계**. 어긋나는 것은 입력이 아니라 **캔버스가 자기 스크롤 상태를 무엇으로 믿는가**다 |
| **어긋남의 크기가 스크롤 깊이에 비례** (맨 위에서는 정상) | **오차 = 바깥 `ScrollView` 의 `contentOffset`** |
| `StableCanvasView` 상당의 정규화(②)를 켜도 **동일하게 실패** | 보정으로 구제할 수 있는 문제가 아니다 |

②는 캔버스의 `contentOffset` 을 0 으로 고정하는데, PencilKit 의 라이브·hover 렌더는 **자기 스크롤 상태가 실제와 일치할 것을 전제**합니다.
drift 를 막으려는 바로 그 행위가 PencilKit 의 좌표 계산을 깨뜨립니다 — **구조 A 에서는 둘을 동시에 만족시킬 수 없습니다.** 이것이 두 번의 롤백과 issue #6 을 설명하며, §11 이 B 를 확정한 근거입니다.

---

## 3. 설계 원칙

| # | 원칙 | 해소 대상 |
|---|---|---|
| P1 | **획은 자르지 않는다.** 한 획은 통째로 한 절에 귀속된다 | D1 |
| P2 | **소유권은 편집 시점에 결정하고 승계한다.** 기하로 매번 재유도하지 않는다 | D2 |
| P3 | **좌표 형식은 `drawingVersion`으로 명시 기록한다.** 추측 금지 | D3 |
| P4 | **레이아웃이 전량 준비될 때까지 합성·입력·저장을 금지한다** | D4 |
| P5 | **스크롤 컨테이너는 하나.** 형태는 spike 로 확정 → B (§11) | D5 |
| P6 | **저장 시점의 레이아웃 메타데이터를 함께 남긴다** | D6 |
| P7 | **빈 결과도 mutation이다.** dirty 집합을 먼저 구하고 `clear`를 명시 생성 | D7 |
| P8 | **한 편집의 모든 절 저장은 단일 트랜잭션이다** | D8 |
| P9 | **Feature는 PencilKit/UIKit 타입을 모른다.** `Data`와 도메인 DTO만 다룬다 | 룰북 |
| P10 | **레이아웃 변경은 표시 변환일 뿐, 저장을 덮어쓰지 않는다** | 원본 보존 |
| P11 | **편집 결과는 즉시 화면에 확정하고, 저장은 revision으로 직렬화한다** | D9 |

---

## 4. 아키텍처 경계

```
ChapterCanvasView / ChapterCanvasController   ← PencilKit 타입은 여기까지만
    PKCanvasView, PKDrawing, PKTool
            ↓ Data + DTO
ChapterCanvasFeature                          ← 상태/액션/저장 orchestration
    State, Action                                PencilKit 타입 없음
            ↓ Dependency
DrawingCodecClient (DrawingCodec)             ← PencilKit을 아는 유일한 Dependency
    합성 / 소유권 / reconcile / reflow / transform 적용
            ↓
DrawingRepository (SwiftDataDrawingRepository) ← SwiftData 단일 접근 경로
    atomic batch create/replace/clear
```

### 좌표 관련 책임 분리

| 컴포넌트 | 책임 |
|---|---|
| `ChapterLayoutBuilder` | 좌표 **영역**을 계산 (rect, 밑줄 anchor, 높이) |
| `DrawingCodec` | Drawing에 **transform을 적용하는 유일한 곳** — `columnOrigin` 평행이동 · reflow · `storageOrigin` localize |

Feature·View·Repository는 좌표 변환을 수행하지 않습니다. (예외: N-Canvas 가 v3 행을 표시할 때의 첫 밑줄 평행이동 — §10-3.)

### 모듈 배치 — 순환 의존 회피

의존 방향은 `Domain → ClientInterfaces` 이므로 `BibleChapter` 를 쓰는 계약을 `ClientInterfaces` 에 둘 수 없습니다.

```
Domain
 ├─ ChapterLayout, VerseCanvasRegion, VerseDrawingSnapshot, VerseDrawingMutation, DrawingLayoutMetadata
 ├─ DrawingRepository 계약 + SwiftDataDrawingRepository
 └─ SingleCanvasFlag (feature flag 키 — CarveFeature 와 SettingsFeature 가 공유)

CarveFeature
 ├─ ChapterCanvasFeature · ChapterCanvasView · ChapterCanvasController
 └─ DrawingCodec · DrawingCodecClient · StrokeOwnershipResolver · LineBandReflow
```

`DrawingCodec` 이 `CarveFeature` 에 있어도 룰북 위반이 아닙니다 — 경계는 **모듈**이 아니라 **Reducer** 이고, `CarveFeature` 는 이미 PencilKit 을 의존합니다. 새 모듈은 추가하지 않았습니다.

### State / Action

실제 정의는 [ChapterCanvasFeature.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/ChapterCanvas/ChapterCanvasFeature.swift) 입니다. 상태는 다섯 묶음입니다.

| 묶음 | 필드 | 의미 |
|---|---|---|
| §6-4 게이트 입력 | `expectedVerseCount` · `layout` · `loadedDrawings` · `loadRequestID` · `loadFailure` · `columnOrigin` | 도착 순서가 보장되지 않는 두 입력. `loadedDrawings` 는 **마지막으로 알고 있는 DB 내용**이며 성공한 저장을 겹쳐 둔다 |
| 합성 결과 (세대) | `renderedData` · `renderedRevision` · `renderedLayout` · `renderedColumnOrigin` · `ownership` · `activeRowIDs` · `layoutMismatchVerses` · `legacyVerses` · `undecodableVerses` | `renderedRevision` 은 합성마다 **그리고 장 진입마다** 오른다. 큐의 편집은 `rendered*`(합성 시점 값)로 계산한다 |
| §8-1 편집 계약 | `editRevision` · `isEditing` · `pendingLayout` · `pendingColumnOrigin` · `pendingReload` · `editQueue` · `isPreparingEdit` · `baselineData` · `retiredSession` | 편집 중 도착한 변경은 pencil-up 뒤 한 번에 적용. `retiredSession` 은 직전 세대의 편집 문맥 (`EditSession`) |
| §8-3 저장 대기열 | `pendingMutations` · `saveStatus` · `inFlightBatch` · `inFlightMutations` · `inFlightChapter` · `reloadWhenSettled` · `isReloading` · `persistedRevision` | rowID 키 coalescing, 저장은 동시에 하나 |
| 표시 요청 | `canUndo/canRedo`(`@Shared(.inMemory)`) · `undoRequestVersion` · `redoRequestVersion` · `scrollRequest` · `scrollRequestToken` · `lastDirtyBounds` · `lastEditedVerse` | 뷰가 카운터 변화로 수행. 스크롤 토큰은 장이 바뀌어도 이어진다 |

`renderedData` 를 State 에 두는 이유: `@ObservableState` 는 keypath 단위 관찰이라 `Data` 필드는 쓰기 시에만 무효화됩니다. Coordinator 는 `renderedRevision` 이 바뀔 때만 디코드합니다.

---

## 5. 데이터 모델 (DTO)

```swift
/// 절 하나의 캔버스 좌표 정보 (Domain)
struct VerseCanvasRegion: Equatable, Sendable {
    let verse: Int
    /// §6-3 Pass 2 의 여유 높이를 포함한다. 밑줄이 그려지는 구간은 텍스트 줄 수만큼.
    let writingRect: CGRect
    /// 획 소유권을 판정하는 영역 (인접 절과의 midpoint로 분할)
    let captureRect: CGRect
    /// 밑줄 y (writingRect 기준 상대값)
    let underlineAnchors: [CGFloat]
    /// 저장 origin = (writingRect.minX, 첫 밑줄 y)
    var storageOrigin: CGPoint
}

/// 장 전체 레이아웃 — 단일 좌표계의 유일한 진실 공급원. 원점은 필사 컬럼 좌상단 (writingRect.minX == 0).
struct ChapterLayout: Equatable, Sendable {
    let chapter: BibleChapter
    let writingWidth: CGFloat
    let totalHeight: CGFloat
    let regions: [VerseCanvasRegion]
    let signature: String                  // §6-5 안정적 signature. chapter 는 넣지 않는다 (U7)
}

/// BibleDrawing 행 식별자 — 신규 행은 선발급 UUID, legacy 행은 business id (§8-7)
struct BibleDrawingRowID: Hashable, Sendable, Comparable { let raw: String }

/// DB 에서 읽어온 절 하나의 저장 상태 (행 단위)
struct VerseDrawingSnapshot: Equatable, Sendable {
    let verse: Int
    let rowID: BibleDrawingRowID
    let isPresent: Bool
    let updateDate: Date?
    let lineData: Data?                    // 비워진 행(clear 이후)은 nil — 빈 Data 는 유효한 인코딩이 아니다
    /// nil / 1 = legacy, 2 = verse-local + top-left (N-Canvas 형식), 3 = verse-local + 첫 밑줄 원점 + metadata
    let drawingVersion: Int?
    let metadata: DrawingLayoutMetadata?   // drawingVersion == 3 일 때만
}

/// 획 ↔ 절 소유권. map 은 "원본 획 → 절" 이며 canvas 엔트리와 1:1 이 아니다 (§7-2)
struct OwnershipSnapshot: Equatable, Sendable {
    let map: [StrokeIdentityKey: Int]
    let layoutSignature: String
}

/// 편집 종료 스냅샷 (PencilKit 타입 없음)
struct CanvasEditSnapshot: Equatable, Sendable {
    let drawingData: Data                  // 편집 직후 content 좌표 drawing
    let dirtyBounds: CGRect?               // 디버그 표시용
    let reason: EditReason                 // ink · erase · undo · redo
    /// 편집 당시 캔버스가 표시하던 renderedRevision — Feature 가 자기 세대의 문맥으로 계산한다 (§8-1)
    let generation: Int
}

/// 한 세대의 편집 문맥. 장 전환·재합성 뒤 늦게 도착한 편집을 옛 기준으로 계산하기 위해 물려 둔다
struct EditSession: Equatable, Sendable {
    let generation: Int; let chapter: BibleChapter
    let layout: ChapterLayout; let columnOrigin: CGPoint
    var activeRowIDs: [Int: BibleDrawingRowID]; var ownership: OwnershipSnapshot; var baselineData: Data
}

/// 저장 명령 — 절이 아니라 **행**을 주소지정한다 (U2)
enum VerseDrawingMutation: Equatable, Sendable {
    case replace(verse: Int, rowID: BibleDrawingRowID, data: Data, metadata: DrawingLayoutMetadata)
    case clear(verse: Int, rowID: BibleDrawingRowID)                   // 행을 삭제하지 않는다
    case create(verse: Int, rowID: BibleDrawingRowID, data: Data, metadata: DrawingLayoutMetadata)  // rowID 는 선발급
}
```

소유권 앵커는 각 획 **자신의 첫 control point** 입니다. 한 번의 pen-down 이 복수 획을 만드는 경우와 undo/redo 를 모두 덮기 위함이며, pencil-down 좌표는 쓰지 않습니다.

### captureRect — 절 사이 gap 흡수

```
Verse 1 writingRect
──────────────────── midpoint   ← captureRect 경계
Verse 2 writingRect
──────────────────── midpoint
Verse 3 writingRect
```

첫 절 위쪽과 마지막 절 아래쪽은 캔버스 끝까지 확장합니다.

**여유 높이는 `writingRect` 안에 둡니다.** §6-3 Pass 2 의 `extraHeight` 를 절 사이 gap 으로 두면 midpoint 분할로 그 절반이 다음 절 소유가 됩니다.
초과 band 는 그 절의 것이므로 `writingRect` 하단에 포함하고, `underlineAnchors` 는 텍스트 줄 수만큼만 만듭니다 ([ChapterLayoutBuilder.swift](../Domain/Domain/Sources/Layout/ChapterLayoutBuilder.swift)).

#### 캔버스 좌표 — `columnOrigin` (U5 확정)

B 구조에서 캔버스는 화면 전폭이고 필사 컬럼은 그 안의 한 영역입니다. `ChapterLayout` 은 "필사 컬럼 = 원점" 좌표계를 유지하고, 평행이동 한 겹만 둡니다.

```
캔버스 content 좌표 = layout 좌표 + columnOrigin        (columnOrigin.y = 0)
```

| 계층 | `columnOrigin` 에 대해 하는 일 |
|---|---|
| 호스팅 | **값의 출처.** `CarveDetailFeature.applyVerseGeometry` 가 절 행의 실측 frame 으로 `ChapterLayoutMeasurement.columnOrigin` 을 얻어 `columnOriginChanged` 로 올린다. 오른손 · iPad mini 세로에서 **x = 366.70** (`halfWidth + 10` 이 아니다 — 행 폭이 제안 폭을 9pt 넘쳐 HStack 이 가운데 정렬된다. "예측하지 말고 실측하라") |
| Feature | **보관·전달만.** 값이 바뀌면 미저장분을 저장한 뒤 다시 합성한다 |
| `DrawingCodec` | **적용의 유일한 지점.** 합성 시 `layout → content`, 소유권 판정 직전 `content → layout`, 저장 전 `storageOrigin` localize |

#### 하단 safe area 인셋 (U6 확정)

`contentInsetAdjustmentBehavior = .never` 를 유지하고(자동 인셋 조정은 offset drift 의 원인) 컨트롤러가 `contentInset.top = 헤더 높이`, `contentInset.bottom = safeAreaInsets.bottom + 24` 를 직접 넣습니다.
**콘텐츠 좌표는 인셋과 무관**합니다 — 화면 여백이 저장 좌표에 스며들지 않도록 `totalHeight` 에 여백을 더하지 않습니다. 텍스트 호스트의 frame 은 **컬럼 자신의 높이**이고 `contentSize` 만 뷰포트 이상입니다 (§20-10 ③).

#### signature 에 `chapter` 를 넣지 않습니다 (U7 확정)

signature 는 "레이아웃 **형식** 호환성" 판정입니다. 필사가 어느 장의 것인지는 행이 알고, 조회도 장 단위라 다른 장의 행이 합성에 들어올 경로가 없습니다. `chapter` 를 넣으면 같은 형식이 장마다 다른 signature 가 되어 `layoutMismatch` 가 장마다 오탐합니다.

---

## 6. ChapterLayout — 측정과 게이트

### 6-1. LazyVStack → VStack

전 절의 geometry 가 있어야 합성이 성립하므로 비지연 `VStack` 으로 전환합니다. **단, 비지연으로 만드는 것은 텍스트 행까지입니다.** 문자 그대로의 전환(행 176개 + `PKCanvasView` 176개 즉시 생성)은 출시할 수 없었습니다 (시뮬레이터 Debug, 시편 119편 cold launch):

| 구성 | 누적 CPU | footprint peak | 첫 레이아웃 완성 | 캔버스 생성 |
|---|---:|---:|---:|---:|
| 행별 실측 액션 (일괄 처리 전) | **2분 넘게 완료 못 함** | 2.9 GB ↑ | — | 9,000개 ↑ |
| `VStack` + 캔버스 176개 즉시 + 행별 중첩 `UIHostingController` | 18.4 s | 613 MB | 9.03 s | 176 |
| `VStack` + 캔버스 176개 즉시, 중첩 호스팅 제거 | 16.2 s | 559 MB | 6.79 s | 176 |
| **`VStack` + 캔버스 지연(sticky) + 중첩 호스팅 유지 — 채택** | **5.4 s** | **198 MB** | **0.71 s** | **30** |
| (참고) Phase 2 이전 `LazyVStack`, 같은 날 같은 절차 | 3.1 s | 83 MB | — | 20 |

전 절 geometry 가 필요한 이유는 **텍스트 실측**이지 캔버스가 아닙니다. 행(본문·밑줄·frame 실측)은 전부 즉시 만들고, `PKCanvasView` 는 뷰포트 위아래 1.5 화면 안의 행에만 만들되 한 번 만든 것은 유지합니다 (`CarveDetailView.activeCanvasIDs`). 결과는 진입 +100 MB · +2.3 s (= 텍스트 행 176개의 값), 스크롤 비용은 옛 코드와 같습니다 (§20-8).

**구조적 함정 2건 — B 구조에도 그대로 적용됩니다.**

| # | 함정 | 조치 |
|---|---|---|
| 1 | **행별 실측 액션.** 행마다 액션을 보내면 액션 하나가 부모 상태를 바꾸고 TCA 가 스코프 스토어(행 176 × 자식 4)를 전부 재평가한다 — O(N²). `LazyVStack` 은 보이는 행만 있어 드러나지 않았다 | `VerseGeometryCollector` — 콜백은 행마다 받되 **런루프 한 틱에 한 액션** (`verseGeometryMeasured`). B 의 `layoutCompleted` 도 같은 규율 |
| 2 | **`VStack` 은 내용 폭을 보고한다.** 행 폭이 제안 폭을 넘으면 세로 `ScrollView` 가 가로로 같이 넓어지고 그 폭에서 다시 `halfWidth` 를 읽어 발산한다 (372 → 376.7 → 381.3 → …, 고정점 1120, 매 단계 행 전체 재생성) | 폭은 바깥 `GeometryReader` 에서 읽고 콘텐츠를 `.frame(width: halfWidth × 2)` 로 고정 |

**`.named` 좌표 공간의 함정 (rev.16).** 행은 `touchIgnoringContextMenu` 가 만드는 중첩 `UIHostingController` 안에 있어 바깥 트리의 `coordinateSpace(name:)` 을 보지 못하고, SwiftUI 는 이름을 못 찾으면 **오류 없이 `.global` 로 대체**합니다. 그래서 행 frame 은 **바깥 트리**에서 `.named(ChapterContent)` 로, 캔버스 영역은 행 자신의 공간(`ChapterLayoutHosting.rowCoordinateSpaceName`)에서 재어 합칩니다 (`ChapterLayoutMeasurement.recordRowFrame / recordCanvasFrameInRow`). **Δ 검증은 반드시 출시 구성에서** — HUD `Δ max` 가 0 이 아니면 레이아웃보다 측정 경로를 먼저 의심합니다.

**행별 중첩 `UIHostingController` (`touchIgnoringContextMenu`)** 는 유지하되 Phase 4 삭제 대상입니다. 채택 구성에서의 이득이 footprint −18 MB · 완성 −0.23 s 뿐이고 CPU 는 같아, 사용자 동작 변화 없이 두었습니다.

**`ChapterLayout` 캐시는 구현하지 않기로 결정했습니다 (rev.18).** B 에서도 텍스트 컬럼은 같은 SwiftUI 행이라 실측이 렌더링에 내재하며, 캐시가 앞당기는 것은 게이트가 열리는 시점뿐입니다. 캐시된 레이아웃으로 먼저 합성하면 폰트·OS 차이로 실측과 어긋난 좌표에 잉크를 놓을 위험이 생깁니다 — §2 의 두 번 롤백과 같은 유형입니다. 시편 119편 게이트가 0.7~0.9 s 인 지금 그 위험을 살 이유가 없습니다.

### 6-2. 입력 게이트 (P4)

아래 조건을 모두 만족하기 전에는 **합성·입력·저장을 모두 금지**합니다.

```swift
layout.regions.count == sentences.count && layout.totalHeight > 0 && layout.writingWidth > 0
```

`PKCanvasViewDrawingPolicy` 에는 "입력 금지" 값이 없으므로(`.default` / `.anyInput` / `.pencilOnly` 뿐) 게이트는 `drawingGestureRecognizer.isEnabled` 입니다.
판정은 `ChapterLayoutMeasurement.isReady` (= `layout.satisfiesCompositionGate(expectedVerseCount:)`) 한 곳이고, 단일 Canvas 는 여기에 `isComposed && !isReloading` 을 더합니다. 시편 119편에서 176/176 → PASS 까지 0.7~0.9 s.

> ⚠️ **새 실패 모드.** 어떤 절의 `Text.LayoutKey` 가 끝내 도착하지 않으면 게이트가 열리지 않아 **그 장 전체가 필기 불가**입니다 (옛 코드에서는 "그 절의 밑줄만 없음"). HUD 의 `missing` 줄로 관찰합니다. 실기기·저사양 기기 확인은 남아 있습니다.

### 6-3. 2-pass 높이 계산

**줄 수가 줄어드는** 리플로우(폭 증가 / 폰트 감소 / 자간 감소)에서는 저장된 필사가 텍스트보다 많은 줄을 요구할 수 있습니다.

```
Pass 1  텍스트 기준 각 절의 밑줄 개수 / 높이 측정
Pass 2  절의 저장 band 수(N_saved)와 현재 밑줄 수(N_now)를 비교
        N_saved > N_now 이면  extraHeight = (N_saved - N_now) × lineSpace
        effectiveHeight = 텍스트 높이 + extraHeight → 레이아웃 재계산
```

Pass 2 는 **band 개수만** 사용하므로 좌표 계산이 필요 없고, reflow 결과에 레이아웃이 의존하는 순환이 생기지 않습니다.

### 6-4. 로드 순서와 합성 게이트

`drawingsLoaded`(`DrawingRepository.load`)와 `layoutCompleted`(전 절 실측)는 **도착 순서가 보장되지 않습니다.** 둘 다 State 에 보관하고 양쪽에서 같은 `composeIfReady` 를 호출합니다.

**장 전환 시 취소:** 장을 바꾸면 새 `loadRequestID` 를 발급하고, 이전 requestID 로 도착한 조회 결과는 폐기합니다. 실측 이벤트는 행 id 가 장을 포함하므로 id 조회 실패 = 폐기입니다.

**합성 입력은 항상 `DB 내용(loadedDrawings) ⊕ 이 장의 미저장분(pendingMutations)` 입니다** (rev.17). 저장이 실패한 채 장을 떠났다 돌아와도, 재합성 중 저장이 실패해도 미저장 잉크가 화면에서 사라지지 않습니다. 성공한 저장은 `loadedDrawings` 에 겹쳐 두 값의 합이 항상 현재 내용입니다.

### 6-5. layoutSignature는 영속 가능한 값이어야 함

Swift `hashValue` 는 프로세스마다 시드가 달라집니다. canonical 문자열(또는 안정적 digest)을 쓰고 다음을 포함합니다: `formatVersion` · `fontFamily` · `fontSize` · `tracking` · `lineSpace` · `writingWidth` · `layoutDirection`(isLeftHanded). `chapter` 는 넣지 않습니다 (U7).

---

## 7. 획 소유권과 승계

### 7-1. 소유권 규칙 (P1)

```
신규 획의 첫 control point (layout 좌표 — Codec 이 content 에서 역변환)
    ↓ ChapterLayout.captureRect 검색
ownerVerse 결정 → stroke 전체를 ownerVerse 에 저장 (자르지 않음)
```

**U1 — 여러 절을 지나는 획은 시작한 절에 속하며, 레이아웃 변경 시 시작 절과 함께 이동합니다** (제품 정책). "4절 영역에 걸친 부분은 4절과 함께" 요구가 생기면 손실 없는 path 분할 또는 chapter-level stroke 모델이 필요하며 별도 설계입니다.

**U8 — 앵커가 캔버스 밖이면 캔버스 안으로 클램프**합니다 (`DrawingCodec.adoptUnownedStrokes`). 소유자 없는 획은 저장에서 빠져 유실되므로, 앵커를 `(0…writingWidth, 0…totalHeight)` 로 클램프한 뒤 `verse(containing:)` 로 **가장 가까운 절**에 귀속시킵니다. B 에서 캔버스는 전폭이라 가로 밖 시작은 없고, 세로는 bounce 구간의 음수 y 가 해당합니다.

### 7-2. 두 종류의 키 — identity와 content signature ★

**하나의 fingerprint로는 안 됩니다.** 용도가 정반대이기 때문입니다.

```swift
/// 같은 논리적 stroke인지 — owner 승계용. bitmap 지우개가 바꾸는 mask 를 **제외**한다.
struct StrokeIdentityKey: Hashable { randomSeed: UInt32; creationTime: TimeInterval; pointCount: Int }

/// 저장 내용이 변경됐는지 — dirty 판정용. mask/path/transform/ink 를 **포함**한다.
struct StrokeContentSignature: Hashable { identity; pathDigest; maskDigest?; transform; inkDigest }
```

```
IdentityKey 동일        → 기존 owner 승계        (§7-3)
ContentSignature 변경   → 해당 verse를 dirty 판정 (§8-2)
```

> **⚠️ `StrokeIdentityKey` 는 canvas stroke 엔트리와 1:1이 아닙니다 (S1-2).** bitmap 지우개가 만든 조각들은 **같은 IdentityKey 를 공유**합니다. 키는 "원본 획 → 절" 의 매핑입니다. 따라서 `map.count` 를 stroke 개수로 쓰거나 map 을 순회해 stroke 를 열거하는 것은 **금지**입니다 — 열거는 항상 `drawing.strokes`, map 은 조회에만.

> **⚠️ `maskedPathRanges.isEmpty` 로 "마스크 없음" 을 판정하지 마십시오 (S1-5).** `mask == nil` 인 stroke 의 `maskedPathRanges` 는 path 전체 구간입니다. `mask` 는 지워진 영역이 아니라 **남은(가시) 영역**의 clip 입니다.

이 분리가 없으면 D7 이 재발합니다 — mask 를 제외한 키 하나로 dirty 를 판정하면 bitmap 지우개는 identity 를 바꾸지 않으므로 "승계는 됐지만 지우기가 저장되지 않는" 상태가 됩니다.

### 7-3. 승계 (reconciliation)

편집 때마다 전량 재판정하면 리플로우 후 소유권이 옆 절로 흘러갑니다. 기존 획은 소유권을 **승계**합니다 ([StrokeOwnershipResolver.swift](../Feature/CarveFeature/Sources/Drawing/StrokeOwnershipResolver.swift)).

1. `StrokeIdentityKey` 완전 일치 → 기존 owner 승계. **S1-2/S1-4 · D3 실측상 bitmap 지우개 경로는 전부 여기서 해결됩니다** (조각들이 키를 공유).
2. `randomSeed` **또는** `creationTime` 이 이전 세대의 어떤 획과 일치하면 "같은 논리적 획의 변형" 으로 보고 3번으로 넘깁니다. 유사도 임계값은 두지 않습니다 — 근거 없는 상수는 조용한 오소유를 만듭니다. 그 역할은 3번의 겹침이 합니다.
3. **2번의 전제가 있는 획에 한해** 이전 세대 획의 `renderBounds` 와 가장 많이 겹치는 owner 승계 — 면적 최대가 1차, 동점이면 verse 최소 (결정적). `.vector` 지우개 전환이나 예외 상황용입니다.
4. 그 밖 (= **새 획**) → 첫 control point 의 `captureRect` 로 신규 귀속 (§7-1, U1).

> **rev.19 — 3번을 2번의 전제 위에서만 적용합니다.** 이전 구현은 identity 가 맞지 않는 모든 획에 3번을 4번보다 먼저 적용했습니다. `.bitmap` 지우개는 1번이 전부 처리하므로 3번이 실제로 발동하는 것은 **새 획**뿐이었고, 새 획이 이웃 절 잉크의 bounds 와 겹치면(절 경계 근처의 긴 획 · 큰 글씨) 시작 절이 아니라 이웃 절에 귀속돼 reflow 때 그 절과 함께 움직였습니다 — U1 위반입니다. 새 획은 seed 도 creationTime 도 새것이라 2번의 전제가 없고, 곧바로 4번으로 갑니다. (§20-12)

3번의 "겹침" 은 `captureRect` 가 아니라 **이전 세대 stroke 의 `renderBounds`** 와의 겹침입니다. 그래서 승계 함수는 이전 `OwnershipSnapshot` 뿐 아니라 이전 `PKDrawing` 도 받습니다 (map 순회는 §7-2 가 금지).

`StrokeIdentityKey` 는 영구 ID 가 아닙니다. **한 편집 세션 안에서 owner 를 승계하기 위한 도구**이며, 세션이 끊기면 DB 의 절별 그룹이 진실입니다. `previous.layoutSignature` 와 현재 signature 가 달라도(리플로우) 재판정하지 않습니다 (P2 · P10).

### 7-4. 지우개 모드 — `.bitmap` 유지로 확정 (U3)

S1-2 · D3 실측: **bitmap 지우개는 분할과 마스킹을 동시에 합니다.** 획 하나의 중간을 지우면 엔트리가 +1 되고, 두 조각은 `path` 의 control point 값까지 원본과 동일하며 `mask` / `maskedPathRanges` / `renderBounds` 만 다릅니다.

```
BEFORE strokes = 2 → AFTER (중간만 지움) strokes = 3
  [0] seed=956091164 pts=10 mask=(203,6,112,8)  ranges=[5.003…9.0]
  [1] seed=956091164 pts=10 mask=( 51,5,112,8)  ranges=[0.0…3.663]
  [2] seed=491497907 pts=10 mask=nil            ranges=[0.0…9.0]
```

조각 전부가 원본과 같은 `StrokeIdentityKey` 를 가지므로 §7-3 1번만으로 승계됩니다. `.vector` 전환은 "부분 지우기" UX 를 바꾸며 단일 Canvas 전환과 함께 바꾸면 회귀 원인 분리가 어려워지므로 하지 않습니다.

### 7-5. "빈 절" 판정과 저장 가드

S1-3 · D3 실측: `PKEraserTool(.bitmap)` 로 획을 **완전히** 지우면 그 stroke 는 `drawing.strokes` 에서 **제거됩니다.** 따라서 `strokes.isEmpty` 는 정상 동작하며 `isFullyMasked` 같은 헬퍼는 필요 없습니다. 방어적으로 `renderBounds` 기반 가시성 검사만 유지합니다 (`.vector` · OS 변경 대비).

그 실측이 드러낸 프로덕션 버그 — "마지막 획을 지우고 재기동하면 지운 획이 되살아난다" — 는 `7ba5bc46` 으로 **N-Canvas 위에서 먼저 고쳤습니다** (§20-2): 저장 가드(`containsPKStroke`)를 제거하고 leading-edge throttle 옆에 trailing-edge debounce 를 두었습니다. `containsPKStroke` 의 의미는 바꾸지 않았습니다 — V1→V2 마이그레이션이 같은 의미를 씁니다.

**`canvasViewDidEndUsingTool` 은 최종 저장 지점으로 쓸 수 없습니다.** PencilKit 이 획을 `drawing` 에 반영하기 **전에** 호출돼 빈 drawing 이 저장됩니다 (시뮬레이터 확인). 단일 Canvas 의 `editEnded` 도 trailing debounce 로 냅니다 (§8-1).

| N-Canvas (`7ba5bc46`) | 단일 Canvas 대체 |
|---|---|
| trailing debounce 로 마지막 변경 보장 | §8-1 편집 종료 계약 (`editEnded`) |
| 저장 가드 제거 + stroke 0개도 저장 | §8-2 dirty 집합 → `.clear` mutation (P7) |
| `strokes.isEmpty` 로 신규 행 억제 | §8-7 `activeRowIDs` + rowID 선발급 |

---

## 8. 저장

### 8-1. 편집 계약 (begin / end)

구현: [ChapterCanvasController.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/ChapterCanvas/ChapterCanvasController.swift) → `ChapterCanvasView.Coordinator` → `ChapterCanvasFeature`.

```
canvasViewDidBeginUsingTool  → editBegan            → isEditing = true (레이아웃 · columnOrigin · 복원 재합성 보류)
canvasViewDrawingDidChange   → trailing debounce 0.3 s → editEnded(CanvasEditSnapshot(generation))
변경 없이 도구 종료 (탭)       → 0.35 s 뒤 editCancelled
editEnded / editCancelled    → isEditing = false, 보류된 변경을 한 번에 적용
```

- **다음 획이 시작되면 직전 획의 trailing 보고를 취소**하고, 미보고 변경은 도구 종료 뒤에 합쳐 보고합니다. 획 도중 `editEnded` 가 나가면 `isEditing` 이 풀려 보류 레이아웃이 획 중간에 적용됩니다.
- **세대.** 스냅샷은 편집 당시의 `renderedRevision` 을 `generation` 으로 싣습니다. Feature 는 합성·장 진입마다 직전 문맥을 `EditSession` 으로 물려 두고(`retiredSession`), 편집을 **자기 세대의 문맥**(현재 또는 물러난 세션)으로 계산합니다. 어느 세대도 아니면 로그와 함께 버립니다. 컨트롤러는 내용을 교체하기 직전에 미보고 편집을 **이전 세대 번호로 먼저 보고**합니다 — 장 전환 직전의 마지막 획까지 이전 장으로 저장됩니다.
- before ownership 은 `baselineData`(코덱이 마지막으로 처리한 내용)와 `ownership` 이며, 큐는 pencil-up 순서로 **한 번에 하나**만 코덱에 보냅니다 — 다음 편집의 before 는 이 편집의 결과입니다.

### 8-2. mutation 계산 (P7)

`DrawingCodec.mutations(beforeData:beforeOwnership:afterData:context:)`:

```
content → layout (−columnOrigin)
  → reconcile (§7-3) → 앵커 밖 클램프 (§7-1 U8)
  → dirty = (before ∪ after 절) 중 ContentSignature 집합이 달라진 절 (§7-2)
  → 절별 완전한 획 집합을 storageOrigin(첫 밑줄) 원점으로 localize
  → 활성 행 있음: 가시 획 있으면 replace / 없으면 clear · 활성 행 없음 + 가시 획: create (rowID 선발급 → issuedRowIDs)
```

**저장 변환은 평행이동뿐입니다.** clipping 이 없으므로 저장→복원→저장이 구조적으로 동일합니다. `.create` 의 rowID 는 코덱이 발급해 `DrawingEditResult.issuedRowIDs` 로 돌려주고 Feature 가 `activeRowIDs` 에 **즉시 예약**합니다.

### 8-3. 직렬화와 coalescing (P11, D9)

**핵심 성질:** `replace` 는 해당 절의 **완전한** 획 집합입니다(delta 가 아님). 같은 행에 대한 나중 mutation 이 이전 것을 완전히 대체합니다.

`pendingMutations: [BibleDrawingRowID: PendingDrawingMutation(revision, chapter, mutation)]` — **rowID 키**, last-wins. verse 키가 아닌 이유: 히스토리 복원으로 활성 행이 바뀌면 이전 행의 미저장 mutation 이 덮여 유실됩니다.

| 기존 | 새 명령 | 결과 | 이유 |
|---|---|---|---|
| `create` | `replace` | `create` | 행이 아직 없을 수 있다 (`create` 는 upsert) |
| `clear` | `replace` | `create` | 그 `clear` 가 미저장 `create` 를 덮은 것일 수 있다 — `replace` 로 남기면 `rowNotFound` 로 batch 전체가 영구 실패 (rev.17) |
| 그 밖 | — | 새 명령 | |

```
1. 저장은 동시에 하나만 (saving 이면 큐에 쌓기만). 한 batch 는 한 장이며 이전 장의 미저장분부터 보낸다
2. batch 의 rowID → revision 을 inFlightBatch 로 캡처
3. 저장 중 도착한 새 mutation 은 pendingMutations 에 계속 기록 (revision 갱신)
4. 성공: pending[rowID].revision == batch[rowID].revision 인 항목만 제거 → 더 최신이면 다음 batch
5. 실패: 항목 전부 유지 + saveStatus = .failed → 다음 편집 / flush / 장 전환에서 재시도
```

```swift
var isFullyPersisted: Bool { pendingMutations.isEmpty && saveStatus == .idle && editQueue.isEmpty && !isPreparingEdit }
```

### 8-4. 실패 정책 — 화면은 되돌리지 않음

Canvas 에는 이미 획이 표시됐으므로 저장 실패로 화면을 과거로 되돌리지 않습니다. 편집 결과는 즉시 확정하고, 실패하면 큐를 보존한 채 재시도합니다. undo stack 은 저장 실패의 영향을 받지 않습니다 (§9-5).

**재합성 게이트의 출구 (rev.17).** 레이아웃·`columnOrigin` 변경과 히스토리 복원은 미저장분을 먼저 저장한 뒤 DB 에서 다시 합성합니다(`reloadAfterSettling`). 그 사이 저장이나 재조회가 실패하면 입력을 영원히 잠그는 대신 **`DB 내용 ⊕ 미저장분` 으로 지금 합성**해 입력을 다시 엽니다. 저장 실패의 경우 `reloadWhenSettled` 를 유지해 다음 저장 성공 뒤에 재조회합니다. 코덱이 편집을 계산하는 중이면 그 결과가 세대를 잃지 않도록 큐가 빌 때까지 미룹니다.

### 8-5. flush — 미저장 잉크 소실 방지

pencil-up 마다 직렬 저장하는 기본 경로가 안전성의 본체이고, flush 는 보조 수단입니다. flush 지점:

| 지점 | 구현 |
|---|---|
| 장 진입 (`load`) | 이전 장의 실패 batch 를 곧바로 재시도. 큐·코덱·trailing 에 남은 이전 장 편집은 물러난 세션(§8-1)이 자기 장으로 저장 |
| 앱 비활성 (`appWillResignActive`) | 항상 트리에 있는 `CarveNavigationView` 의 scenePhase 훅에서 보낸다 — `CarveDetailView` 는 사이드바가 열리면 트리에서 빠진다. flag 와 무관하게 보낸다 (best-effort) |
| flag off 로 돌아온 장 (`setSentence`) | 단일 Canvas 에 남은 미저장분을 마저 저장 |

**미구현 — 요청/승인 흐름.** 설계 초안은 장 전환을 "flush 성공 후 전환, 실패 시 사용자 확인" 흐름으로 규정했습니다. 현재는 전환을 막지 않고 위의 물러난 세션과 장 진입 재시도로 대체합니다. 설정 화면으로의 이동은 `NavigationStack` push 라 Carve 상태(미저장분 포함)가 유지됩니다. 재시도 UI(`AnalyticsClient.trackErrorShown` + 사용자 알림)는 없습니다.

### 8-6. 원자적 batch (P8)

```swift
protocol DrawingRepository: Sendable {
    func load(chapter: BibleChapter) async throws -> [VerseDrawingSnapshot]
    func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter) async throws   // 전부 성공 또는 전부 실패
}
```

`SwiftDataDrawingRepository` 는 `SwiftDatabaseActor.applyDrawingMutations(_:chapter:now:)` **한 actor 메서드 = 한 트랜잭션**입니다 — 변경을 모아 마지막에 `save()` 1회, 하나라도 실패하면 `rollback()` 뒤 throw.

| 명령 | 의미 | 이유 |
|---|---|---|
| `create` | **upsert.** 행이 없으면 삽입(`rowUUID` = 선발급 rowID · `drawingVersion 3` · `isPresent true`), 있으면 `replace` 처럼 갱신 | 저장 실패·재시도로 두 번 도착해도 행은 하나 |
| `replace` | `lineData` · metadata 교체 · `drawingVersion 3` 승격 (§10-2 정책 5) · `updateDate` 갱신. **행이 없으면 `rowNotFound`** | 주소지정 버그를 조용히 새 행으로 바꾸지 않는다 |
| `clear` | 행 유지 · `lineData = nil` · `updateDate` 갱신. **행이 없으면 빈 행을 만든다** | 앞선 `create` 가 저장됐든 아니든 결과가 같아야 한다 |

> **한계 — 로컬 원자성 ≠ CloudKit 원자성.** 절 3개를 한 트랜잭션으로 커밋해도 CloudKit 에는 CKRecord 3개로 개별 동기화됩니다. 다른 기기가 일시적으로 찢어진 상태를 볼 수 있습니다. 장 단위 단일 레코드로 바꾸지 않는 한 해결할 수 없으므로 알려진 한계로 둡니다.

### 8-7. 히스토리와 행 주소지정 (U2: 기존 다중 행·히스토리 유지)

한 절은 여러 `BibleDrawing` 행(필사 회차)을 가질 수 있고 `isPresent` 로 대표를 표시합니다. 단일 Canvas 는 절마다 **대표 행 하나**만 합성합니다.

| 규정 | 내용 |
|---|---|
| 활성 행 | 합성 시 `representativesByVerse()` → `activeRowIDs[verse]`. 편집은 항상 그 행에만 `replace` / `clear` |
| `clear` 는 행을 삭제하지 않는다 ★ | 삭제하면 `mainDrawing()` 이 과거 회차를 승격해 지운 획이 되살아난다. 행 유지 + `lineData` 비움 + `updateDate` 갱신. 빈 행은 히스토리 목록에서만 숨긴다 |
| 신규 행의 rowID 는 저장 전에 발급 ★ | rowID 없이는 rowID 키 큐에 못 들어가 빈 절에 빠르게 두 번 그으면 행이 둘 생긴다. 코덱이 발급 → `activeRowIDs` 즉시 예약 → 후속 편집은 같은 행의 `create` 를 교체 → 저장소가 upsert |
| 새 회차 생성 | 현행 유지 — 해당 절에 행이 하나도 없을 때만. "새 필사 시작" 트리거는 별도 제품 기능 |
| 대표 행 결정 (`DrawingRepresentativeRule`) | ① `isPresent` 행 중 `updateDate` 최신 ② 동률이면 rowKey 사전순 ③ `isPresent` 없으면 `updateDate` 최신 → rowKey. 모델 `mainDrawing()` 도 같은 규칙 (CloudKit 충돌로 `isPresent` 가 복수일 수 있어 입력 순서 의존을 제거) |
| 행 식별자 | 신규 행은 UUID(`rowUUID`), legacy 행은 business `id` 를 키로 **쓰기 갱신 없이** 사용 (비파괴). lazy UUID 소급 발급은 철회 — 두 기기가 다른 UUID 를 부여할 수 있다 |
| `drawing.id` 표현 금지 ★ (S0-3) | `drawing.id` 는 문맥 의존 오버로드다 — 기대 타입이 없으면 `String!`, `PersistentIdentifier` 면 `persistentModelID`. 새 코드는 `persistentModelID` / `rowKey` 만 쓴다 |

#### 히스토리 복원 흐름

```
사용자가 회차 선택 (N-Canvas: 행별 시트 · B: 캔버스 롱프레스 → UIEditMenuInteraction → CarveDetailFeature.chapterHistory 시트)
  ↓ ② updatePresentDrawing — isPresent 이전 (VerseDrawingHistoryFeature)
  ↓ ③ verseRowRestored(verse:rowID:) → 미저장분 선저장(①) → DB 에서 다시 합성 → activeRowIDs 갱신 → undo stack clear (§9-5)
  ↓ ④ mutation 생성 없음 — DB 에 이미 존재하는 내용
```

①이 ②보다 뒤에 와도 안전합니다 — pending 은 rowID 로 주소지정되므로 이전 활성 행의 변경은 그 행으로 저장됩니다. B 의 절 판정은 `ChapterCanvasFeature.historyRequested(at:)` 이 합성 시점 레이아웃으로 `verse(containing:)` 하며, 텍스트 쪽(컬럼 왼쪽)을 눌러도 같은 행이 되도록 x 만 컬럼 안으로 당깁니다 (§20-11).

### 8-8. 전체 흐름

```
editBegan → isEditing
editEnded(snapshot(generation))
  ↓ 세대 확인 → editQueue → 코덱 한 번에 하나 (before = baselineData · ownership, 세션의 layout · columnOrigin · activeRowIDs)
  ↓ reconcile → 클램프 → dirty 절 → replace / clear / create (rowID 선발급 즉시 예약)
  ↓ pendingMutations[rowID] coalescing
  ↓ 저장 (동시에 하나, 한 장씩) → 단일 SwiftData 트랜잭션
성공 → 같은 revision 항목만 제거 · loadedDrawings 에 겹침 · 다음 batch / settle → 예약된 재합성
실패 → 화면 유지 + 큐 보존 + 재시도 (재합성 대기 중이면 DB ⊕ 미저장분 으로 합성해 입력 재개)
```

---

## 9. 복원과 reflow (G4)

### 9-1. 핵심 불변식

보존해야 할 것은 획의 절대 Y 가 아니라 `verse + underline index + 해당 underline 으로부터의 상대 offset` 입니다.

### 9-2. line band reflow

```
저장 stroke → 저장 당시 metadata 의 baseUnderlineAnchors 로 band(줄) 판정
           → 현재 layout 의 같은 index underline 으로 translate
           → 폭이 줄었을 때만 uniform 축소 (scale = min(1, now / base))
```

**왜 균등 세로 스케일이 아닌가** — 폰트를 키우면 같은 폭에서 줄 수가 늘어납니다. 세로로 늘리면 글씨가 밑줄과 어긋나고, 줄 단위로 재앵커하면 글씨 크기가 유지된 채 각 줄이 밑줄에 정렬됩니다.

reflow 는 `StrokeIdentityKey` 를 깨뜨리지 않습니다 — `PKDrawing.transformed(using:)` 이 `randomSeed` / `creationDate` / `path.count` 를 보존함을 실사용 fixture 5건으로 확인했습니다 (§20-3). reflow 후 첫 편집에서도 §7-3 1번 규칙이 성립합니다. 구현: [LineBandReflow.swift](../Feature/CarveFeature/Sources/Drawing/LineBandReflow.swift).

### 9-3. 정책 표

| 상황 | 처리 |
|---|---|
| 밑줄 수·줄 구성 동일 | 밑줄별 분류 후 새 y 로 translate |
| writing width 감소 | 종횡비 유지 uniform 축소 |
| writing width 증가 | **확대하지 않음.** 원래 크기 유지 |
| 줄 수 증가 | 남는 밑줄은 빈 줄 |
| 줄 수 감소 | 초과 band 는 마지막 간격 연장 + §6-3 effectiveHeight 로 공간 확보 (§9-3-1 4번) |
| 줄바꿈만 달라짐 | `textLineRanges` 겹침으로 이동 — **미구현.** 현재 줄의 문자 범위 실측(`Text.Layout.Run.characterIndices`, iOS 17.0+ — S2 확인)이 파이프라인에 없다. 자리(`Input.currentTextLineRanges`)만 있고 읽지 않는다. 임의 구현하면 §9-3-1 로 가야 할 절이 조용히 잘못된 줄에 앉는다 |
| 매핑할 줄 없음 | **첫 밑줄 기준으로 통째 보존** + `layoutMismatch` 기록 (§9-3-1) |
| metadata 없음 (legacy) | 무변환 (§10-2). 코덱이 현재 `writingRect` 원점에 배치 |

> `CharacterIndex` 의 단위(Character vs UTF-16)는 미확정입니다 — 검증에 쓴 한글 46자는 두 값이 같았습니다. 성경 본문에 이모지·결합 문자가 없어 리스크는 낮으나, `textLineRanges` 를 구현할 때 확인하십시오.

### 9-3-1. `layoutMismatch` — 매핑 실패 시의 확정 동작

```
1. 표시   절 Drawing 전체를 첫 밑줄 기준으로 보존해 배치 (임의로 다른 줄에 합치거나 분산시키지 않음)
2. 기록   State.layoutMismatchVerses 에만 — 표시 상태이지 저장 상태가 아님
3. 저장   사용자가 그 절을 실제로 편집하기 전까지 자동 저장하지 않음 (P10)
```

원본을 건드리지 않으므로 설정을 되돌리면 원래 배치로 복귀합니다. 구현하면서 확정한 명세 4건:

| # | 확정 |
|---|---|
| "매핑할 줄 없음" 의 조건 | ① 저장 band 0개 ② 현재 밑줄 0개 ③ 줄 수가 줄었는데 마지막 간격 ≤ 0. ③ 을 진행하면 초과 band 가 같은 y 에 겹쳐 쌓여 위 1번을 위반한다 |
| uniform 축소 적용 여부 | 적용한다 — 절 안의 상대 배치를 바꾸지 않고, 없으면 잉크가 좁아진 컬럼 밖으로 샌다 |
| legacy 무변환의 출력 좌표계 | `legacyPassthrough` — 좌표를 전혀 건드리지 않는다. 배치는 코덱의 런타임 legacy 판별(§10-2 3번)이 담당 |
| "마지막 간격" 이 밑줄 1개일 때 | `writingRect` 상단 ~ 첫 밑줄 거리를 한 줄 높이로 본다 (새 상수 없음). 0 이하면 ③ |

### 9-3-2. 밑줄 offset 정밀화 (미적용)

`Text.Layout.Line.typographicBounds` 가 `ascent` / `descent` 를 제공하므로 `VerseTextFeature.makeUnderlineOffsets` 의 `UIFont.descender` 근사를 실측값으로 바꿀 수 있습니다. 밑줄 위치는 `baseUnderlineAnchors` 로 영속화돼 근사 오차가 저장 데이터에 굳습니다. 후속 과제입니다.

### 9-4. 비파괴 원칙 (P10)

reflow 는 **표시 시점에만** 적용하고 저장하지 않습니다. 사용자가 그 절에 실제로 획을 추가/삭제할 때만 새 레이아웃 기준으로 저장합니다. 설정 화면에서 폰트를 이리저리 바꿔보는 것만으로는 원본이 훼손되지 않습니다. `ReflowedVerseDrawing` 이 `Data` 를 노출하지 않는 것으로 타입 수준에서 강제합니다.

### 9-5. undo 정책

| 상황 | undo stack |
|---|---|
| 같은 레이아웃 안의 필기·지우기 | native undo 대상 |
| 장 변경 · reflow 적용 · 히스토리 복원 | **clear** (programmatic 교체라 기준이 어긋남) — 컨트롤러가 `renderedRevision` 변화마다 비운다 |
| 저장 실패 | 변경 없음 |

---

## 10. 스키마 V4와 레거시

### 10-1. V4 — additive only

```swift
@Model final class BibleDrawing {           // DrawingSchemaV4 — 기존 필드 전부 유지
    /// 좌표 형식의 단일 진실 (V2 부터 있던 필드에 의미만 확정)
    ///   nil / 1 = legacy (형식 미확정)   2 = verse local + top-left (N-Canvas)   3 = verse local + 첫 밑줄 원점 + metadata
    var drawingVersion: Int?
    @Attribute(.externalStorage) var layoutMetadataData: Data?   // DrawingLayoutMetadata blob, drawingVersion == 3 일 때
    var rowUUID: String?                     // 신규 행에만 발급. legacy 는 nil (비파괴)
}

struct DrawingLayoutMetadata: Codable {     // Domain, 순수 DTO
    let metadataSchemaVersion: Int           // blob 자체의 버전. 좌표 형식은 drawingVersion 한 곳에만
    let baseWritingWidth: CGFloat; let baseWritingHeight: CGFloat
    let baseUnderlineAnchors: [CGFloat]      // 첫 밑줄 기준 상대 y (첫 값 0). VerseCanvasRegion.underlineAnchors(writingRect 상단 기준)와 기준이 다르다 — 변환은 UnderlineAnchorBasis 로만
    let textLineRanges: [Range<Int>]?
    let layoutSignature: String
}
```

새 필드는 전부 optional (CloudKit 요구), lightweight migration 한 단계. `drawingVersion` 을 읽거나 쓰는 코드, 좌표를 만지는 코드는 마이그레이션에 없습니다 (§20-5).

#### 10-1-a. ⚠️ CloudKit 스키마 승격 함정 — 단일 Canvas 배포 전 필수 (D7 실측)

CloudKit **Development** 환경은 필드를 **실제 값이 처음 저장될 때** 서버 스키마에 만들고, **Production** 은 Dashboard 에서 명시적으로 배포(promote)해야 생깁니다. D7 시점 dev 컨테이너에는 `CD_rowUUID`(신규 행에 값이 있어서)와 `CD_lineDataBytes` 는 있고 **`CD_layoutMetadataData` 는 없었습니다** — 아무도 쓰지 않았기 때문입니다.

> **배포 전 절차:** ① dev 에서 `layoutMetadataData` 에 값을 한 번이라도 저장해 서버 스키마에 필드를 만든다 ② Dashboard 에서 Development → Production 배포 ③ 그다음 단일 Canvas 를 기본 활성화한다. 메커니즘이 아니라 **순서**의 문제입니다.

### 10-2. 레거시 판별은 migration에서 할 수 없다 ★

`normalizedForVerseRect` 는 현재 verse rect 가 있어야 동작하는데 migration 시점에는 레이아웃이 없습니다. **런타임 lazy 정책:**

1. V3 → V4 는 optional 필드 추가만. 데이터 변환 금지
2. 기존 record 는 `drawingVersion == nil || == 1` → legacy
3. `ChapterLayout` 이 완성된 런타임 이후에 판별 (코덱 `compose`)
4. 판별 결과로 **표시만** 함. 원본 자동 덮어쓰기 금지
5. 해당 절을 **처음 편집할 때만** `drawingVersion = 3` + metadata 로 저장
6. 확실하지 않은 절은 복구 로그 / 사용자 확인 대상 (`legacyVerses`)
7. bounds 를 저장 당시 폭으로 추정해 확대하지 않음

metadata 없는 행은 마이그레이션 이후에도 다른 기기에서 계속 도착할 수 있으므로 판별은 "legacy 행을 만날 때마다" 의 런타임 경로입니다. **1.2.0 은 22일간 배포됐습니다** (2025-12-08 → 12-30 롤백) — 그 기간의 행은 절대좌표입니다.

#### 10-2-1. `normalizedForVerseRect` 휴리스틱은 실데이터의 71%에서 실패합니다

실사용 blob 225건에 판정식(첫 획 `renderBounds` 가 `rect.origin` 에서 두 축 모두 20pt 이내면 절대좌표)을 적용한 결과 발동 66 (29%) / 미발동 159 (71%) 였습니다 ([LegacyCoordinateTesting.swift](../Feature/CarveFeature/Tests/LegacyCoordinateTesting.swift)). 절대좌표인데 탐지 안 됨(필사가 장 아래로, 로그 없음)과 로컬인데 절대로 오인(장 상단 절이 밀림)이 **반대 방향**이라 `tolerance` 로 동시에 해소되지 않습니다. → P3 는 선택이 아니라 필수이며, 정책 6번이 다수 경로일 것을 전제해야 합니다.

### 10-3. 롤백의 의미 — forward-only ★

V4 로 마이그레이션된 store 는 V3 빌드로 되돌릴 수 없습니다. Phase 3 을 되돌리는 수단은 **feature flag off** 뿐이며 그때도 저장소는 V4 입니다. → **V4 저장소를 유지한 채 flag 를 껐을 때 N-Canvas 경로가 정상 동작해야 합니다** (§14 16).

flag off 경로가 단일 Canvas 의 행을 읽는 규칙 (rev.17):

| 행 | N-Canvas 표시 | N-Canvas 편집 |
|---|---|---|
| legacy (nil/1) · v2 | 무변환 | 형식 표식 불변 |
| **v3** (첫 밑줄 원점) | `CanvasFeature.State.firstUnderlineY`(실측 첫 밑줄)만큼 내려 표시 (`displayTransform`) | 자기 형식인 **v2** 로 내리고 metadata 를 지운다. `DrawingDatabase.updateDrawing` 이 `drawingVersion` · `layoutMetadataData` 를 함께 옮긴다. 단일 Canvas 가 다음 편집 때 다시 v3 로 올린다 |

설정 > 필사 캔버스 토글(`CanvasSettingsFeature`)이 `SingleCanvasFlag.appStorageKey` 에 쓰고, `CarveDetailView` 는 `usesSingleCanvas` 변화에 현재 장을 다시 불러옵니다. Debug 실행 인자 `-SingleCanvas` 는 같은 효과입니다.

### 10-4. BiblePageDrawing

기준 데이터가 아니라 캐시/복구 전용으로 격하합니다. 장 전체가 레코드 1개라 CloudKit 에서 last-writer-wins 로 통째 덮어씁니다. D8 실측상 실데이터 0행이므로 제거해도 마이그레이션 부담이 없습니다 — Phase 4 후보.

---

## 11. UI 호스팅 — spike로 확정 (P5)

`PKCanvasView` 는 `UIScrollView` 서브클래스입니다.

```
A. SwiftUI ScrollView + content-sized PKCanvasView overlay      ← 기존 시도. 정규화로 풀리지 않음 (D1)
B. PKCanvasView 가 유일한 UIScrollView, 텍스트는 그 scroll content 안의 UIHostingController   ← ★ 확정 (U4)
```

> **금지:** PKCanvasView 와 별개인 SwiftUI 텍스트에 `contentOffset` 만 전달하는 방식. 프레임별 동기화·bounce·safe-area·zoom 에서 drift 가 재발합니다. 텍스트는 반드시 **canvas 의 scroll content 내부**에 있어야 합니다.

### 실험 범위

Debug 전용 하네스 `CanvasScrollSpike`(§20-4) — A/B 런타임 전환, 동일한 176절 mock layout, SwiftData 와 연결하지 않음.

### 통과 기준

| # | 기준 | S4 (시뮬레이터) | D (실기기) |
|---|---|---|---|
| 1 | 스크롤 전후 동일 content point 의 stroke 오차 ≤ 1pt | ✅ A·B 0.000pt | — |
| 2 | 빠른 fling/rebound 후 오차 없음 | △ bounce 프로그램 왕복 PASS. **관성 fling 미수행** | — 미수행 |
| 3 | Split View resize 후 재필기 위치 | ✅ 폭축소 토글 재계산 후 0.000pt | D6: 회전·리사이즈 시 표시만 어긋나고 되돌리면 복구 |
| 4 | 왼손잡이 전환 후 정합 | ✅ 0.000pt | — |
| 5 | 헤더 애니메이션 / 롱프레스 / 탭 | △ 헤더 애니메이션 중 스크롤 PASS. **탭/롱프레스는 구조만 확인** | — 미수행 (D9 에 포함) |
| 6 | 재진입·장 변경 후 offset 복원 | ✅ Δ0.00 | — |
| 7 | live stroke 가 pencil-up 에 확대·이동하지 않음 | 측정 불가 | **A ❌ / A+정규화 ❌ / B ✅** |
| 8 | hover 중 좌표 변화 없음 | 측정 불가 | **A ❌ / A+정규화 ❌ / B ✅** (HUD peak 0.000) |
| 9 | `.pencilOnly` 한 손가락 스크롤 | 측정 불가 | ✅ A·B |
| 10 | `allowFingerDrawing` 일 때 스크롤 방법 | 측정 불가 | ✅ B — 한 손가락 그리기 / 두 손가락 스크롤. 발견 가능성은 제품 과제 |
| 11 | 시편 119편 layout 시간·peak memory | △ | D5 baseline (§18-3-a). layout 시간은 Phase 2 signpost 로 시뮬레이터만 |

**기준 1 의 "오차"** 는 화면 절대 위치가 아니라 "content point → viewport 매핑이 `contentOffset` 만큼의 평행이동인가" 입니다. 컨테이너 이동(헤더 접힘 등)을 오차로 잡으면 105pt 짜리 가짜 FAIL 이 납니다.

```
residual = (point 의 window 좌표) − viewportOriginInWindow + contentOffset      ← 스크롤해도 불변이어야 하는 값
```

### 판정 — B 확정 (U4)

**S4(시뮬레이터)는 A 와 B 를 구별하지 못했습니다** — 8개 시나리오 전부 A·B 모두 max 0.000pt 였고, A 는 정규화를 꺼도 통과했습니다 (프로그램 스크롤 경로에는 보정할 drift 가 없음). 깊은 offset 15000 에서 B 의 16184pt `UIHostingController` 도 정상 렌더됐습니다.

**실기기 D1 이 갈랐습니다.** 같은 하네스를 실기기에서 Apple Pencil 로 관측:

| 기준 | A | A + 정규화 | B |
|---|---|---|---|
| 7 live stroke | ❌ 그리는 동안 다른 위치에 렌더되고 펜을 떼면 정상 위치로 **점프** | ❌ 동일 | ✅ |
| 8 hover | ❌ 크게 어긋남 | ❌ 동일 | ✅ peak 0.000 |

결정적 관찰 셋: 시스템 펜슬 그림자는 정상 위치인데 PencilKit 잉크 점만 어긋남(입력이 아니라 캔버스의 스크롤 상태 인식) · 어긋남이 스크롤 깊이에 비례(오차 = 바깥 `ScrollView` 의 `contentOffset`) · 정규화를 켜도 동일(보정 불가). 상세는 §2.

한계: iOS 27 beta · 1회 정성 관측 · iPad mini 한 대. 기준 2 의 fling 과 5 의 탭/롱프레스는 D9 로 이월.

### Phase 3 구현 — B 구조 호스팅

[ChapterCanvasController.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/ChapterCanvas/ChapterCanvasController.swift) · [ChapterCanvasView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/ChapterCanvas/ChapterCanvasView.swift)

| 항목 | 구현 |
|---|---|
| 스크롤 뷰 | `ChapterPKCanvasView: PKCanvasView` 하나 — 이 화면의 유일한 `UIScrollView`. 텍스트 컬럼(`UIHostingController`)은 scroll content 안, **잉크 아래** (`layoutSubviews` 에서 `sendSubviewToBack`). 스크롤 동기화 코드 없음 |
| 텍스트 컬럼 | N-Canvas 와 **같은 행 뷰** (`SentencesWithDrawingView`, `isCanvasActive: false`). 호스트는 `isUserInteractionEnabled = false`. frame 높이 = 컬럼 자신의 높이 (content 높이로 늘리면 짧은 장에서 세로 중앙 배치됨), 루트에 `.frame(maxHeight: .infinity, alignment: .top)` |
| 인셋 | `.never` + `contentInset(top: 헤더, bottom: safeArea + 24)`. 헤더 높이는 첫 apply 뒤에 실측돼 오므로, 인셋이 바뀔 때 맨 위에 있던 스크롤만 새 인셋으로 다시 고정 |
| 편집 계약 | §8-1 — trailing debounce · 다음 획 시작이 직전 보고 취소 · 세대 번호 · 교체 직전 flush |
| 표시 | `renderedRevision` 이 바뀔 때만 디코드해 `drawing` 에 넣고 undo 스택을 비움 |
| 게이트 | `drawingGestureRecognizer.isEnabled = isComposed && !isReloading` |
| undo/redo | 캔버스 자신의 `undoManager`. 팔레트와 `@Shared(.inMemory("canUndo"/"canRedo"))` 공유 — 단일 Canvas 에서는 팔레트가 `delegatesUndoToCanvas` 로 `SharedUndoManager` 를 건드리지 않는다 |
| 스크롤 요청 | `ScrollRequest(token)` — 절 하단이 보이는 하단(`offset + bounds − inset.bottom`) 근처에 오도록. top inset 은 관여하지 않는다 |
| 히스토리 메뉴 | 손가락 롱프레스(`allowedTouchTypes = [.direct]`) → `UIEditMenuInteraction` "이전 필사 내용 보기" → `historyRequested(at: content 좌표)` (§8-7) |
| 헤더 애니메이션 | `scrollViewDidScroll` 이 SwiftUI `offsetY` 와 같은 의미의 (이전, 현재)를 올려 기존 `headerAnimation` 재사용 |

**S4 와 다른 점** — S4 는 컬럼 폭을 명시적으로 넘겼고, 제품 코드는 Phase 2 의 `GeometryReader` 경로를 그대로 쓰며 컬럼 높이는 `onGeometryChange` 로 잽니다.

#### ⛔ D9 결함 — 텍스트 컬럼은 **절대 세로로 늘어나면 안 됩니다** (R16)

**컬럼 상단이 레이아웃 좌표계의 원점이고 컬럼 높이가 곧 좌표 스케일입니다.** 컬럼이 늘어나면 잉크 좌표계 자체가 깨집니다.

실기기에서 **긴 장 → 짧은 장** 전환(창세기 1장 31절 → 2장 25절)만으로 마지막 절이 **1335.78pt** 어긋났고 자가 복구되지 않았습니다. 고리는 이렇습니다:

```
columnHeight 가 장 전환에 초기화되지 않음 (컨트롤러는 장을 넘어 생존)
   → 짧은 장의 호스트 frame 이 이전 장의 큰 높이를 가짐
   → 컬럼 루트가 maxHeight: .infinity 라 초과 높이가 컬럼에 제안됨
   → 행의 underLineView(maxHeight: .infinity)가 흡수해 행이 실제로 늘어남
   → 늘어난 컬럼을 다시 재도 높이가 같아 setColumnHeight 가드에 걸림  ★ 안정 고정점
```

**N-Canvas 는 무사합니다** — `ScrollView` 가 무한 높이를 제안해 초과분 자체가 없습니다. 즉 이것은 **B 구조 호스팅 고유의 함정**입니다.

`updateContentGeometry` 의 주석이 인접한 함정(“content 높이로 늘리면 세로 중앙 배치”)을 이미 알고 있었지만, 중앙 배치를 `alignment: .top` 으로 막았을 뿐 **초과 높이 자체는 남아 있었습니다.** 규칙을 다음과 같이 못박습니다.

> **컬럼은 항상 자기 이상적 높이를 갖는다.** 호스트 frame 이 더 커도 컬럼이 그 높이를 먹지 않는다.
> 호스트 frame 계산에 쓰는 컬럼 높이는 **현재 장의 것**이어야 한다.

**수정 (rev.20).** `ChapterCanvasView.hostedColumn(_:reportHeight:)` 로 호스트 컬럼 조합을 모으고, `column` 에 **`.fixedSize(horizontal: false, vertical: true)` 를 `.onGeometryChange` 보다 안쪽에** 걸었습니다. 컬럼이 어떤 제안을 받아도 자기 이상적 높이를 보고하므로 되먹임 고리가 구조적으로 사라집니다. 바깥 `.frame(maxHeight: .infinity, alignment: .top)` 은 유지 — 호스트가 더 커도 상단에 붙어야 합니다.

`columnHeight` 리셋은 **넣지 않았습니다.** 쓸 수 있는 신호(`Configuration.layout?.chapter`)가 원리적으로 늦기 때문입니다 — 장 전환 리듀서가 `layout` 을 nil 로 지우고 새 값은 실측 완료 뒤에 오므로, 리셋이 필요한 창이 정확히 `layout == nil` 구간입니다. nil 을 "장 바뀜" 으로 취급하면 정상 구간에서 리셋이 튀는 새 실패 모드가 생깁니다. `fixedSize` 가 있으면 낡은 `columnHeight` 도 다음 측정에서 곧바로 수렴합니다.

**행 뷰는 건드리지 않았습니다** — `underLineView` 의 `maxHeight: .infinity` 는 N-Canvas 와 공유라 그대로입니다.

절차·기록은 [런북 §8-7 R16](./phase-0a-d-device-test.md).

---

## 12. 결정사항

| ID | 결정 | 근거 |
|---|---|---|
| U1 | cross-verse 획은 **시작 절에 통째 귀속** | §7-1 · rev.19 §7-3 |
| U2 | **다중 행·히스토리 유지** → mutation 을 행 주소지정으로 | §8-7 |
| U3 | 지우개는 **`.bitmap` 유지** | §7-4 |
| U4 | 스크롤 구조 **B** — `PKCanvasView` 가 유일한 `UIScrollView` | §11 · §2 |
| U5 | `columnOrigin` — 호스팅 출처 · Feature 보관 · **Codec 만 적용** | §5 |
| U6 | 하단 인셋 — `.never` 유지 + `contentInset`, 콘텐츠 좌표 불변 | §5 |
| U7 | signature 에 `chapter` 를 **넣지 않음** | §5 · §6-5 |
| U8 | 앵커가 캔버스 밖인 획 — **캔버스 안으로 클램프** | §7-1 |

### U2 결정의 파급

| 항목 | 규정 |
|---|---|
| 활성 행 추적 | `State.activeRowIDs` |
| `clear` | 행 삭제 금지, `lineData` 만 비움 |
| 히스토리 복원 | `isPresent` 이전 → `verseRowRestored` (mutation 미생성, 미저장분 선저장) → undo clear |
| coalescing 키 | verse 가 아닌 **rowID** |
| `mainDrawing()` | 결정적 (`DrawingRepresentativeRule`) |
| 새 회차 생성 | 행이 없을 때만. 자동 회차 증가 없음 — "새 필사 시작" 은 별도 제품 기능 |

---

## 13. 이행 계획

각 Phase 는 **forward-only** 로 독립 배포 가능합니다 (§10-3).

| 단계 | 상태 |
|---|---|
| Phase 0A-S0 (기준선) | ✅ §18 |
| Phase 0A-S1/S2/S3/S4 (시뮬레이터 검증) | ✅ §19 · §20-4 · §20-8 |
| Phase 0A-D D1~D8 (실기기) | ✅ B 확정 · baseline · legacy 추출 · CloudKit 일부 (§20-6 · §20-7). **D9 남음** |
| Phase 0B (순수 로직) | ✅ `f5206814` 레이아웃 · `0c071d29` 소유권/승계 · `565dfe69` reflow · `0e9a8449` fixture |
| Phase 1 (V4 additive schema) | ✅ `b68b6101`. 실기기 마이그레이션 성공. CloudKit 미러링 일부 미검증 (§20-5 · §20-7) |
| Phase 2 (`VStack` + 게이트 + 오버레이) | ✅ rev.15 (§20-8). 실기기 미측정 |
| Phase 3 (flag 뒤 단일 Canvas) | ✅ (3/3) rev.18 + 결함 수정 rev.17 + 승계 수정 rev.19. **flag 기본 off.** 기본 활성화·배포 판단은 **D9 뒤** |
| Phase 4 (구 구조 제거) | 실기기 검증 및 안정화 후 |

### Phase 2 산출물

| 항목 | 산출물 |
|---|---|
| `LazyVStack → VStack` | `CarveDetailView.contentView` — 텍스트 행 즉시, 캔버스는 뷰포트 근처에서 지연(sticky) |
| 전 절 실측 파이프라인 | `ChapterLayoutMeasurement` (측정 상태 · 게이트 · 예측 vs 실측 Δ · `columnOrigin`) · `VerseGeometryCollector` (한 틱 한 액션) · `ChapterLayoutHosting` (뷰와 빌더가 공유하는 배치 상수) |
| 빌더 입력 | `VerseLayoutInput.leadingInset` (장 중간 절의 소제목, `writingRect` 밖) · `topPadding` (1절 상단 여백 25, `writingRect` 안) |
| 게이트 · 오버레이 | `CanvasView(isInputEnabled:)` · `-ChapterLayoutOverlay` (writingRect 파랑 · captureRect 초록 점선 · anchors 주황 · 실측 frame 빨강 점선 · dirtyBounds 자홍 + HUD) |
| 계측 · 무인 시나리오 | `ChapterLayoutSignpost` (`ChapterLayout` / `measure`) · `-ChapterLayoutAutoScroll` · `-ChapterLayoutAutoNext` |

### Phase 3 산출물

| 조각 | 산출물 | 커밋 |
|---|---|---|
| (1/3) 저장 계층 | `DrawingRepository` + `SwiftDataDrawingRepository` · `VerseDrawingSnapshot` · `DrawingRepresentativeRule` · `DrawingLayoutMetadata+Blob` | `2cde2ad1` |
| (1/3) 코덱 | `DrawingCodec` (`compose` · `mutations`) · `DrawingCodecClient` | `2cde2ad1` |
| (1/3) 리듀서 | `ChapterCanvasFeature` — §6-4 게이트 · §8 편집 큐 · coalescing · 직렬 저장 · 실패 정책 · flush · 저장 후 재합성 | `2cde2ad1` |
| (2/3) B 호스팅 · flag 배선 | `ChapterCanvasController` · `ChapterCanvasView` · `CarveDetailFeature.usesSingleCanvas` · `singleCanvasBody` 분기 · 행 frame 2분할 실측 | `a1ac525f` |
| (2/3) 리뷰 결함 15건 | 편집 세대 · 물러난 세션 · 재합성 출구 · `coalesce` · 디코드 불가 행 · B 기하 4건 · v3 행의 N-Canvas 호환 · `scrollToTop` · 팔레트 undo 위임 (§20-10) | `24e9818e` |
| (3/3) 히스토리 메뉴 · 설정 토글 · `dirtyBounds` | `historyRequested(at:)` → `Delegate.showHistory` → `CarveDetailFeature.chapterHistory` 시트 → `verseRowRestored` · `CanvasSettingsFeature` · `SingleCanvasFlag` (§20-11) | `ea462922` |
| 승계 규칙 3 전제 | `StrokeOwnershipResolver.PartialIdentityIndex` (§7-3, §20-12) | `df15ba45` |

**하지 않은 것:** 실기기 D9 · `ChapterLayout` 캐시(구현하지 않기로 결정, §6-1) · `touchIgnoringContextMenu` 제거 · `activeCanvasIDs` 삭제 (N-Canvas 가 남는 동안 유지) · §8-5 요청/승인 흐름 · §9-3 `textLineRanges` · §9-3-2 밑줄 정밀화.

### Phase 4 — 안정화 후 구 구조 제거

- `CanvasFeature` / `CanvasView` · `CombinedCanvasFeature` / `CombinedCanvasView` (`StableCanvasView` 포함 — 접근 자체가 폐기, §2)
- `SharedUndoManager` — 단일 Canvas 는 `canvas.undoManager` 를 쓰므로 불필요. (D4 실측상 관측 가능한 오동작은 없었으므로 "깨져 있어서" 가 아니라 "불필요해서" 지웁니다)
- `clippedPrecisely` / `normalizedForVerseRect` · `VerseRowFeature`(죽은 리듀서)
- `touchIgnoringContextMenu` 의 행별 중첩 `UIHostingController` · `CarveDetailView.activeCanvasIDs`
- `DrawingDatabase.updateDrawings(requests:)` · `updateDrawing(drawing:)` — Repository 로 흡수

---

## 14. 테스트

### 필수 항목

**소유권·저장**
1. 경계 획이 잘리지 않고 **시작 절에 온전히** 저장되는지
2. 지우개로 절을 완전히 비우면 `clear` mutation 이 발생하는지
3. 두 절 dirty 저장 중 하나가 실패하면 **모두 롤백**되는지
4. 동일 fingerprint 후보가 여러 개일 때 owner 가 결정적으로 선택되는지
5. 복수 행이 있는 절에서 `clear` 후 과거 회차가 자동 승격되지 않는지

**히스토리 (U2)** — 5-1 편집이 `activeRowIDs[verse]` 행에만 · 5-2 복원이 mutation 을 만들지 않음 · 5-3 미저장 pending 이 있어도 복원 시 유실 없음 · 5-4 `isPresent` 복수일 때 결정적 · 5-5 빈 행은 목록에서만 숨김

**signature / 행 생성** — 5-6 mask 만 달라진 stroke 가 owner 유지 + dirty · 5-7 신규 절 연속 편집이 `create` 하나로 coalescing

**순서·복구** — 6 edit 1 저장 지연 중 edit 2 가 먼저 끝나도 최종 DB 가 edit 2 · 6-1 저장 중 도착한 최신 mutation 을 성공 콜백이 지우지 않음 · 6-2 조회/레이아웃 도착 순서 무관 · 6-3 이전 장 조회 결과 미적용 · 7 장 전환 직전 pending edit 유실 없음 · 8 저장 실패 후 다음 edit 성공 시 함께 반영

**레이아웃·복원** — 9 라운드트립 구조 보존 · 10 layout 미완성 시 입력·저장 금지 · 11 layout 변경 중 필기는 pencil-up 뒤 reflow · 12 줄 수 감소 시 높이 증가 · 13 legacy 무변환 · 14 reflow 후 undo 초기화 · 15 signature 영속

**롤백** — 16 V4 저장소 + flag off 에서 N-Canvas 정상 · 17 undo/redo 후 재실행 유지

### 테스트 파일 ↔ 항목

| 파일 | 건수 | 고정하는 것 |
|---|---:|---|
| `ChapterLayoutBuilderTesting` · `ChapterLayoutBuilderInsetTesting` · `ChapterLayoutPointQueryTesting` (Domain) | 20+ | 2-pass (12) · signature canonical (15) · `leadingInset` / `topPadding` · `verse(containing:)` |
| `DrawingLayoutMetadataTesting` · `DrawingSchemaV4MigrationTesting` · `DrawingDatabaseTesting` (Domain) | 30+ | metadata 라운드트립 · V3→V4 마이그레이션 11건 · §10-3 등가 9건 |
| `DrawingRepositoryTesting` (Domain, 13) | 13 | `create` upsert · legacy 주소지정과 승격 · `clear` 행 유지 (5) · 롤백 (3) · `rowNotFound` · 대표 행 규칙 (5-4) |
| `StrokeOwnershipResolverTesting` (§7-1 · §7-3) | 20 | 첫 control point · U1 · 지우개 조각 승계 · 규칙 3 결정성 · **새 획은 겹쳐도 시작 절 (rev.19)** · 4 부분 |
| `LineBandReflowTesting` · `LegacyCoordinateTesting` · `PencilKitDataModelTesting` · `TextLayoutKeyProbeTesting` | 30+ | §9-2 · §9-3-1 · legacy fixture · S1 · S2 |
| `ChapterLayoutMeasurementTesting` · `CarveDetailLayoutMeasurementTesting` | 21 | 게이트 · 도착 순서 무관 (6-2) · 이전 장 폐기 (6-3) · 수집기 |
| `DrawingCodecTesting` | 11 | legacy 무변환 (13) · v3 reflow · 라운드트립 무 mutation (9) · 경계 획 `create` (1) · `clear` (2) · mask dirty (5-6) · 클램프 (U8) |
| `ChapterCanvasFeatureTesting` (18) · `ChapterCanvasHistoryTesting` (2) | 20 | 6-2 · 10 · 6-3 · 5-7 · 6-1 · 8 · 11 · 5-2 · 5-3 · 7 · 세대 · 물러난 세션 · 재합성 출구 · `coalesce` · 히스토리 절 판정 |
| `ChapterCanvasControllerTesting` | 7 | trailing 취소·합침 · `editCancelled` · 교체 직전 flush · 호스트 frame · 늦은 헤더 높이 · `scrollOffset` |
| `SingleCanvasRollbackTesting` (7) · `CarveDetailHistoryWiringTesting` (2) · `CanvasSettingsFeatureTesting` (1) | 10 | v3 행 표시·v2 강등·DB 반영 (16 의 일부) · 디코드 불가 행 비파괴 · 팔레트 undo 위임 · 히스토리 시트 배선 · 토글 |
| `DrawingErasePersistenceTesting` | 6 | `7ba5bc46` 회귀 (§7-5) |

> **테스트로 고정되지 않은 필수 항목:** 14 (reflow 후 undo 초기화 — UI) · 16 (flag off 경로는 실행으로 확인) · 17 (펜 입력 필요 — D9).
>
> **TestStore 주의:** TCA 1.20.2 + Xcode 26.3 에서 `receive` 가 기대 액션을 못 받으면 issue 기록 경로에서 xctest 가 `EXC_BAD_ACCESS` 로 죽고 나머지가 재시작된 프로세스에서 돕니다. 크래시는 증상이고 원인은 그 위의 ✘ 단언입니다. 비exhaustive 스토어는 다음 `send` 전에 미수신 액션을 자동 소비하므로 "나중에 도착하는 결과" 는 `RepositorySpy.holdNextLoadCall / holdNextApply` 게이트로 순서를 강제합니다. `DrawingDatabase.testValue` 는 프로세스에서 한 번 만들어진 actor 를 쓰므로, 저장 결과를 다른 context 로 검증하려면 **그 actor 의 `modelContainer`** 로 검증 actor 를 만듭니다.

### D9 결함 대응 테스트안 (rev.20)

두 결함 모두 **기존 테스트가 놓칠 수밖에 없는 자리**에 있었습니다. 무엇을 못 잡았는지부터 정리합니다.

| 결함 | 왜 안 잡혔나 | 고정할 방법 |
|---|---|---|
| **R13** 행 높이 예측 ✅ (rev.21 완료) | `ChapterLayoutBuilderTesting` 은 빌더를 **합성 입력**으로만 검증합니다. "빌더의 모델 = SwiftUI 의 실제 렌더" 는 **뷰 계층과의 통합 성질**이라 순수 단위 테스트로 잡을 수 없습니다 | ① `VerseLayoutInput` 에 실측 높이를 additive 로 넣고, **fallback 예측과 실측이 다를 때 실측이 이긴다**를 빌더 테스트로 고정 ② 실측이 없을 때 기존 식으로 떨어지는 것도 고정 ③ `captureRect` 경계가 새 높이로도 빈틈·겹침 없이 분할되는지 (기존 불변식 재확인) |
| **R16** 컬럼 신장 | `ChapterCanvasControllerTesting` 의 "호스트 frame" 테스트는 **한 장 안에서만** 봅니다. 장 전환 **시퀀스**가 없었습니다 | ④ **긴 장 → 짧은 장 시퀀스**에서 `contentFrame.height` 가 이전 장 높이를 물려받지 않는다 ⑤ 호스트가 컬럼보다 커도 컬럼이 그 높이를 먹지 않는다 ⑥ 뷰포트보다 짧은 장에서 세로 중앙 배치가 일어나지 않는다 (기존 주석이 경계하는 함정) |

#### 일반화 — 컨트롤러의 **이월 상태**를 감사해야 합니다

`columnHeight` 는 한 사례일 뿐입니다. `ChapterCanvasController` 는 장 전환에도 **살아남고**, "밖에서 들어온 값을 캐시하고 `!=` 가드로 중복 적용을 막는" 프로퍼티가 여럿 있습니다. 그 패턴은 전부 같은 방식으로 낡을 수 있습니다.

| 프로퍼티 | 장 전환 시 검토할 것 |
|---|---|
| **`columnHeight`** | ★ R16 본체 |
| `appliedScrollToken` | 새 장의 첫 `scrollToTop` 토큰이 같은 값이면 **요청이 무시**될 수 있다 |
| `appliedUndoVersion` · `appliedRedoVersion` | 새 장에서 버전이 리셋되면 요청 1회가 누락되거나 중복될 수 있다 |
| `appliedRevision` | 세대 비교의 기준. Feature 쪽 리셋 규칙과 짝이 맞는지 |
| `isPerformingHistory` · `historyMenuPoint` | 전환 중 남으면 **다른 장의 절**에 적용될 수 있다 |
| `lastReportedTop` · `lastBounds` | 새 장의 첫 보고가 스킵될 수 있다 |
| `hasUnreportedChange` · `unreportedReason` | **의도적 이월** (§8-1 교체 직전 flush). 감사 대상이지만 바꾸면 안 된다 |

> **테스트 형태의 제안:** 개별 프로퍼티마다 테스트를 쓰기보다, **"장 A 를 적용 → 장 B 를 적용" 시퀀스를 한 번 태우고 B 의 관측 가능한 기하·요청이 A 와 무관함을 확인**하는 테스트를 하나 두는 편이 낫습니다. 새 이월 상태가 생겨도 같은 테스트가 잡습니다.

#### Δ 안전망 — `LayoutDeltaVerdict` (rev.21 구현) ★

`ChapterLayoutMeasurement.isReady` 는 절 개수만 확인하므로, **Δ 가 87.5pt 여도 `gate PASS` 이고 입력이 열립니다.** 그 상태의 필기는 잘못된 절에 귀속됩니다 (G3 위반). 아래 셋 중 **세 번째**를 채택해 구현했습니다.

| 선택지 | 평가 |
|---|---|
| 그대로 둔다 | 결함이 **조용히** 잘못된 데이터를 만든다 |
| Δ 를 합성 게이트(`isReady`)에 넣는다 | ❌ 오탐 하나로 **기존 잉크가 안 보이거나 미저장분이 유실**된다 (§15) |
| **Debug 에서 시끄럽게 알린다 + 한 줄 이상 어긋날 때만 새 입력을 막는다** | ✅ **채택** |

**계약**

| 조건 | 동작 |
|---|---|
| Δ > 1pt (`LayoutDeltaVerdict.tolerance`) | Debug 로그. 실측이 절마다 도착하므로 **의미 있는 변화**에만 남긴다 — 차단 여부 전환 · 허용치 신규 초과 · 최악 절 변경 · 허용치 이상 확대 |
| Δ > `lineSpace` (한 줄 — 귀속이 확실히 틀어지는 크기) | 그 위에 더해 **새 획 입력만** 차단 |

- 게이트는 `ChapterCanvasFeature.State.isDrawingInputEnabled` **하나**이고 `ChapterCanvasView.Display` 를 거쳐 `drawingGestureRecognizer.isEnabled` 로 간다. 합성·표시·저장·flush·복원은 `isComposed` / `isReloading` / `isFullyPersisted` 만 보므로 무엇이 어긋나든 계속 돈다. **`isReady` 는 건드리지 않는다.**
- **단일 Canvas 전용.** N-Canvas 는 잉크가 절-로컬이라 레이아웃 Δ 가 귀속을 틀지 않는다 — 거기서 막으면 무해한 조건으로 필기를 못 하게 만드는 회귀다. `CarveDetailFeature.forwardLayoutToSingleCanvas` 의 `usesSingleCanvas` 가드가 그 경계다.
- Pass 2 여유 높이(§6-3)가 붙은 절이 있으면 **판정을 보류한다** (`hasReflowSlack`). 그 여유는 `writingRect` 를 의도적으로 부풀린 값이라 "의도한 여유" 와 "예측 결함" 을 Δ 로 구별할 수 없고, 구별할 수 없을 때는 막지 않는다.
- **장 전환 시 리셋한다** — 이전 장의 Δ 로 새 장의 입력을 막지 않는다 (위 이월 상태 감사와 같은 계열).
- HUD 에 `guard OPEN / BLOCKED` 로 보인다.

이것은 **결함의 대체재가 아니라 안전망**입니다. R13 수정(실측 높이, §20-14)이 본체입니다.

#### 합성 결과는 **마지막 합성**의 것이다 (rev.22 — E-4 오독 지점) ★

`layoutMismatchVerses` · `legacyVerses` · `undecodableVerses` 는 `composeIfReady` 가 돌 때만 갱신됩니다.
**일반 편집은 재합성을 일으키지 않습니다** — 획 하나마다 재합성하면 살아 있는 캔버스를 갈아엎기 때문입니다.
따라서 legacy 행에 획을 그어 v3 로 승격시켜도(§10-3) 그 값은 **그 자리에서 줄지 않고**, 다음 재합성
(장 재진입 · 레이아웃 변경 · 재조회)까지 옛 값을 들고 있습니다. 진단에 쓸 때 이 시차를 전제해야 합니다.

D9 에서 이 시차를 결함으로 오독했습니다 (E-4). 경위는 런북 rev.7 · §8-7.

> ⚠️ **다만 그때의 "E-4 는 결함 아님" 판정은 되돌렸습니다** — "그 절이 v1 이라서" 는 band reflow 를 안 한다는 뜻이지
> 재배치가 아예 안 된다는 뜻이 아니고, 폰트 변경과 회전은 둘 다 컬럼을 통째로 다시 짓는 같은 자극이라 D9 H 와 구분되지 않습니다.
> **E-4 는 미확정이며 D9 H 잔여 검증(글꼴 변경)에서 재판정합니다** (§16 · 런북 §8-7).

#### 계측이 없으면 못 보는 구간 — 합성 프로브 (rev.22)

디버그 HUD 의 `sig` 는 `CarveDetailFeature` 의 **측정** 레이아웃이지 캔버스가 합성에 쓴 레이아웃이
아닙니다. 둘이 갈라지면 **본문만 재배치되고 잉크는 제자리에 남는데**, 그 상태를 화면으로 볼 수
없었습니다. `compose` 줄(`csig` · `rev` · `rl`/`rws`/`ed`/`pend` · `mism`/`leg`/`und` 절 번호)이
그 구간을 채웁니다 (`f17f49b5`). §20-8 의 Δ 오버레이 · §20-13 의 Δ 프로파일과 같은 계열의 투자입니다.

### 라운드트립 판정 기준

"비트 단위 동일" 은 너무 강합니다 (`dataRepresentation()` 이 canonical 이라는 보장이 없음). stroke 수 / control point 수 · 좌표와 bounds(허용 오차) · ink · transform · `randomSeed` 를 비교합니다. 프레임워크는 Swift Testing.

---

## 15. 주요 리스크

| 리스크 | 완화 |
|---|---|
| 장대한 획이 레이아웃 변경 시 시작 절과 통째로 이동 | 제품 정책으로 명문화 (U1) |
| `allowFingerDrawing == true` 에서 "두 손가락 스크롤" 을 사용자가 발견하지 못함 | 제품 과제 — 안내·온보딩·설정 문구 |
| fingerprint 가 영구 ID 가 아님 | 세션 내 승계 도구로만 사용, DB 의 절별 그룹이 진실 |
| 로컬 atomic batch ≠ CloudKit 원자성 | 알려진 한계 (§8-6) |
| V4 이후 버전 다운그레이드 불가 | flag off 경로 확보 + v3 행의 N-Canvas 호환 (§10-3) |
| 절별 실측을 절마다 액션으로 올리면 O(N²) | `VerseGeometryCollector` (§6-1) |
| 텍스트 행 176개 즉시 생성의 진입 비용 (+100 MB · +2.3 s, 시뮬레이터) — 실기기·저사양 값 없음 | D9 에서 D5 절차로 재측정 |
| 게이트가 열리지 않으면 장 전체가 필기 불가 | HUD `missing` 으로 관찰. 실기기 확인 필요 |
| `.named` 좌표 공간이 중첩 호스팅 안에서 조용히 `.global` 로 대체됨 | 행 frame 2분할 측정. Δ 검증은 출시 구성에서 (§6-1) |
| 단일 Canvas 의 편집·저장 경로가 시뮬레이터에서 실행되지 않음 | flag 기본 off. **D9 전에는 활성화하지 않음** |
| 손가락 롱프레스가 `allowFingerDrawing` 의 그리기 제스처와 겹침 (가만히 0.5 s 누르면 메뉴 + 점) | N-Canvas 의 행별 메뉴도 같은 조건. D9 에서 확인 |
| **빌더가 행 높이를 예측한다** (`lineCount × lineSpace`) — 실기기(iOS 27)에서 절당 0.5pt 어긋나 176절에서 87.5pt 누적 (R13) | ✅ **실측 높이를 레이아웃 입력으로 승격 (rev.21, §20-14).** 예측은 실측이 없는 절의 fallback 으로만 남으므로 OS 판올림에 재발하지 않는다. 안전망이 한 줄 초과 시 새 입력을 막는다 |
| **Δ 계측이 R16 계열(호스트 제안이 행을 늘리는 결함)을 더 이상 검출하지 못한다** — 레이아웃이 실측 높이를 따라가 예측 == 실측이 되기 때문 (rev.21 부작용, §20-14) | 자동 검출은 `hostedColumnKeepsIdealHeightAndStaysAtTop` 하나뿐. 실기기에서는 HUD 의 `H`(totalHeight)를 새 진입값과 비교한다 (런북 §6-9). **`fixedSize` 불변식과 한 쌍이다** |
| **B 구조에서 텍스트 컬럼이 세로로 늘어날 수 있다** — 장 전환 시 1335pt 어긋남 (R16, §11) | ✅ **`fixedSize` 로 고정 · 실기기 4건 통과 (rev.20).** 컬럼 높이가 좌표 스케일이므로 이 불변식은 앞으로도 지켜야 한다 |
| N-Canvas 가 v3 행을 편집하면 v2 가 되어 다음 폰트 변경 때 reflow 되지 않음 | flag on 에서 한 번 편집하면 v3 로 복귀 |
| CloudKit 스키마 승격 순서 (§10-1-a) | 기본 활성화 전 dev 저장 → promote |

---

## 16. 검증 상태

### SDK 헤더로 확인 (iOS 26.2)

`PKCanvasViewDrawingPolicy` 는 3개뿐 (`.prohibited` 없음 → 게이트는 `drawingGestureRecognizer.isEnabled`) · `PKCanvasView : UIScrollView` · `PKStroke.randomSeed` (iOS 16+) · `PKStroke.mask` / `maskedPathRanges` · `PKEraserType` `.vector` / `.bitmap` / `.fixedWidthBitmap` · `PKStrokePath.creationDate`.

### 완료

| ID | 결과 |
|---|---|
| S0-2 | 테스트 기준선 확보 (§18-2). flaky 1건은 `19be99ea` 로 해소 (§20-1) |
| S0-3 | `drawing.id` 는 문맥 의존 오버로드 — 표현 금지 (§8-7) |
| S0-4 · D5 | N-Canvas baseline — 시뮬레이터 §18-3, 실기기 §18-3-a |
| S0-5 · D8 | 진짜 legacy `lineData` 는 실기기 필요 → 225행 추출, fixture 5건 (§18-4 · §20-3) |
| S1-1~5 · D3 | `randomSeed` 보존 · bitmap 지우개는 분할+마스킹 · 완전히 지운 stroke 제거 · IdentityKey 불변 · mask 보존. 실제 Pencil 도 동일 (§19 · §20-7) |
| S2 | `textLineRanges` 실현 가능 — `Run.characterIndices` iOS 17.0+ (§19-3) |
| S3 | 시편 119편 176절 Δ 0.00pt · 게이트 PASS · `columnOrigin.x` 366.70 (출시 구성에서 재확인, §20-9) |
| S4 · D1 · D2 | A/B — 시뮬레이터는 구별 못 함, 실기기에서 B ✅ / A ❌ → **B 확정** (§11) |
| S6 | 단일 Canvas 스모크 — 176/176 · Δ 0.00 · `PKCanvasView` 1개 · 124 MB (§20-9). 펜 입력 미실행 |
| D4 | Pencil 더블탭 · 두 손가락 더블탭 undo 정상 (§20-7) |
| D6 | 회전·리사이즈 시 필사 표시가 어긋나고 되돌리면 복구 — G4 가 풀려는 문제 그 자체 (§20-7) |
| D7 (일부) | `NSPersistentCloudKitContainer` 가 V4 수용 · `.externalStorage` 미러링 · `rowUUID` 정책 · 큐 정상. **미검증:** 메타데이터 없는 행의 도착 · `isPresent` 복수 충돌 (§20-7) |
| **D9 (R13 · R16)** | ✅ **실기기 재검증 통과** — 시편 119편 Δ 87.50 → **0.00** · `slope` +0.500 → **+0.000/절** · `top` v1~v176 전부 0.00 · 장 전환 4건 `totalHeight` **5138.0 동일** · 정상 상태에서 `guard OPEN` (오탐 없음). **D9-1 보류 해제** (§20-14) |

### 남은 것

**종결된 결함 8건** — 재발 판별에 쓸 실측 기준만 남깁니다.

| ID | 결론 |
|---|---|
| ✅ **R13** | **절당 0.5pt 누적.** 빌더가 행 높이를 `lineCount × lineSpace` 로 **예측**했다 (시편 119편 87.50pt · 창세기 1장 15.00pt = (N−1) × 0.5). **실측 높이를 레이아웃 입력으로 승격**해 종결 (§20-14) · 실기기 Δ **0.00** |
| ✅ **R16** | **장 전환 시 텍스트 컬럼 신장.** `columnHeight` 미초기화 → 이전 장의 큰 높이가 호스트 frame → 행이 초과분을 흡수 → 1335.78pt, 자가 복구 불가. `.fixedSize` 로 종결 (§11) · 실기기 4건 통과. **Phase 3 단일 Canvas 전용** |
| ✅ **D9 H** | **회전 후 이전 필기가 표시되던 결함.** 표시용 획 재구성을 `applyDrawing` 에 넣어 종결 (§20-16 · `ef053111`). 실기기 확인: 회전 3왕복 · 글꼴/행간 변경 · 좌우 전환 · 스크롤 중 회전 · 편집 저장 왕복 · 회전 직전 flush 전부 정상이고, `-CanvasReuseStrokesOnApply` 대조에서 **매번 결함이 재현**됐습니다. **계측(`store`/`delivered`/`applied` 일치 · `storeDiff=0` · `expected==canvas`)은 두 경로를 구분하지 못하고 화면 판정만 갈립니다** — 재발 판별의 기준입니다. 비용은 R20 |
| ✅ **E-4** | **결함 아님 — D9 H 와 같은 결함이었습니다.** 글꼴·행간을 바꾸면 **v1·v3 잉크가 모두** 본문을 따라갑니다(시편 120편: 1절 v3, 2·4절 v1). rev.22 의 "v1 이라서" 설명은 성립하지 않습니다. 대조 모드에서만 제자리에 남습니다 |
| ✅ **R19** | `drawingVersion == 3` 인데 metadata 가 없는 행을 **첫 밑줄 원점**으로 읽는다 — 좌표 형식의 단일 진실은 버전이고 metadata 는 band 매핑 근거일 뿐입니다 (§10-1 · §9-3-1). `8901a0fe` · `LegacyInkPlacementTesting` 이 고정 |
| ✅ **R23** | **수정 완료 (2026-09-08).** flag off 로 장을 **열기만 해도** 그 장의 v3 절이 v2 로 강등되고 `layoutMetadataData` 가 삭제되던 결함. 원인은 N-Canvas coordinator 에 프로그램 대입 억제가 없어 로드 즉시 `.saveDrawing` 이 나간 것이고, 단일 Canvas 와 같은 `isApplyingDrawing` 관용구로 막았습니다. 회귀 2건 추가(기준선 302 → **304**), 변이 테스트로 `drawingVersion → 2` · `metadata → nil` 실패 확인, 실기기에서 **170행 불변** 재확인. §10-3 의 "편집할 때만 강등" 이 이제 지켜집니다 |
| ✅ **R24** | **같은 장 재로드가 기하 실측을 버려 복구 불가 상태를 만들던 결함 (2026-09-08 수정).** `begin()` 이 `rowFrames`·`canvasFramesInRow`·`measuredFrames`·`titleHeights` 를 지우는데 producer 인 `onGeometryChange` 는 값이 바뀔 때만 부른다 — 같은 장·같은 폭이면 아무도 복구하지 못한다. **증상은 셋이었다**: 캔버스 미활성으로 flag off 시 화면 밖이던 절의 **잉크가 사라짐** · 레이아웃이 **실측 높이 대신 예측식으로 후퇴**(R13 재발, `H` 3016 → 2977) · **Δ 안전망 실명**(`deltaMax=unmeasured`). 장·절 목록이 실제로 바뀔 때만 버리도록 고쳤고, 회귀 4건(304 → **308**)·변이 확인·실기기 재확인을 마쳤다 |
| ✅ **R21** | **단일 Canvas 가 N-Canvas 보다 가볍다 (2026-09-08 실측).** 열어 둔 이유는 단일 Canvas 의 시편 119편 진입 peak(944.8 MiB)이 D5 의 N-Canvas baseline(363.6 MB)과 어긋난 것이었는데, **같은 절차로 N-Canvas 를 재니 오히려 N-Canvas 가 무거웠습니다** — 정점 **1376/1388 MiB vs 943/948 MiB**, 안정 **1321/1322 MiB vs 874/882 MiB** (순서 바꿔 2회씩). N-Canvas 는 행이 활성화될 때마다 `PKCanvasView` 가 쌓여 **스크롤이 곧 메모리**이고, 단일 Canvas 는 평평합니다. **D5 와의 차이는 경로가 아니라 절차 차이였습니다**(§18-3-a 는 스크롤 절차가 계측되지 않았습니다). 레이아웃 시간도 같습니다(`firstMs` 419 vs 437) |

**살아 있는 항목**

| ID | 내용 |
|---|---|
| ✅ **R26** | **긴 장을 떠나도 메모리가 회수되지 않던 결함 (2026-09-09 수정).** 시편 119편을 거쳐 120편으로 오면 945 MB 였다(cold launch 는 179.7 MB). 실기기 귀속 실험에서 **본문 컬럼만 비우자 757 MB 가 풀렸고** 잉크는 16 MB 였다 — 원인은 `UIHostingController` 를 장마다 재사용하며 `rootView` 만 갈아끼워 이전 컬럼의 백업이 남는 것이었다(§5 가 재생성을 미채택한 결과). `setColumn(_:chapter:)` 이 **장이 바뀔 때만** 한 번 비우도록 고쳤고 **945 → 124.4 MB** 로 재확인했다 (D5 의 N-Canvas 109.7 MB 와 같은 수준) |
| ⚠️ **R27** | **기존 행의 `rowUUID` 가 서버에 없습니다.** V4 가 새 행마다 쓰는 값인데 Production 스키마에 필드가 없어 2026-09-09 승격 전까지 올라가지 못했습니다. 앞으로는 올라가지만 **이미 만들어진 행은 여전히 없고**, 저장 경로가 rowUUID 로 행을 찾으므로 다른 기기에서 **절당 행 중복**이 생겼을 수 있습니다. 기기 2대 확인 필요 (런북 §8-7) |
| ⛔ **R28** ★ **출시 전 결정** | **혼재 버전에서 구버전이 v3 행을 잘못 다룹니다.** `displayTransform` 과 v3→v2 강등이 둘 다 `24e9818e`(Phase 3, **미출시**)에 들어왔고, 출시본은 V4 스키마(`b68b6101`)까지만 있습니다 — **필드는 받지만 해석·강등 규칙이 없습니다.** 보기만 하면 한 줄쯤 밀려 보이고(데이터 무사), **편집하면 좌표는 캔버스 로컬로 덮어쓰면서 라벨은 3 으로 남아** 새 기기에서도 어긋납니다. 재편집으로 복구되며 조건은 좁습니다(기기 2대 + 한쪽 미업데이트 + 양쪽 필기). 완화책: 단계적 출시 / 최소 버전 게이트 / 감수 |
| ⚠️ **R20** | **회전 전이 peak 과 jetsam 한도 (2026-09-09 실측).** 보유 기기(8 GB)의 한도는 **≈ 3376 MB**. 시편 119편 진입 **934.8 MB**, **회전 peak 1839.2 MB**(여유 45.5%). ⚠️ **다만 비교 대상이 안전한 기준선이 아니다** — 같은 장에서 **N-Canvas 는 정지 상태가 1322 MB** 다(R21). 한도가 RAM 에 비례한다면 3 GB 기기(~1260 MB 추정)에서는 **현재 출시본이 이미 상시로 그 선을 넘는다.** 단일 Canvas 는 정지 448 MB 낮고 회전에만 높으므로 **전환은 대체로 완화 쪽**이다. 외삽은 한 점에서 나왔으니 단정하지 않는다 — 실제 확인은 배포 후 **MetricKit** 의 memory 종료 카운트로. **실질 개선은 회전 전이를 정지 상태 근처로 낮추는 것** |
| ⚠️ **R29** | **`BiblePageDrawing` 이 코드에는 남아 있는데 CloudKit 레코드 타입은 없습니다 (2026-09-09).** 배포 전 정리 때 `CD_BiblePageDrawing` 을 지웠으므로 **이 경로를 되살리면 Production 에 없는 타입을 쓰게 되어 동기화가 조용히 실패합니다** — `DrawingDatabase.upsertPageDrawing` 과 스키마에 경고 주석을 남겼습니다. ✅ **롤백됐던 옛 단일 Canvas 구현(`CombinedCanvasFeature`·`CombinedCanvasView` 967줄)은 삭제했습니다** — 새 단일 Canvas 옆에 남아 있어 혼란만 줬고, 삭제 후에도 312 통과로 정말 죽은 코드였음이 확인됐습니다. 그 결과 `fetchPageDrawing`·`upsertPageDrawing` 의 **제품 코드 호출부가 0건**이 되고 테스트(`DrawingSchemaV4MigrationTesting`)만 남았습니다. **엔티티 제거는 V5 마이그레이션이 필요해 여전히 Phase 4** 입니다 |
| ⚠️ **R17** | **`Δ max` 가 R16 계열을 검출하지 못합니다** — 레이아웃이 실측 높이를 따라가 예측 == 실측이 되기 때문 (§20-14 부작용 2). 자동 검출은 `hostedColumnKeepsIdealHeightAndStaysAtTop` 하나뿐이고, 실기기 대체 절차는 HUD 의 `H` 비교 (런북 §6-9 D9-0-d) |
| ⚠️ **R18** | **N-Canvas 가 새로 만드는 행이 v2 가 아니라 v1(모델 기본값)로 저장됩니다.** 배치에는 영향이 없으나(코덱이 v1·v2 를 같게 처리) 진짜 legacy 와 오늘 그린 행이 `legacyVerses` 한 통에 섞여 **진단에서 구별되지 않습니다.** 저장 경로 별건 (런북 §8-7) |
| ⚠️ **R22** | 세로 화면인데 도구 팔레트가 가로 폭으로 배치돼 **redo 버튼이 잘립니다** (2026-09-08 관측). UI 별건이나 undo/redo 접근성이 막힙니다 (런북 §8-7) |
| **D9 (진행 중)** | **절차: [런북 §6-9](./phase-0a-d-device-test.md) · 기록: 런북 §8-7.** 통과: 스모크 · **D9-1** · **D9-2** · **D9-3-1·2·4** · **D9-4-1·4** · **D9-7-4** · **D9-8**(측정) · D9-CK②. ❌ **D9-6**(flag 롤백 — R23 으로 실패 정정. 이전 ✅ 는 화면만 본 판정이었습니다). 미수행: **D9-5**(히스토리 메뉴) · **D9-7 나머지**(fling·탭/롱프레스) · **D9-CK③**(Production 승격). **기본 활성화의 선행 조건** |
| D7 나머지 | 기기 2대가 필요한 미러링 항목 2건 · §10-1-a 승격 절차 |
| 기기 사각지대 | 보유 기기(iPad mini A17 Pro · iPad Air M2)는 60Hz · 8GB. ProMotion 과 저메모리 iPad 는 TestFlight 베타에서 |
| 코드 외부 | 1.2.0 배포 기간의 절대좌표 데이터 실존 여부 — App Store Connect 이력으로만 확인됨 |

---

## 17. 룰 체크리스트

- [x] Canvas 는 장당 하나 · 저장 기준은 절별 Drawing · atomic batch 저장
- [x] 좌표 영역 = `ChapterLayoutBuilder`, transform 적용 = `DrawingCodec` (U5)
- [x] Feature 에서 PencilKit/UIKit 타입 제거 · SwiftData 접근은 Repository 단일 경로
- [x] 지우개 · undo/redo · 빈 절 저장 포함 (P7) · 지우개 모드 `.bitmap` (U3)
- [x] 레거시 비파괴 (런타임 lazy) · 레이아웃 변경은 표시 변환만 (P10) · V4 forward-only 명문화
- [x] 편집 계약 — begin/end · 세대 · 물러난 세션 · 직렬 저장 · retry
- [x] identity key 와 content signature 분리 · 신규 행 rowID 선발급 · 저장 중 최신 mutation 보호
- [x] layout / drawings 도착 순서 무관 · 요청 취소 · 절별 액션 금지(수집기)
- [x] 실제 존재하는 입력 게이트 (`drawingGestureRecognizer.isEnabled`) · 디버그 오버레이 · Δ 검증은 출시 구성에서
- [x] U1~U8 확정 (§12) · 저장 명령 의미 확정 (§8-6)
- [x] 승계 규칙 3 은 규칙 2 의 전제 위에서만 — 새 획은 시작 절 (rev.19)
- [x] 단일 Canvas 는 flag 뒤, 기본 off — 설정 토글 · v3 행의 N-Canvas 호환 · 히스토리 메뉴
- [ ] §8-5 장 전환 요청/승인 흐름 — 미구현 (현재는 flush + 물러난 세션)
- [x] **R13 · R16 수정** (§16) — 실기기 재검증 통과 (§20-13 · §20-14)
- [ ] 실기기 **D9** → 기본 활성화 판단 → Phase 4

---

## 부록 — 삭제/격하 대상 요약

| 대상 | 처리 | Phase |
|---|---|---|
| `CanvasFeature` / `CanvasView` · `CombinedCanvasFeature` / `CombinedCanvasView` (`StableCanvasView` 포함) | 삭제. 단일 Canvas 는 신규 파일로 작성됐고 구 파일은 flag off 경로가 사라질 때 함께 | 4 |
| `SharedUndoManager` | 삭제 — 불필요 (§13 Phase 4) | 4 |
| `clippedPrecisely` / `normalizedForVerseRect` · `VerseRowFeature` | 삭제 | 4 |
| `Data.containsPKStroke` | 의미 유지 — 호출부만 수정 완료 (`7ba5bc46`) | ✅ |
| `BiblePageDrawing` | 격하 → 제거 후보 (실데이터 0행) | 4 |
| `DrawingDatabase.updateDrawings(requests:)` · `updateDrawing(drawing:)` | 대체 구현 존재 (`SwiftDataDrawingRepository`). N-Canvas 가 쓰는 동안 유지 | 4 |
| `BibleDrawing.mainDrawing()` · `VerseDrawingHistoryFeature` | ✅ 결정적 규칙 적용 · B 에서도 연결됨 | ✅ |
| `touchIgnoringContextMenu` 의 행별 중첩 `UIHostingController` · `CarveDetailView.activeCanvasIDs` | 삭제 — N-Canvas 행과 함께 | 4 |
| `ChapterLayoutMeasurement` · `VerseGeometryCollector` · `ChapterLayoutHosting` · `ChapterLayoutSignpost` | 유지 — 두 경로가 그대로 공유 | ✅ |

---

## 18. 부록 B — Phase 0A-S0 실측 결과

> 환경: Xcode 26.3 / Swift 6.2.4 / tuist 4.39.0 / iPad mini (A17 Pro) 시뮬레이터 iOS 26.2. **§18-3-a 만 실기기 기록**이며 시뮬레이터 값과 절대값 비교는 금지입니다.

### 18-1. 재현 조건

| 항목 | 값 |
|---|---|
| tuist | `PATH` 기본값(4.44.3)과 다르므로 반드시 `mise x -- tuist …` |
| iPad 시뮬레이터 런타임 | iOS 26.2 하나뿐. iOS 17/18 iPad 런타임 없음 → "저사양 iOS 17 iPad" 리스크는 시뮬레이터로 보완 불가 |
| 툴체인 | **Xcode 26.3 이 아니면 빌드되지 않음** — TCA 1.20.2 가 Swift 6.3.3 에서 컴파일 실패 (AGENTS.md) |

### 18-2. S0-2 — 테스트 기준선

rev.8 시점 **57/57** (DomainTest 31 · CarveFeatureTest 8 · CarveToolkitTest 6 · ChartFeatureTest 6 · SettingsFeatureTest 3 · UIComponentsTest 3). 이후 이력과 현재 기준선은 §19-4-2.

### 18-3. S0-4 — N-Canvas 경로 baseline (시뮬레이터) ★

**측정 방법 (재측정 시 그대로 반복)**

```
메모리  /usr/bin/footprint <pid>   (vmmap 은 이 머신에서 권한 오류 — 같은 Physical footprint 지표. ps RSS 는 부적합)
CPU     ps -o time= 누적 CPU time 델타, 0.25 s 샘플링
장 지정  simctl uninstall 로 컨테이너를 비운 뒤 설치 → defaults write … title -data <BibleChapter JSON hex> → 로그 "ChapterLayout 완성" 으로 확인
        (앱이 한 번 장을 바꾸면 Saved Application State 가 시드를 무시한다)
로그     앱 실행 전에 log stream --level debug 를 붙인다 (Log.info 는 log show 에 남지 않음)
스크롤  -ChapterLayoutAutoScroll (settle 8 s 뒤 1 s 간격 11단계) — 원래 절차는 flick 11회 (372,900)→(372,200)
캔버스 수 com.apple.pencilkit 의 isGenerationToolEnabled 로그 1줄 = PKCanvasView 1개
기준점  cold launch 후 8초 settle
```

**(A) Cold launch** — 창세기 1장 78.2 MB · 시편 119편 86.2 MB (진입은 절 수에 거의 무관, `LazyVStack`).
**(B) 장 전환 진입** — 창세기 1→2장 +25.6 MB / 0.25 s · 시편 118→119편 +37.4 MB / 0.31 s.
**(C) 장 전체 스크롤 (flick 11회)** — 창세기 1장 +49.9 MB / CPU 9.99 s · 시편 119편 +109.0 MB / CPU 24.70 s (증분 ≈ 37 + 0.41·N MB). 비용은 진입이 아니라 **스크롤에 분산**.
**(D) 메모리 회수 안 됨** — 시편 119편 스크롤 후 195 MB → 시편 120편 진입 후 209 MB. **실기기에서는 재현되지 않았습니다** (§18-3-a) — 시뮬레이터 한정으로 읽으십시오.

> ⚠️ rev.15 에 같은 절차로 옛 코드를 다시 재자 (C) 는 458 MB 였습니다 (캔버스당 ≈2.1 MB, 원인 미상). **Phase 3 이후 비교의 기준은 (C) 의 195 MB 가 아니라 §20-8 의 458 MB 입니다.**

### 18-3-a. D5 — N-Canvas 경로 baseline (실기기) ★

```
기기   iPad mini (A17 Pro) / iOS 27.0 beta (24A5408d) · Xcode 26.3 개발 서명 Debug · USB (Wi-Fi 로는 기록이 1초 만에 끊기고 데이터도 유실)
도구   xctrace record --template 'Activity Monitor' --all-processes → sysmon-process 의 memory-physical-footprint
       (Allocations 는 오버헤드가 커서 앱이 사실상 멈춘다 — 스크롤 측정에 쓸 수 없음)
```

| 구간 | 메모리 (MB) | 평균 CPU |
|---|---|---:|
| 창세기 1장 진입·스크롤 | 70.9 ~ 276.7 | 35.5% |
| **시편 119편 진입·스크롤** | 73.0 ~ **363.6** | **84.5%** |
| 시편 120편 전환 후 정지 | **109.7** (평평) | 0.1% |

peak **363.6 MB** · 최종 정지 **109.7 MB** · CPU > 90% 샘플 47 / 188. **§18-3 (D) 의 "미회수" 가 재현되지 않았습니다** — 실기기는 회수됩니다. 이후 실기기에서 메모리가 회수되지 않는다면 그것은 새로운 현상입니다.

한계: iOS 27 beta · 1회 측정 · 손가락 조작(부하 재현 보장 없음) · 구간 경계는 타임라인 추정 · iPad Air 미수행 · hitch time ratio 미측정.

### 18-4. S0-5 — legacy fixture 확보 경로

현행 스키마의 새 필사 데이터는 시뮬레이터에서 만들 수 있지만 **진짜 legacy `lineData` 는 실기기 파일 복사뿐**입니다 — Debug 빌드는 dev CloudKit 컨테이너에 붙는데 실사용 데이터는 prod 컨테이너에 있습니다. `lineData` 는 `.externalStorage` 라 `Carve.sqlite` 하나가 아니라 `Library/Application Support/` 전체를 가져와야 합니다. 절차는 [phase-0a-d-device-test.md](./phase-0a-d-device-test.md) §6-1. 결과는 §20-3.

### 18-5. S0에서 나온 후속 영향

| # | 발견 | 영향 |
|---|---|---|
| 1 | 시뮬레이터는 CloudKit 미러링이 전혀 동작하지 않음 (entitlement 비어 있음) | V4 의 CloudKit 제약은 실기기(D7)에서만 검증 가능 |
| 2 | `LazyVStack → VStack` 은 비용을 스크롤에서 진입으로 옮김 | 통과 기준은 **(B)표 기준으로 엄격히**. 실측 결과 캔버스는 지연 생성으로 바꿨고 남은 증분은 텍스트 행 176개 (+100 MB / +2.3 s, §20-8) |
| 3 | iPad 시뮬레이터 런타임이 iOS 26.2 뿐 | 저사양 iOS 17 iPad 리스크는 베타 단계로 |

---

## 19. 부록 C — Phase 0A-S1 / S2 실측 결과

### 19-1. 결과 요약

| ID | 결과 | 설계 영향 |
|---|---|---|
| S1-1 | `randomSeed` 라운드트립 보존 | `StrokeIdentityKey` 성립 |
| S1-2 | bitmap 지우개는 **분할 + 마스킹 동시** | §7-4 — 조각들이 IdentityKey 를 공유해 결론이 강화됨 |
| S1-3 | 완전히 지운 stroke 는 **제거됨** | §7-5 — 저장 가드 문제로 재정의 |
| S1-4 | IdentityKey 구성요소 전부 불변 | §7-3 1번 신뢰도 |
| S1-5 | `mask` / `maskedPathRanges` 보존 | `ContentSignature` 성립 |
| S2 | `textLineRanges` 실현 가능 | §9-3 |

### 19-2. S1-4 — 지우개 전후 비교

| 항목 | 지우기 전 | 지우기 후 (두 조각 모두) |
|---|---|---|
| `randomSeed` · `path.creationDate` · `path.count` · control points · `transform` | 956091164 · …7905478 · 10 · — · identity | **전부 동일** (control point 10개 값까지) |
| `renderBounds.width` | 264 pt | 112 / 112 pt (축소) |
| `mask` | nil | 각각 다른 clip 영역 |

### 19-3. S2 — `Text.LayoutKey` 타입 구조

바이너리 swiftmodule 의 symbol graph 로 확정 (`xcrun swift-symbolgraph-extract -module-name SwiftUICore`). `Text.Layout` → `Line` (`origin`, `typographicBounds`) → `Run` (**`characterIndices`**, `typographicBounds`, `layoutDirection`), 전부 iOS 17.0. `CharacterIndex` 는 `Strideable(Stride == Int)`. 런타임 확인(창세기 1:2, 46자, 폭 180pt): 4줄 `[0...12, 13...25, 26...39, 40...45]` — 빈틈·겹침 없음.

### 19-4. 추가된 테스트

이력은 §19-4-2 로 대체합니다. 실측 블롭은 테스트 타깃에 resource 설정이 없어 base64 상수로 내장했습니다 (빌드 설정 변경 회피).

### 19-4-2. 회귀 기준선 이력 ★

`xcodebuild test -scheme Carve-Workspace`, iPad mini (A17 Pro) iOS 26.2, Xcode 26.3 / Swift 6.2.4. **줄어들면 회귀입니다.**

| rev | 합계 | 증분 |
|---|---:|---|
| 8 | 57 | 초기 |
| 9 | 76 | S1/S2 10 · 지우개 회귀 6 · 동점 규칙 3 |
| 10 | 82 | legacy fixture 6 |
| 11 | 122 | `ChapterLayoutBuilder` 13 · 소유권/승계 27 |
| 12 | 155 | reflow 33 (S4 하네스는 테스트 없음 — HUD 판정) |
| 13 | 175 | V4 마이그레이션 11 · §10-3 등가 9 |
| 15 | 203 | Phase 2 — 인셋 7 · 측정 12 · 수집기 3 · 배선 6 |
| 16 | 237 | 저장 계층 13 · 코덱 11 · 리듀서 10 |
| 17 | 259 | 결함 수정 22 |
| 18 | 264 | (3/3) 5 |
| 19 | 265 | 승계 규칙 3 전제 1 |
| 20 | 267 | R16 회귀 2 (장 전환 컬럼 신장). CarveFeatureTest 142 · DomainTest **103** (XCTest 2 포함) · SettingsFeatureTest 4 · ChartFeatureTest 9 · CarveToolkitTest 6 · UIComponentsTest 3 <br>⚠️ rev.20 문서는 DomainTest 를 101 로 적어 per-target 합이 265 로 어긋났습니다 (rev.21 정정) |
| **21** | **285** | R13 18 (빌더 4 · 파이프라인 3 · 안전망/배선 8 · 부작용 고정 1 · Phase 3 흡수 1 + 변이 보강). 당시 기준선 — CarveFeatureTest 156 · DomainTest 107 (XCTest 2 포함) · SettingsFeatureTest 4 · ChartFeatureTest 9 · CarveToolkitTest 6 · UIComponentsTest 3 |
| 23 | 296 | 당시 기준선 — CarveFeatureTest 167 · DomainTest 107 (XCTest 2 포함) · SettingsFeatureTest 4 · ChartFeatureTest 9 · CarveToolkitTest 6 · UIComponentsTest 3. 조사 인계 기준 295에서 진단 안전성 테스트 1개 추가. rev.21 이후 선행 변경도 포함 (§20-15) |
| 24 | 302 | D9 H 정식 수정 6건 (표시용 재구성의 속성·소유권 보존 · 마스크 파생값 고정점 · 지우개 절 1회 dirty · 빈/디코드 실패 · 같은 revision 무교체 · 회전 flush). CarveFeatureTest 173 · DomainTest 107 (XCTest 2 포함) · SettingsFeatureTest 4 · ChartFeatureTest 9 · CarveToolkitTest 6 · UIComponentsTest 3 |
| 26 | 304 | R23 회귀 2 (① 프로그램 대입은 v3 를 강등하지 않는다 ② 사용자 편집 콜백은 그대로 저장된다 — 억제 과잉 방지). 실측 내역: Swift Testing 302 + XCTest 2. 변이 테스트로 억제 제거 시 `drawingVersion → 2` · `metadata → nil` 실패 확인 |
| 28 | 308 | R24 회귀 4 (`ChapterLayoutReloadTesting`: 같은 장 유지 · 다른 장 폐기 · 절 목록 변경 시 폐기 · 실측 높이 유지). Swift Testing 306 + XCTest 2 |
| 30 | 310 | 단일 Canvas 기본 전환 회귀 2 (토글 미조작 사용자가 기본값을 본다 · 명시적 off 가 유지된다). Swift Testing 308 + XCTest 2 |
| **31** | **312** | **현재 실측 기준선** — R26 회귀 2 (같은 장은 컬럼을 놓지 않는다 · 장이 바뀌면 놓는다). Swift Testing 310 + XCTest 2 |

통과한 실행에서도 PencilKit 필기인식 권한 `com.apple.corehandwriting -1003`와 CoreData persistent history 정리 로그가 관찰됐습니다. 모든 `error:`를 노이즈로 취급하지 말고, 명령 종료 코드·실행 테스트 수·실패 내용을 함께 확인합니다. rev.16 클린 빌드에서 `UIComponentsTest` 의 테스트 타깃 의존성 누락을 고쳤습니다.

### 19-5. S1에서 확인하지 못한 것

- `PKEraserTool(.vector)` 동작 — 범위 밖. 결론은 `.bitmap` 한정
- `CharacterIndex` 의 단위 (Character vs UTF-16) — §9-3

---

## 20. 부록 D — 변경 기록

| 커밋 | 내용 | 절 |
|---|---|---|
| `19be99ea` | 주간 요약 동점 tie-break | §20-1 |
| `7ba5bc46` | 지우개 저장 누락 | §20-2 |
| `0e9a8449` | D8 legacy 데이터 추출 + fixture | §20-3 |
| `f5206814` · `0c071d29` · `565dfe69` | Phase 0B | §13 |
| `b53cbfd8` | S4 스크롤 A/B 하네스 | §20-4 |
| `b68b6101` | Phase 1 V4 스키마 | §20-5 |
| — | 실기기 세션 D1~D7 | §20-6 · §20-7 |
| `94fe4578` | Phase 2 | §20-8 |
| `2cde2ad1` · `a1ac525f` | Phase 3 (1/3 · 2/3) | §20-9 |
| `24e9818e` | 리뷰 결함 15건 | §20-10 |
| `ea462922` | Phase 3 (3/3) | §20-11 |
| `df15ba45` | 승계 규칙 3 전제 | §20-12 |

### 20-1. `19be99ea` — 주간 요약 동점 tie-break

`ChartFeatureTest / DrawingWeeklySummaryStateTesting` 1건이 5회 중 1회 실패했습니다. `merged.max(by:)` 가 동점이면 `Dictionary` 순회 순서에 좌우되고 Swift 해시 시드는 프로세스마다 다릅니다. `TopChapterRank(Comparable)` 로 **전순서**를 두었습니다 — ① 합계 내림차순 ② 성경 순서(`BibleTitle.allCases`) ③ 장 번호. 새 구현에서도 Dictionary/Set 순회 순서에 결과를 맡기지 않도록 주의합니다 (§7-3 · §8-7 의 결정성 요구와 같은 유형).

### 20-2. `7ba5bc46` — 지우개 저장 누락

증상은 §7-5. 세 판단: `containsPKStroke` 의미 불변(호출부만 수정, V1→V2 마이그레이션이 같은 의미를 씀) · `canvasViewDidEndUsingTool` 은 획 반영 전에 불려 저장 지점으로 쓸 수 없음 · `setSentence` 의 대표 drawing 후보 필터 제거("전부 지운 최신 기록" 이 빠지면 과거 회차가 승격됨 — §8-7 `clear` 와 같은 함정). 부수: 기록이 없는 절 + 빈 canvas 는 새 행을 만들지 않음. 회귀 테스트 6건 (`DrawingErasePersistenceTesting`).

### 20-3. `0e9a8449` — D8 legacy 데이터 추출과 fixture

개발 서명 설치가 불가한 상태라 Finder 비암호화 로컬 백업에서 추출했습니다 (2026-09-05, iPad mini A17 Pro).

| 항목 | 값 |
|---|---|
| `ZBIBLEDRAWING` | **225행** (2025-02-13 ~ 2026-03-23), `ZDRAWINGVERSION` **전부 1** (D3 "죽은 필드" 실증) |
| `ZBIBLEPAGEDRAWING` | **0행** → `BiblePageDrawing` 제거 부담 없음 |
| 디코드 | 225/225 성공 — PencilKit 인코딩 호환성 문제 없음 |
| 좌표 | 225건 전부 절 로컬 — 1.2.0 배포 기간에 이 기기의 필사가 0건. 절대좌표 fixture 는 `LegacyDrawingFixture.absoluteVariant` 로 합성 |

산출물: `LegacyDrawingFixture.swift` (실사용 blob 5건, 식별 메타 제거) · `LegacyCoordinateTesting.swift`. 추출 원본은 저장소 밖(`~/carve-device-dump/`)에 두고 커밋하지 않았습니다. §10-2-1 의 71% 는 여기서 나왔습니다.

### 20-4. `b53cbfd8` — S4 스크롤 A/B spike 하네스

Debug 전용, 파일 단위 `#if DEBUG`. `Feature/CarveFeature/Sources/Debug/CanvasScrollSpike*.swift` — View(모드 전환) · Hosting(A/B 실체) · Metrics(자체 측정기) · Content(mock layout) · Column · Store(launch argument · 무인 시나리오) · HUD. 진입점은 `App.swift` 의 `#if DEBUG` 분기 1건.

측정은 `contentOffset` 산술을 쓰지 않고(그것이 검증 대상) 잉크 / 텍스트 마커 / viewport 원점을 전부 UIKit `convert(_:to:)` 로 얻습니다. 컨테이너 이동은 `viewportOrigin` 을 빼서 제거합니다 (§11 기준 1).

| 인자 | 뜻 |
|---|---|
| `-CanvasScrollSpike` | 하네스 진입 (필수) |
| `-CanvasScrollSpikeMode A` / `B` · `-CanvasScrollSpikeAuto` · `-CanvasScrollSpikeJump <pt>` | 모드 · 8개 시나리오 무인 · 지정 offset 정지 |
| `-CanvasScrollSpikeLeftHanded` · `-CanvasScrollSpikeNarrow` · `-CanvasScrollSpikeAnyInput` · `-CanvasScrollSpikeNormalizeA` | 기준 4 · 3 · 정책 · A 정규화 |

**환경 제약 2건 (고치지 않음):** 시뮬레이터 터치 주입 도구가 `xcode-select` 설정 때문에 사용 불가 — 해소하려면 `sudo xcode-select` 로 시스템 설정을 바꿔야 해서 하지 않았습니다 (fling · 탭/롱프레스 미검증) · `vmmap` 권한 오류 (A/B 상대 메모리 미측정). 결과는 §11.

### 20-5. `b68b6101` — Phase 1 V4 additive schema

`layoutMetadataData` · `rowUUID` 두 optional 필드 추가, `MigrationStage.lightweight` 한 줄. `drawingVersion` 은 새 필드가 아니라 V2 부터 있던 것에 의미만 확정. typealias `BibleDrawing` / `BiblePageDrawing` 을 V4 파일로 옮겨 V3 는 동결된 과거 정의만 담습니다.

**마이그레이션을 실제로 태워 검증** — 임시 파일에 V3 스키마로 store 를 만들고 같은 파일을 앱과 동일한 표현으로 다시 열었습니다: 기존 행 생존 · `lineData` 바이트 동일 · `.externalStorage` 승격(1.87 MB blob, 임계값은 1 MB 근방) · 새 필드 nil · `drawingVersion` 불변. **§10-3 등가 검증** — 마이그레이션된 V4 store 에 기존 `DrawingDatabase` API 전부를 태우고 재오픈 시 재마이그레이션 없음까지 확인. legacy 행 갱신 후에도 `drawingVersion 1` · metadata nil · `rowUUID` nil 유지.

CloudKit 항목 4건은 당시 미검증이었고 D7 이 2건을 확인했습니다 (§20-7).

### 20-6. 실기기 세션 — D5 · D1 · D2

환경: iPad mini (A17 Pro) / iOS 27.0 beta (24A5408d) / Xcode 26.3 / USB. 코드 변경 없음, S4 하네스 그대로. 절차는 [phase-0a-d-device-test.md](./phase-0a-d-device-test.md).

| # | 결과 | 반영 |
|---|---|---|
| 1 | **스크롤 구조 B 확정** — 기준 7·8 이 A ❌ / B ✅ | §11 · §12 U4 |
| 2 | 오차의 정체 = 바깥 `ScrollView` 의 `contentOffset` | §2 D5 |
| 3 | `StableCanvasView` 접근 폐기 — 정규화를 켜도 동일 실패 | 부록 |
| 4 | D2 기준 9·10 통과 | §11 |
| 5 | D5 baseline 확보 · §18-3 (D) 미회수가 실기기에서 재현되지 않음 | §18-3-a |

**부수 확인 4건:** ① 개발 서명 설치가 App Store 앱의 데이터 컨테이너를 **보존**함 (1회 관측 — 백업 절차는 유지) ② V4 마이그레이션이 실기기·CloudKit entitlement 활성 상태로 성공 (`Carve.dev.sqlite` 7.4 → 8.8 MB, prod `Carve.sqlite` 변동 없음 — Debug/Release 분리 실증) ③ **Instruments 기록에는 USB 필수** — Wi-Fi 는 1.1초 만에 끊기고 `Deferred` 모드라 데이터도 유실 ④ `Allocations` 템플릿은 앱을 사실상 멈추므로 스크롤 측정에는 `Activity Monitor`.

### 20-7. D3 · D4 · D6 · D7 실측

**D3 ✅** — 실제 Pencil 로 시편 127:1 에 획 2개를 긋고 부분/완전 지우기 후 DB 디코드: 획 1개가 stroke 2개로 분할되고 각각 다른 `mask`, `seed` / `creationDate` / `points` 동일 (IdentityKey 1개), 완전히 지운 획은 `strokes` 에 없음. S1 과 동일 → §7-2 · §7-3 · §7-4 가 실기기에서 유효.

**D4 ✅** — Pencil 더블탭 지우개 전환 · 두 손가락 더블탭 undo (절을 넘나드는 순차 undo 포함) 정상. `SharedUndoManager` 의 구조적 지적은 관측 가능한 오동작으로 이어지지 않았습니다 — 삭제 근거는 "깨져 있어서" 가 아니라 "단일 Canvas 에서 불필요해서" 입니다.

**D6 ✅** — 회전·리사이즈 시 레이아웃은 깨지지 않으나 **필사 배치가 바뀌거나 잘려 보이고, 되돌리면 복구**됩니다. 폭이 바뀌면 개행 수가 바뀌는데 현재 구조에는 reflow 가 없기 때문 — G4 가 풀려는 문제 그 자체이며, 원본이 훼손되지 않는 성질(§9-4)은 새 설계가 후퇴시키지 않아야 할 기준입니다.
부수: `UISupportedInterfaceOrientations~ipad` 가 Tuist 기본값(4방향)이라 **세로 고정이 iPad 에서 적용되지 않습니다** ([InfoPlist.swift:23](../Plugins/ProjectDescriptionHelpers/InfoPlist.swift)). 이 설계 범위 밖.

**D7 (일부)** —

| # | 항목 | 결과 |
|---|---|---|
| 1 | `NSPersistentCloudKitContainer` 가 V4 를 수용 | ✅ (위반 시 `fatalError` 인데 정상 실행) |
| 2 | `.externalStorage` 미러링 | ✅ `CD_lineDataBytes` 존재 |
| 3 | `rowUUID` 정책 | ✅ 신규 6행 UUID / legacy 135행 nil |
| 4 | 미러링 큐 | ✅ 167건, 대기중 export 0 |
| 5 | `CD_layoutMetadataData` 서버 스키마 | ❌ 없음 — 값이 쓰인 적이 없어서. **배포 순서 문제** (§10-1-a) |
| 6 · 7 | 메타데이터 없는 행의 도착 · `isPresent` 복수 충돌 | ⏳ 기기 1대 · 인위적 데이터 필요 |

### 20-8. Phase 2 — `VStack` + 실측 파이프라인 + 게이트 + 오버레이

환경: 시뮬레이터 (§18-3 과 동일). 실기기 미측정. 파일과 역할은 §13 "Phase 2 산출물".

```
행 (SentencesWithDrawingView)
  Text.LayoutKey → 밑줄 offset · 소제목 높이 · 캔버스 영역 frame ─→ VerseGeometryCollector (한 틱에 모음)
        ↓ verseGeometryMeasured([id: VerseRowGeometry])   ← 시편 119편에서 1건
CarveDetailFeature — ChapterLayoutMeasurement.recordText / recordTitleHeight / recordRowFrame / recordCanvasFrameInRow
  전 절 텍스트 + writingWidth → ChapterLayoutBuilder.build   ← 0.71 s (signpost `measure`)
  isReady → drawingGestureRecognizer.isEnabled
```

- 1절의 상단 여백 25pt 는 캔버스 안(`topPadding`, `writingRect` 안)에 있습니다 — legacy 1절 데이터가 그 아래에서 시작하므로 밖으로 빼면 25pt 위로 밀려 보입니다.
- 소제목은 장 중간 절에도 붙습니다 (창세기 2:4). `writingRect` 밖 gap(`leadingInset`)이고 `captureRect` 가 midpoint 로 나눠 갖습니다.
- 행 frame 은 **검증 전용**입니다. 레이아웃 입력으로 쓰면 "빌더가 실제 배치를 재현하는가" 를 확인할 수 없습니다.

**S3 결과 — 시편 119편** `176/176 gate PASS · W 372 · H 16049 · columnX 366.70 · Δ max 0.00` (출시 구성으로는 §20-9 에서 재확인). `lineCount × lineSpace` 가 실제 행 높이와 일치합니다.

| 시나리오 | Phase 2 이전 (`LazyVStack`) | Phase 2 | 차이 |
|---|---|---|---|
| (A) 시편 119편 cold launch | 83 MB · CPU 3.06 s · 캔버스 20 | 187~198 MB · CPU 5.3~5.4 s · 캔버스 30 · 완성 0.71 s | **+100 MB · +2.3 s** = 텍스트 행 176개 |
| (B) 시편 118 → 119편 전환 | +18 MB · 0.25 s | +65 MB · 2.7 s (peak 248) | 사용자가 체감할 수 있는 크기. 실기기 값 없음 |
| (C) 전체 스크롤 11단계 | 83 → **458 MB** · CPU +13.3 s | 187 → 541 MB · CPU +13.1 s | **스크롤 비용 동일** |

§18-5 2번의 (B)표 기준을 그대로 적용하면 통과가 아닙니다. 다만 증분은 캔버스가 아니라 전 절 텍스트 실측 자체의 비용이며 B 구조도 같은 실측을 필요로 합니다. 줄일 여지: 행별 중첩 호스팅 제거(−18 MB · −0.23 s 뿐) · TextKit 측정 경로 · 밑줄 `Canvas` → `Path`. 실측으로 드러난 함정 3건(행별 액션 O(N²) · `VStack` 폭 발산 · 캔버스 즉시 생성 + 중첩 호스팅)은 §6-1.

### 20-9. Phase 3 (1/3 · 2/3) — 저장 계층 · 코덱 · `ChapterCanvasFeature` · B 호스팅 + flag

파일과 역할은 §4 · §13. 리듀서 흐름은 §8-8, 호스팅은 §11 "Phase 3 구현". 두 가지가 초안보다 보수적입니다: ① 레이아웃·`columnOrigin` 변경과 히스토리 복원은 **미저장분을 먼저 저장한 뒤 DB 에서 다시 합성** (DB 스냅샷으로 곧바로 합성하면 미저장 잉크가 화면에서 사라짐) ② 조회 실패는 빈 장이 아니라 **닫힌 게이트** (빈 장으로 열면 기존 행 위에 새 `create` 행이 생김).

**실측 — 같은 날 같은 절차 (§18-3 절차, `simctl uninstall` 시드)**

| 시나리오 | N-Canvas (flag off) | **단일 Canvas (flag on)** |
|---|---|---|
| (A) 시편 119편 cold launch | 204 MB · 첫 완성 0.98 s · `PKCanvasView` ~30 | **124 MB** · 0.89 s · **1** |
| (C) 전체 자동 스크롤 11단계 | 187 → 541 MB (rev.15) | **112 → 116 MB** — 스크롤로 메모리가 늘지 않는다 |
| 창세기 1장 (소제목 1개) | 124 MB · 캔버스 ~25 | **65 MB** · 1 |
| HUD (출시 구성) | 시편 `176/176 · Δ 0.00 · columnX 366.70` / 창세기 `31/31 · Δ 0.00` | **동일** |

잉크가 있는 장의 렌더 비용은 재지 않았습니다 (시뮬레이터에 필사 데이터 없음) — 16049pt 높이의 `PKDrawing` 하나가 스크롤에서 어떻게 렌더되는지는 D9 의 몫입니다. `.named` 좌표 공간 오염과 수정은 §6-1.

### 20-10. Phase 3 (2/3) 리뷰 결함 15건 수정 (rev.17)

네 뿌리로 묶었습니다. 설계 반영은 §8-1 · §8-3 · §8-4 · §8-5 · §10-3 · §11.

#### ① 편집 계약에 세대가 없고 재합성 게이트에 출구가 없음

| 위치 | 증상 | 수정 |
|---|---|---|
| `editEnded` | 장 전환 뒤 도착한 이전 장 편집이 새 장 기준으로 계산돼 오저장·잠금 | `CanvasEditSnapshot.generation` + `EditSession`(`retiredSession`). 코덱은 `renderedLayout` · `renderedColumnOrigin`(합성 시점 값)으로 계산 |
| `load` | `renderedRevision` 미증가 → 이전 장 잉크가 새 장 위에 남음 | 장 진입이 세대를 올림 |
| `columnOriginChanged` | 편집 중 즉시 reload → 획 유실 · 큐 교착 | `pendingColumnOrigin` 보류. `drainEditQueue` 의 `!isReloading` 가드 제거 |
| 재합성 중 저장·재조회 실패 | `isReloading` 미해제 → 입력 영구 잠금 | 합성 입력 = `DB ⊕ 미저장분`. 실패 시 그 입력으로 합성해 입력 재개 (`recoverFromReloadFailure`) |
| `scrollToVerse` | 장 전환 후 첫 토큰이 컨트롤러 잔존 토큰과 충돌 | `scrollRequestToken` 은 장이 바뀌어도 이어짐 |
| (후보) `load` 시점에 코덱 진행 중인 편집 폐기 | 확인됨 | 물러난 세션 + 컨트롤러의 교체 직전 flush. 장 진입은 flush 지점 |

#### ② 저장 명령 의미의 비대칭

`coalesce (clear, replace) → create` (아니면 `rowNotFound` 로 장 전체 저장이 영구 실패) · 디코드 실패 blob 은 `undecodableVerses` 로 활성 행에서 제외(다음 편집은 `create`, 원본 보존) · 장 진입 flush + scenePhase 훅을 `CarveNavigationView` 로.

#### ③ B 호스팅 기하

텍스트 호스트 frame = 컬럼 높이(content 높이로 늘리면 짧은 장에서 세로 중앙 배치 — 가장 심각) · 늦게 오는 헤더 높이는 맨 위 스크롤만 재고정 · `scrollOffset` 의 top inset 이중 차감 제거 · 다음 획 시작이 trailing 보고 취소.

#### ④ flag 경계

v3 행을 N-Canvas 가 첫 밑줄만큼 내려 표시하고 편집하면 v2 로 강등(§10-3) · 단일 Canvas 의 `scrollToTop` · 팔레트 `delegatesUndoToCanvas`.

검증: 테스트 22건 추가, 전량 259. 남은 위험: `retryCount` 는 `.saving` 을 거치며 1 로 돌아옴(로그용) · 같은 장 안의 재합성 직전에 커밋된 부분 획은 저장되지만 화면에는 다음 재조회 때 올라옴.

### 20-11. Phase 3 (3/3) — 히스토리 메뉴 재설계 · 설정 토글 (rev.18)

| 항목 | 구현 | 테스트 |
|---|---|---|
| B 의 히스토리 메뉴 | 손가락 롱프레스 → `UIEditMenuInteraction` → `Event.historyRequested(at:)` → `ChapterCanvasFeature.historyRequested(at:)` (합성 시점 레이아웃으로 `verse(containing:)`, 텍스트 쪽은 x 클램프) → `Delegate.showHistory(verse:)` → `CarveDetailFeature.chapterHistory` 시트(`VerseDrawingHistoryView` 재사용) → `setPresentDrawing` 에 `verseRowRestored` (§8-7) | 리듀서 2 · 배선 2 (실제 `Store`) |
| 설정 토글 | 설정 > 앱 설정 > **필사 캔버스** — `CanvasSettingsFeature` / `CanvasSettingsView`. 키는 Domain `SingleCanvasFlag.appStorageKey`. `Path` 가 `Hashable` 상태를 요구하고 `Shared` 는 `Hashable` 이 아니라 상태는 plain `Bool`, 쓰기는 `@Dependency(\.defaultAppStorage)` (KVO 로 `@Shared(.appStorage)` 가 따라옴). `CarveDetailView` 는 `usesSingleCanvas` 변화에 `fetchSentence`. flag off 뒤 미저장분은 `setSentence` / `appWillResignActive` 가 flush | 1 |
| `dirtyBounds` 오버레이 | `lastDirtyBounds` · `lastEditedVerse` → `CarveDetailView.lastEditForOverlay` | 리듀서 1 |

`ChapterLayout` 캐시는 구현하지 않기로 결정 (§6-1). 롱프레스 → 메뉴 → 시트의 실제 터치는 시뮬레이터에서 확인하지 못했습니다 (D9). 설정 화면은 `NavigationStack` push 라 Carve 상태가 유지됩니다.

### 20-12. 승계 규칙 3 을 규칙 2 의 전제 위에서만 적용 · 문서 정리 (rev.19)

**결함.** rev.17 리뷰가 "승계 규칙 3(겹침)이 U1(시작 절 귀속)보다 먼저 적용된다" 를 미검증 후보로 냈고, 확인 결과 사실이었습니다. `.bitmap` 지우개는 규칙 1 이 전부 처리하므로 규칙 3 이 실제로 발동하는 것은 새 획뿐이었고, 새 획이 이웃 절 잉크의 `renderBounds` 와 겹치면 이웃 절에 귀속됐습니다.

**수정 (`df15ba45`).** `StrokeOwnershipResolver.reconcile` 이 이전 세대 획의 `randomSeed` · `creationTime` 집합(`PartialIdentityIndex`)을 만들고, **부분 일치가 있는 획에만** 규칙 3 을 적용합니다. 그 밖은 규칙 4 (첫 control point). 규칙 3 의 기존 테스트 2건은 후보가 `creationTime` 을 공유하도록 바꿨고, "새 획은 이전 획과 겹쳐도 시작 절에 귀속된다" 를 추가했습니다. 전량 265.

**문서 정리.** 절 번호를 유지한 채 결정이 끝난 논의 과정 · rev 별 정정 문구 · 초안 시점의 State/DTO 코드 블록 · 중복 기록을 걷어내고 결정과 실측 사실만 남겼습니다 (3,760 → 약 1,280 줄). 과정은 git 이력에 있습니다.

### 20-13. D9 실기기 검증 — 레이아웃 결함 2건 (rev.20)

Phase 3 이후 처음으로 **제품 코드의 단일 Canvas 경로를 실기기에서** 봤습니다 (iPad mini A17 Pro · iOS 27.0 beta · USB). 필기(D9-1)에 들어가기 전 스모크에서 결함 2건이 나왔고, **둘 다 시뮬레이터에서는 드러나지 않았습니다.**

| ID | 결함 | 범위 | 상태 |
|---|---|---|---|
| **R13** | 빌더가 행 높이를 `lineCount × lineSpace` 로 예측 → 절당 0.5pt 어긋나 선형 누적 (176절 87.50pt) | Phase 2 공용 (N-Canvas·단일 Canvas 동일) | ✅ **종결** — 수정 (§20-14) · 실기기 Δ 0.00 |
| **R16** | `columnHeight` 미초기화 → 장 전환 시 컬럼이 초과 높이를 흡수해 신장 (1335.78pt, 자가 복구 불가) | **Phase 3 단일 Canvas 전용** | ✅ **종결** — 수정 (§11) · 실기기 4건 통과 |

**R16 수정과 회귀 테스트.** `hostedColumn` 의 `fixedSize` 한 줄이 본체이고, 회귀 2건을 붙여 기준선이 265 → **267** 이 됐습니다. 테스트는 **출하 조합(`ChapterCanvasView.hostedColumn`)을 그대로 호출**하고 `UIWindow` 에 올려 실제 SwiftUI 배치를 돌립니다 — `.fixedSize` 를 일시 제거하면 컬럼이 300 대신 1,175 로 늘어나 두 건 모두 실패하는 것을 확인했습니다.

**기존 테스트가 놓친 이유가 사각지대를 가리킵니다.** 기존 기하 테스트는 `setColumnHeight` 를 **직접 호출해** `contentFrame` 만 확인했습니다 — 컬럼을 실제로 배치·측정하지 않으니 "컬럼이 제안된 높이만큼 늘어나 같은 값을 되보고한다" 는 되먹임 고리가 테스트 경로에 아예 없었습니다. → **SwiftUI 호스팅을 실제로 돌리지 않는 기하 테스트 전반**이 같은 사각지대입니다 (§14).

**R13 의 구조적 논점.** 측정 파이프라인은 줄 수·밑줄 위치·소제목 높이·컬럼 폭을 전부 **실측**하는데 **행 높이만 예측**입니다. 그 예측은 뷰의 `lineSpacing = lineSpace − font.lineHeight` · `lineGapPadding = (lineSpace − font.lineHeight) / 2` 조합이 실수 연산으로 정확히 `N × lineSpace` 가 되는 것에 의존합니다. 수식은 맞지만 **SwiftUI 가 픽셀 그리드에 스냅하면 깨집니다.** 시뮬레이터 iOS 26.2 에서 0.00 이던 것이 실기기 iOS 27.0 beta 에서 0.5 로 나타났습니다 — **OS 판올림마다 재발할 구조**입니다. 수정 방향은 `VerseLayoutInput` 에 실측 높이를 additive 로 추가하고 빌더가 있으면 그것을 쓰는 것입니다 (Pass 2 의 band 모델은 `lineSpace` 유지 — reflow §9-2 무영향). **그대로 수정했습니다 — §20-14.**

**R15 — 계측이 값을 했습니다.** Phase 2 의 Δ 오버레이가 정확히 이 계열을 잡으라고 만든 것이고, 잡았습니다. 오버레이가 없었다면 "장 아래쪽에서 필기가 이상하다" 는 재현 어려운 제보로 왔을 것입니다. D9 중에 절별 Δ 프로파일 한 줄(`h[min max]` · `slope` · 샘플 절의 `top`)을 추가해 원인 판별에 썼습니다.

### 20-14. R13 종결 — 행 높이 실측을 레이아웃 입력으로 승격 · Δ 안전망 (rev.21)

`e98e4679`. 측정 파이프라인에서 **유일하게 예측이던 값**(행 높이)을 실측으로 바꿨습니다. 모델을 더 정교하게 만들지 않은 이유는 §20-13 의 구조적 논점 그대로입니다 — 빌더가 SwiftUI 의 픽셀 스냅을 모델링하는 한 OS 판올림마다 재발합니다.

| 변경 | 내용 |
|---|---|
| `VerseLayoutInput.measuredHeight` | additive optional. Pass 1 이 있으면 실측을 쓰고 없으면 기존 `topPadding + 줄 수 × lineSpace` 로 떨어진다. 실측은 행 전체를 잰 값이라 `topPadding` 을 이미 포함하므로 **이중 가산하지 않는다** |
| Pass 2 | 손대지 않았다. band 모델은 `lineSpace` 를 그대로 쓴다 — reflow(§9-2)의 band 폭과 같은 값이어야 한다 |
| `canvasFramesInRow` 의 높이 | **검증 전용 → 레이아웃 입력.** 재계산 트리거에 포함한다. **게이트 조건에는 넣지 않았다** — 아직 실측이 오지 않은 절은 예측식으로 떨어지므로 게이트가 늦게 열리지 않는다. 행 frame 은 원점만 쓰이므로 검증 전용 그대로다 |
| `LayoutDeltaVerdict` | 안전망. 계약은 §14 |

> **`fixedSize` 가 이 변경의 전제입니다.** 실측 높이를 레이아웃 입력으로 올리면 `layout → totalHeight → 호스트 높이 → 컬럼 → 행 높이` 가 닫힌 고리가 될 수 있습니다. ① 호스트 frame 높이는 `totalHeight` 가 아니라 **컬럼이 스스로 보고한 높이**이고 ② 컬럼은 R16 수정의 `.fixedSize(horizontal: false, vertical: true)` 로 제안된 높이를 먹지 않으므로 고리가 끊겨 있습니다. **제거하거나 우회하면 R16 이 되살아나는 동시에 이 입력이 순환합니다.**

#### 부작용 3건 — 반드시 알고 읽어야 합니다

1. **`frameDeltas.heightDelta` 가 구조적으로 0 이 됩니다.** (Pass 2 여유가 붙은 절만 예외이며, 그때는 정확히 `−extraBands × lineSpace`.) 높이 Δ 는 더 이상 독립 검증이 아니라 자기 자신을 검증합니다. 남는 독립 검증은 **`topDelta`** 이고, 그것이 `metrics`(`topInset`/`verseSpacing`/`bottomInset`)와 `leadingInset` 의 적재를 계속 검증합니다.
2. ⚠️ **Δ 가 R16 계열을 더 이상 검출하지 못합니다.** 호스트 제안이 행을 늘려도 레이아웃이 그 렌더를 따라가 예측 == 실측이 되기 때문입니다. **이번 세션에서 실증됐습니다** — `.fixedSize` 가 빠진 실기기 빌드가 장 전환 Δ 를 0.00 으로 표시했습니다. 자동 검출은 `ChapterCanvasControllerTesting.hostedColumnKeepsIdealHeightAndStaysAtTop` 하나뿐이고, 실기기에서는 HUD 의 `H`(totalHeight)를 **새 진입값과 비교**해야 합니다 (런북 §6-9).
3. **장 진입이 예측 → 실측 2회 빌드**가 됩니다. 편집 중 도착한 레이아웃은 §8-1 의 `pendingLayout` 이 흡수해 pencil-up 뒤에 적용됩니다. 절 수가 많은 장의 진입 비용은 D9-8 에서 확인 대상입니다.

#### 변이 테스트 — 7건 중 2건이 처음에 무력했습니다

통과만 하는 테스트는 회귀 테스트가 아니므로 변이를 하나씩 넣고 **실패하는지**를 봤습니다. 무력했던 두 건이 사각지대를 가리킵니다.

| 변이 | 결과 |
|---|---|
| 빌더 `measuredHeight ??` → 예측식 고정 | ✘ 22 |
| `recordCanvasFrameInRow` 높이 변화 반환 제거 | ✘ 6 |
| **`Display` 를 `isInputEnabled` 로 되돌림** | ⚠️ **처음엔 실패 0** → 보강 후 ✘ 4 |
| `hasReflowSlack` 예외 제거 | ✘ 4 |
| **`usesSingleCanvas` 가드 우회** | ⚠️ **처음엔 실패 0** → 보강 후 ✘ 4 |
| 장 전환 `layoutDelta = nil` 삭제 | ✘ 1 |
| 판정 전달 effect 삭제 | ✘ 5 |

- **`Display`** — `ChapterCanvasView.Display` 를 만드는 테스트가 **하나도 없었습니다.** 안전망이 `drawingGestureRecognizer.isEnabled` 까지 닿는 유일한 지점이 무방비였습니다. 리듀서 상태만 보는 테스트는 뷰 경계에서 끊깁니다 — §14 의 "SwiftUI 호스팅을 실제로 돌리지 않는 기하 테스트" 사각지대와 같은 계열입니다.
- **`usesSingleCanvas`** — 테스트가 `CarveDetailFeature().reduce(into:)` 를 **직접 호출해 effect 를 버렸습니다.** 배선을 지워도 상태가 안 변하니 통과했습니다. **`reduce` 직접 호출로 배선을 검증하는 테스트는 전부 같은 결함을 가집니다** — 실제 `Store` 로 태워야 합니다.

#### 검증

- 시뮬레이터 전량 **285 통과** (Swift Testing 283 + XCTest 2, 기준선 267 → 285) · SwiftLint 0.
- 실기기 (iPad mini A17 Pro / iOS 27.0 beta / `-SingleCanvas -ChapterLayoutOverlay`): 시편 119편 Δ **87.50 → 0.00** · `slope` +0.500 → **+0.000/절** · `top` v1~v176 전부 0.00 · 장 전환 4건 `totalHeight` **5138.0 동일**(새 진입 == 창세기 1→2 == 시편 119편→창세기 2) · 정상 상태에서 **`guard OPEN`** (오탐 없음).


### 20-15. D9 H — 회전 표시 결함 원인 분리 (rev.23)

2026-09-08, iPad mini(A17 Pro) / iPadOS 27.0 beta `24A5408d` / USB / Xcode 26.3. **원인을 좁힌 세션**이고 수정은 다음 rev(§20-16)입니다.

**남길 결론 셋** — 나머지 경위는 [분석 문서](./single-canvas-rotation-display-investigation.md) §2~§3 과 git 이력에 있습니다.

1. **데이터는 도착했는데 화면만 낡았습니다.** 가로→세로→가로에서 Store/전달/applied 세대가 2→3→4 로 일치했고 44개 획의 경계·변환·seed·point 수도 최종 디코딩과 일치했지만 화면은 이전 합성 상태였습니다.
2. **표시 교체 방식만 바꿔도 정상화됩니다.** 일반 redraw 와 같은 drawing 재대입은 무효, 빈 drawing 경유 복원과 같은 공개 속성의 새 `PKStroke` 생성은 정상화 → 기존 획 재사용에 따른 PencilKit 렌더 캐시/표시 갱신 경로가 유력합니다 (Apple 내부 구현은 확인하지 않았습니다).
3. **계측을 등치 비교하지 마십시오.** `legInk` 는 legacy 절만의 병합 전 값이라 전체 `canvas.drawing.bounds` 와 다릅니다. `Δ max 0.00` · `compose SYNC` · 렌더 완료 콜백은 **어느 것도 화면의 최신 표시를 증명하지 못합니다.**

당시 기준선 296. 조사에 쓴 opt-in 인자 `-CanvasFreshStrokesOnApply` 는 §20-16 에서 사라졌고, 지금 남은 `-CanvasReuseStrokesOnApply` 는 **의미가 정반대**(수정을 끄는 opt-out)입니다 — [CLI 절차](./device-debugging-cli.md).

### 20-16. D9 H 정식 수정 — 표시용 획 재구성 (rev.24)

`ef053111`. 회전 뒤 이전 필기가 표시되는 결함의 처방을 Debug 실행 인자 뒤에서 **기본 경로로 승격**했습니다. `ChapterCanvasController.applyDrawing` 의 **디코딩 후 · `canvas.drawing` 대입 직전**에서 같은 공개 속성으로 획을 새로 만들어 넣습니다. 좌표·저장 데이터·Feature·코덱·DB 는 손대지 않았고, 실행 위치는 `renderedRevision` 이 실제로 바뀔 때 안 그대로입니다.

**속성 감사 (iOS 26 SDK).** `PKStroke` 의 값 지정 가능 속성은 `ink`·`path`·`transform`·`mask`·`randomSeed` 다섯이고 전부 그대로 넘깁니다. `renderBounds`·`maskedPathRanges`·`requiredContentVersion` 은 읽기 전용 파생값이라 지정 수단이 없습니다. **손실되는 지정 가능 속성은 없습니다.** `path` 를 통째로 넘기므로 `creationDate` 와 control point 가 유지되고, **`StrokeIdentityKey` 가 쓰는 `randomSeed`+`creationDate`+`path.count` 셋이 모두 보존**되어 소유권 승계가 유지됩니다.

> ⚠️ **알려진 부작용 — 지우개 조각 절이 1회 재저장됩니다.** `mask != nil` 인 획을 재구성하면 파생값 `maskedPathRanges` 가 재계산되며 미세하게 달라집니다(실측 차이 약 6.7e-4). `StrokeContentSignature` 는 반올림을 금지하므로(§7-2 — D7 재발 방지) 그 절이 한 번 dirty 로 잡혀 `.replace` 가 한 번 나갑니다. **저장 내용(획 수·좌표·`StrokeIdentityKey`·`ownership.map`)은 원본과 동일하고**, 그 결과로 다시 합성·재구성하면 mutation 이 없는 **고정점**이라 회전마다 되풀이되지 않습니다. 다만 `updateDate` 가 바뀌므로 히스토리 순서·주간 통계에 영향이 있을 수 있습니다.

**실기기 A/B 로 인과를 확인했습니다** (2026-09-08, iPad mini A17 Pro / iPadOS 27.0 beta). 인자 없이 가로↔세로 **3왕복 전부 정상**, `-CanvasReuseStrokesOnApply`(Debug opt-out)로 **결함 재현**. **계측은 두 실행이 구분되지 않고 화면 판정만 갈립니다** — `store/delivered/applied` 일치, canvas bounds 기대값과 동일, `offset`·`zoom`·`transform` 동일, 컨트롤러 동일. 상세는 [D9 H 분석](./single-canvas-rotation-display-investigation.md) §3.

**이것이 계측의 한계를 다시 보여줍니다.** `Δ max` · `compose SYNC` · `org` · `legInk` · `applied` · 렌더 완료 콜백 — 전부 "값이 도달했는가" 만 말하고 "화면이 그것인가" 는 말하지 못했습니다. 이 결함은 **사람이 화면을 봐야만** 판정됩니다. 시뮬레이터 테스트도 데이터·계약만 고정하고 PencilKit 의 화면 캐시 자체는 검출하지 못합니다.

**아직 종결이 아닙니다.** §6 의 잔여 검증 — 편집·저장 왕복(새 필기·부분 지우개·undo/redo·장 이동·재실행 복원·N-Canvas 왕복), 긴 장(시편 119편) 재구성 비용, 스크롤 중 회전, 글꼴/행간 변경, 좌우 필사 위치 — 이 남아 있습니다. **E-4 재판정도 그 글꼴 변경 확인에 달려 있습니다** (런북 §8-7).
