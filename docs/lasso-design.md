# 올가미 도구 설계 (단일 Canvas)

작성일: 2026-09-16. 대상 브랜치 `feat/lasso`. 기반은 [단일 Canvas 전환 설계](single-canvas-design.md)이며,
이 문서는 그 설계의 **§7 소유권**에 규칙 하나를 더하고 도구 한 칸을 여는 범위만 다룬다.

## 1. 범위 — 정한 것과 정하지 않은 것

| 결정 | 값 | 날짜 |
|---|---|---|
| 동작 | **선택 + 이동만.** 삭제 · 복제 · 복사 · 붙여넣기 · 크기 조절은 넣지 않는다 | 2026-09-16 |
| 구현 | **네이티브 `PKLassoTool`.** 자체 올가미는 만들지 않는다 | 2026-09-16 |
| 절 경계를 넘는 이동 | **허용하고 놓인 절로 재귀속한다** | 2026-09-16 |
| 도구 선택의 지속 | 앱 실행 동안만 유지한다(`.inMemory`). 재기동하면 펜 | 2026-09-16 (이 문서) |

삭제를 넣지 않는 것이 이 설계의 크기를 결정한다 — 삭제 · 복사는 PencilKit 편집 메뉴가 유일한 표면인데,
그 메뉴는 R25 사고(§8-7)로 **지금 전부 걷어내고 있다**. 이동만이면 그 정책을 그대로 둔 채 도구만 바꾸면 된다.

## 2. 지금 코드의 자리

| 자리 | 상태 |
|---|---|
| 팔레트 올가미 버튼 | **이미 있다.** 아이콘(`CarveIcon.lasso`)까지 있고 `.disabled(true)` + 빈 동작 — `PencilPalatteView.swift:101` |
| 디자인 | 도구 팔레트 3번째 칸으로 확정 (`design/ui-design-direction.md` §2 · §6-1). 열린 결정은 「올가미 식별성(아이콘 교체/유지)」 하나 (§8-3) |
| 도구 표현 | `PencilPalatte.pencilType` 하나뿐이고 `.monoline` 이 **지우개 sentinel** 이다. 올가미는 잉크 종류가 아니라 여기에 낄 수 없다 |
| 도구 전달 | 팔레트 → `@Shared(.appStorage("pencilConfig"))` → `ChapterCanvasView.tool(for:)` → `Configuration.tool` → `canvas.tool`. 스토어를 거치지 않는다 |
| 편집 메뉴 | `ChapterCanvasController.suppressPencilKitEditMenus()` 가 캔버스 **하위 뷰**의 `UIEditMenuInteraction` · `UIContextMenuInteraction` 을 매 레이아웃마다 제거한다 (R25) |

SDK 확인(iPhoneSimulator 26.2 헤더):

- `PKLassoTool` 의 공개 API 는 `init()` 뿐이다. **선택을 읽거나 바꾸는 API 가 없다** — 그래서 "우리 메뉴" 나 "이 절 안에서만 선택" 은 네이티브로 불가능하다.
- `PKCanvasViewDelegate` 의 `canvasViewDidBeginUsingTool` 주석은 "selecting, drawing, or erasing" 이다 — 선택도 도구 사용이므로 §8-1 편집 계약이 그대로 걸린다(실동작은 §5 L-3 에서 확인한다).

## 3. 제약 — 왜 도구 한 칸이 아닌가

획은 **시작한 절**에 귀속되고(§7-1 U1) 절별 행에 **첫 밑줄 원점** 기준으로 저장된다(§8-2).
승계 규칙 1번은 `StrokeIdentityKey`(seed · 생성 시각 · point 수)가 같으면 기존 owner 를 그대로 물려준다(§7-3).

올가미 이동은 **획의 위치를 바꾸는 유일한 입력**이고, 옮겨도 identity 는 변하지 않는다.
그대로 두면 3절 잉크를 5절 자리로 옮겼을 때 이렇게 된다.

```
저장   3절 행에, 3절 첫 밑줄 기준의 큰 offset 으로 들어간다
표시   지금은 5절 자리에 보인다 (좌표가 절대값이므로)
레이아웃 변경  글자 크기 · 회전 뒤 그 잉크는 5절이 아니라 3절을 따라 움직인다 (§9 reflow 는 owner 절의 밑줄 기준이다)
절 단위 기능   3절 「지우기」가 5절 자리의 잉크를 지우고, 3절 이미지 · 위젯에 그 잉크가 들어간다
```

즉 **재귀속 규칙이 이 기능의 본체이고**, 도구 전환은 부속이다.

## 4. 설계

### 4-1. 도구 상태 — sentinel 을 늘리지 않는다

`pencilType` 의 `.monoline` sentinel 은 그대로 둔다. 올가미는 **우선하는 플래그 하나**로 표현한다.

```swift
@Shared(.inMemory("isLassoSelected")) var isLassoSelected: Bool = false
```

| 값 | 도구 |
|---|---|
| `isLassoSelected == true` | 올가미 |
| `false` + `pencilType == .monoline` | 지우개 (현행) |
| `false` + 그 밖 | 잉크 (현행) |

- 우선순위를 한 곳(`tool(for:isLasso:)`)에만 두므로 진실이 갈라지지 않는다.
- appStorage 스키마를 건드리지 않는다 — `PencilPalatte` 에 필드를 더하면 기존 JSON 디코드가 실패해 사용자의 펜 설정이 초기화된다.
- `.inMemory` 인 이유: 올가미로 둔 채 앱을 닫고 다음 날 펜슬을 대면 **글씨가 안 써진다**. 지우개와 달리 화면에 남는 흔적도 없어 고장으로 읽힌다.
- 팔레트에서 펜 · 지우개를 누르면 `isLassoSelected = false` 로 내린다. `pencilType` 은 건드리지 않으므로 올가미에서 펜으로 돌아오면 **마지막 잉크**로 복귀한다(지금 지우개 → 펜 규칙과 같다).
- 선택 표시: 펜 `!isErasing && !isLasso`, 지우개 `isErasing && !isLasso`, 올가미 `isLasso`. 접힌 팔레트의 캡션(「펜 · 0.5 mm」)에 올가미 문구를 더한다.

### 4-2. 캔버스 도구 매핑

```swift
static func tool(for config: PencilPalatte, isLasso: Bool) -> PKTool {
    if isLasso { return PKLassoTool() }
    return config.pencilType == .monoline
        ? PKEraserTool(.bitmap)
        : PKInkingTool(config.pencilType, color: config.lineColor.color, width: config.lineWidth)
}
```

입력 게이트(§6-2)는 `drawingGestureRecognizer.isEnabled` 하나이고 올가미도 그 인식기를 쓰므로 **레이아웃 완성 전에는 올가미도 닫힌다** — 추가 게이트가 필요 없다.

### 4-3. 편집 이유

`EditReason` 에 `.lasso` 를 더하고, 컨트롤러가 `canvasView.tool is PKLassoTool` 로 판정한다
(현재는 `tool is PKEraserTool ? .erase : .ink`). 지금 이 값을 분기하는 곳은 없고 진단 · 로그용이다 —
저장 계산은 아래 4-4 의 **앵커 이동**으로 판정하지 이유로 하지 않는다. undo/redo 로 되돌린 이동도 올바르게 처리되어야 하기 때문이다.

### 4-3-a. 이동에는 `editBegan` 이 오지 않는다 (실측)

| 조작 | delegate 호출 |
|---|---|
| 올가미로 **선택** | `didBeginUsingTool` → `didEndUsingTool` (`drawing` 변화 없음 → 0.35 s 뒤 `editCancelled`) |
| 선택을 **이동** | `drawingDidChange` **만**. 도구 시작 · 종료 호출이 없다 |

저장은 정상이다 — `editEnded` 는 `isEditing` 을 전제하지 않고, 실측에서도 이동이 DB 까지 갔다.
문제는 이동하는 **동안 `isEditing` 이 false** 라는 것이다. §8-1 이 그 구간에 보류하는 것(레이아웃 · `columnOrigin` ·
복원 재합성)이 이동 도중에 적용되면 `canvas.drawing` 이 제스처 한가운데서 교체된다.

**결정 — 올가미 편집의 첫 `drawingDidChange` 에서 `editBegan` 을 함께 낸다.** 컨트롤러가 이미 도구를 알고 있고
(4-3), 닫는 쪽은 기존 trailing `editEnded` 가 그대로 한다. 선택만 하고 마는 경우는 `drawing` 이 바뀌지 않으므로
이 경로에 오지 않는다.

### 4-4. 소유권 재귀속 — §7-3 규칙 1의 조임 ★

```
1'. IdentityKey 일치 + 앵커 불변  → 기존 owner 승계        (현행 1번)
1''. IdentityKey 일치 + 앵커 이동  → 규칙 4로 보낸다        (신규)
2 · 3 · 4                          → 현행 그대로
```

앵커는 §7-1 과 같은 점이다 — **첫 control point 에 `transform` 을 적용한 캔버스 좌표**(`StrokeOwnershipResolver.anchorPoint`).
비교 대상은 같은 세대의 `previousDrawing` 에 있는 같은 IdentityKey 획들의 앵커 집합이다.

이 규칙이 안전한 근거는 이미 측정돼 있다.

| 경로 | 앵커 | 결과 |
|---|---|---|
| `.bitmap` 지우개 | 조각이 원본 control point 를 그대로 물려받는다 (S1-2 · S1-4 · §19-2 실측) | 불변 → 승계 유지 |
| reflow | `mutations` 경로를 타지 않는다 (§9-4 비파괴) | 비교 자체가 일어나지 않는다 |
| 표시용 재구성 (D9 H) | `path` · `transform` 을 그대로 옮긴다 | 불변 |
| 올가미 이동 | 위치가 바뀐다 | **이동 → 재귀속** |
| 그 이동의 undo | 원래 위치로 돌아온다 | **이동 → 원래 절로 재귀속** |

- 임계값을 두지 않는다. "움직였는가" 는 같은 세대 안의 좌표 동일성 비교이고, §7-3 이 경계하는 "근거 없는 마법 상수" 를 만들지 않는다.
  L-2 에서 건드리지 않은 획의 `local` · `transform` 은 소수점까지 그대로였고 움직인 획만 정확히 이동량만큼 달라졌다 —
  지금은 ε 가 필요하다는 근거가 없다. 잡음이 관측되면 그때 근거와 함께 넣는다.
- 재귀속의 목적지는 규칙 4 그대로다: 첫 control point → `captureRect` → 절. 캔버스 밖이면 기존 `adoptUnownedStrokes`(U8)가 클램프한다.
- **올가미는 획을 쪼개지 않는다** (L-1 실측). 획의 절반만 감싸도 획 전체가 선택되고 `path` · `mask` 는 그대로다. 그래서 잉크 획에서는 identity 와 선택 단위가 1:1이다.
- 남는 경우는 **bitmap 지우개가 이미 쪼개 둔 조각**뿐이다. 조각들은 IdentityKey 를 공유하므로(§7-2) 소유권을 나눌 수 없고, 조각 하나를 옮기면 그룹 전체가 새 절로 간다. 잉크의 절대 좌표는 그대로라 화면은 달라지지 않고 다음 레이아웃 변경 때 함께 움직인다. 그룹을 쪼개려면 소유권 모델 자체를 바꿔야 하므로 **알려진 한계로 둔다.**

### 4-5. 저장 — 변경 없음

떠난 절과 도착한 절이 모두 dirty 가 되고(§8-2 ContentSignature 집합 비교), 절별 **완전한** 획 집합이
각자의 첫 밑줄 원점으로 localize 되어 한 batch(원자적, §8-6)로 나간다.

```
떠난 절    남은 획 있음 → replace / 없음 → clear
도착한 절  활성 행 있음 → replace / 없음 → create (rowID 선발급 → issuedRowIDs)
```

코덱 · 큐 · 세대 · flush 는 손대지 않는다.

### 4-6. undo — 변경 없음

PencilKit 이 이동을 자기 `undoManager` 에 등록하므로 팔레트의 실행 취소 · 다시 실행이 그대로 동작한다(§9-5). 등록 여부는 §5 L-4 에서 확인한다.

### 4-7. 편집 메뉴 — 변경 없음 (억제 유지)

이동만 제공하므로 PencilKit 편집 메뉴를 열 이유가 없다. `suppressPencilKitEditMenus()` 와 그 회귀 테스트를
**그대로 둔다** — R25 의 원인(우리 절 메뉴가 PencilKit 메뉴로 교체되어 오탭이 「전체 선택」으로 이어지던 경로)이 닫힌 채 유지된다.

선택 해제는 선택 밖 탭으로 한다(PencilKit 기본). 절 롱프레스 메뉴는 손가락 전용이고 올가미는 필기 입력이라 서로 겹치지 않는다.
⚠️ 다만 **올가미 완료 시점에 PencilKit 이 메뉴를 새로 붙이는지**는 확인해야 한다 (§5 L-5).

### 4-8. N-Canvas 롤백 경로

`CanvasView`(flag off)는 올가미를 지원하지 않는다 — 절마다 캔버스가 따로라 장 단위 선택·이동이 성립하지 않는다.
팔레트의 `isLassoAvailable` 은 `delegatesUndoToCanvas` 와 같은 자리에서 `CarveDetailFeature` 가
`state.usesSingleCanvas` 로 정하고, 버튼은 그 값으로 잠긴다. `selectLasso` 리듀서도 같은 값을 가드한다.

**flag 를 끄고 돌아온 장에서는 선택까지 내린다.** 버튼만 잠그면 이전에 고른 올가미가 `.inMemory` 에 남아
N-Canvas 에서 펜을 대도 아무 일도 일어나지 않는 것처럼 보인다.

## 5. 실측 결과 (L0 — 2026-09-16, 시뮬레이터)

iPad mini (A17 Pro) · iOS 26.2 전용 기기(`carve-lasso-probe`), Debug 빌드 + `-LassoProbe`,
`allowFingerDrawing` 을 켜고 손가락 touch_path 로 조작했다. 창세기 1장에 1절 · 2절에 획을 하나씩 긋고
1절 획을 3절 자리로 끌어내린 기록이다. 계측기는 `ChapterCanvasLassoProbe`(읽기 전용).

| # | 질문 | 결과 |
|---|---|---|
| L-1 | 부분 선택이 획을 자르는가 | **아니다.** 획의 오른쪽 절반만 감싸도 **획 전체**가 선택돼 움직였다. `pts` 불변 · `mask=nil` 유지 |
| L-2 | 이동이 `transform` 인가 `path` 인가 | **`transform` 만.** 첫 control point(`local`)는 그대로고 `t.ty` 가 0 → 327 로(대각 이동은 `tx=62 ty=120`) 바뀌었다 |
| L-3 | 편집 계약이 걸리는가 | **선택**에는 `didBegin/didEndUsingTool` 이 온다. **이동**에는 `drawingDidChange` 만 온다 (→ 4-3-a) |
| L-4 | undo 에 등록되는가 | **된다.** 실행 취소가 `t.ty` 를 327 → 0 으로 정확히 되돌렸고 `canRedo` 가 켜졌다 |
| L-5 | 편집 메뉴가 뜨는가 | **안 뜬다.** 모든 사건에서 하위 뷰의 편집 · 컨텍스트 메뉴 수가 `0` 이고, 선택 안에서 1.2 초 롱프레스해도 메뉴가 없었다 |
| L-6 | 도구 재대입이 선택을 지우는가 | 재대입 2회를 관측했고 **선택은 유지**됐다 (관측 2건, 이동 제스처 **도중**의 재대입은 만들지 못했다) |

### 5-1. 원본 기록

```
#3  drawingDidChange  tool=PKInkingTool  strokes=1
   [0]* seed=2207437656 created=…570.942 pts=8 local=(445.00,118.50) anchor=(445.00,118.50) t=[1 0 0 1 0.00   0.00]
#9  drawingDidChange  tool=PKLassoTool   strokes=2        ← 1절 → 3절 자리로 이동
   [0]* seed=2207437656 created=…570.942 pts=8 local=(445.00,118.50) anchor=(445.00,445.50) t=[1 0 0 1 0.00 327.00]
#10 drawingDidChange  tool=PKLassoTool   canRedo=true     ← 실행 취소
   [0]* seed=2207437656 created=…570.942 pts=8 local=(445.00,118.50) anchor=(445.00,118.50) t=[1 0 0 1 0.00   0.00]
#13 drawingDidChange  tool=PKLassoTool   strokes=2        ← 2절 획의 오른쪽 절반만 올가미 → 대각 이동
   [1]* seed=3596494425 created=…588.957 pts=8 local=(445.00,258.00) anchor=(507.00,378.00) t=[1 0 0 1 62.00 120.00]
```

`StrokeIdentityKey` 의 세 성분(`seed` · `created` · `pts`)이 이동 전후로 **전부 같다.** 즉 현행 승계 규칙 1번은
옮긴 획을 원래 절에 그대로 묶어 두며, 앵커(`local` × `transform`)만 정확히 이동량만큼 달라진다 — 4-4 의 판정 기준 그대로다.

### 5-3. L3 — 고친 뒤 같은 절차 (2026-09-16)

L1 · L2 를 넣고 **컨테이너를 비운 뒤 같은 조작**을 반복했다. (본문 모양은 iCloud KVS 에서 복원돼 29 pt 로 시작했다 —
재설치로도 남는다는 기존 관측과 같다.)

| 조작 | 결과 |
|---|---|
| 1절 획을 2절 자리로 이동 | 1절 행 **비워짐**(`clear`) · 2절 행에 두 획(`replace`) |
| 그 획을 다시 3절 자리로 이동 | **3절 행이 새로 생김**(`create`, `rowUUID 709BD016…`) · 2절은 자기 획만 |
| 글자 크기 변경(reflow) | 옮긴 획이 **3절에 그대로 남고** 2절 획과 겹치지 않는다 — 5-2 에서 겹쳤던 그 자리다 |
| 앱 재기동 | 두 획 모두 같은 자리 (저장 정착 확인) |
| 재기동 직후 도구 | **펜**. 올가미는 지속되지 않는다 (§4-1 의도대로 — 손가락 획이 잉크로 그려졌다) |

```
sqlite> select ZVERSE, length(ZLINEDATA) from ZBIBLEDRAWING;
1|(비어 있음)     ← 떠난 절
2|420
3|420            ← 놓인 절. 5-2 에서는 이 행이 없었다
```

⚠️ 이 확인은 **시뮬레이터 · 손가락 입력**이다. 실기기와 Apple Pencil, 그리고 이동 제스처 **도중**의 도구 재대입(L-6)은 아직 보지 못했다.

### 5-2. 결함을 실제로 재현했다

재귀속 규칙이 **없는** 상태(현행 코드)로 1절 획을 3절 자리에 놓고 저장한 뒤 확인했다.

```
sqlite> select ZVERSE, ZDRAWINGVERSION, length(ZLINEDATA) from ZBIBLEDRAWING;
1|3|420        ← 3절 자리에 보이는 획이 여기 들어 있다
2|3|420
              ← 3절 행은 없다
```

이어서 **본문 설정에서 글자 크기를 20 → 29 pt 로** 올리자(레이아웃 변경 → §9 reflow), 3절에 놓았던 획이
자기 소유 절(1절)을 따라 올라와 **2절 잉크와 같은 줄에 겹쳤다.** 사용자가 놓은 자리도, 원래 자리도 아니다.
§3 이 예측한 그대로이며, 이 설계가 막으려는 것이 이 결과다.

## 6. 테스트

| 파일 | 항목 | 상태 |
|---|---|---|
| `StrokeOwnershipLassoTesting` (신규) | 앵커 이동 → 놓인 절 재귀속 / 되돌리기 → 원래 절 / 같은 절 안 이동 → 그대로 / 겹침(규칙 3) 대신 앵커 / 캔버스 밖 → owner 없음 / 지우개 조각은 앵커 불변이라 승계 유지 | ✅ 6건 |
| `DrawingCodecLassoTesting` (신규) | 도착 절에 행이 없으면 `clear` + `create`(rowID 선발급) / 행이 있으면 `replace` 로 두 획 합침 / 같은 절 안 이동은 한 절만 `replace` | ✅ 3건 |
| `ChapterCanvasLassoTesting` (신규) | 도구 매핑(올가미 우선) · `editReason` 매핑(히스토리 우선) / 이동이 `editBegan` 을 한 번만 합성하고 `editEnded(.lasso)` 로 닫는다 / 펜 획에는 합성하지 않는다 | ✅ 4건 |
| 〃 (같은 파일, 팔레트) | 올가미 선택이 잉크 설정을 보존 / 펜 · 지우개가 올가미를 해제 / 롤백 경로에서 선택 불가 | ✅ 3건 |
| `ChapterCanvasMenuSuppressionTesting` | 변경 없음 — 억제가 유지되는지 회귀로 확인 | ✅ 그대로 통과 |

검증은 CLI 로 한다(AGENTS.md).

```
xcodebuild test -scheme CarveFeatureTest -destination 'iPad mini (A17 Pro), OS=26.2'
  L0 직후  284 통과 · 실패 0
  L1 직후  293 통과 · 실패 0   (+9)
  L2 직후  300 통과 · 실패 0   (+7)
```

`xcodebuild build -scheme CarveApp` 도 성공한다.

**음성 대조.** 재귀속 규칙을 끄면(`hasMoved` 를 `false` 로) L1 테스트 9건 중 **6건이 깨진다.**
4-3-a 의 합성도 마찬가지로 확인됐다 — 편집 구간이 열리지 않는 상태에서는 `editBegan` 이 1회에 머물러
"이동이 편집 구간을 연다" 가 실패한다(구현 중 실제로 그 실패를 봤다).
나머지 3건(같은 절 안 이동 2건 · 지우개 조각 승계 1건)은 규칙과 무관하게 통과해야 하는 항목이고 실제로 통과했다 —
"바뀌면 안 되는 것" 쪽 가드가 공허하지 않은지도 같이 확인한 셈이다.

```bash
mise x -- tuist generate --no-open
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace \
  -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=26.2'
```

## 7. 이행 단계

| 단계 | 내용 | 산출 |
|---|---|---|
| L0 | §5 실측 (L-1 ~ L-6) | ✅ **완료 (2026-09-16).** 설계를 뒤집는 결과는 없었고 4-3-a 가 추가됐다 |
| L1 | 소유권 재귀속 규칙 + 단위 테스트 | ✅ **완료 (2026-09-16).** `StrokeOwnershipResolver` 규칙 1'' + 테스트 9건. 음성 대조로 6건이 규칙에 실제로 매달려 있음을 확인 |
| L2 | 도구 상태 · 매핑 · 팔레트 활성화 · `EditReason.lasso` · 4-3-a `editBegan` · 4-8 롤백 가드 | ✅ **완료 (2026-09-16).** 도구 전환은 L0 에서, 4-3-a · 4-8 과 테스트 7건이 여기서 |
| L3 | 시뮬레이터 · 실기기 시나리오 | 🔶 **시뮬레이터 완료 (2026-09-16, §5-3).** 이동 → 저장 → reflow → 재기동까지 확인. **남은 것: 실기기 · Apple Pencil, 이동한 절의 「지우기」 · 절 이미지 · 위젯 대상 확인, L-6** |

## 8. 위험과 한계

| 항목 | 내용 |
|---|---|
| 조각 그룹 분할 불가 | 4-4 마지막 문단. **지우개가 쪼개 둔 조각**에만 남는다 — 올가미 자체는 획을 쪼개지 않는다(L-1) |
| 이동 도중의 레이아웃 적용 | 4-3-a 의 `editBegan` 합성으로 막는다. 합성 전에는 글자 크기 · 회전이 제스처 한가운데 끼어들 수 있다 |
| 팔레트 선택 표시 | 올가미 칸의 선택 배경이 유리 표면 위에서 옅다. 색 외 구분은 있으나 대비는 DESIGN-1 에서 본다 |
| 잉크가 절 사이 여백에 놓일 때 | `captureRect` 는 빈틈 없이 장을 나누므로 소유자는 항상 정해진다(경계 위의 점은 아래 절). 다만 사용자가 의도한 절과 다를 수 있다 |
| 이동 뒤 reflow | 놓인 절 기준으로 밑줄에 재배치되므로 절의 줄 구성이 다르면 위치가 미세하게 달라진다. §9 정책 그대로이며 새로 생기는 문제는 아니다 |
| 삭제 부재 | 올가미로 묶어 지우기는 지금 범위 밖이다. 필요해지면 편집 메뉴를 도구별로 여는 설계를 따로 쓴다(R25 회귀 시험 포함) |
| 손가락 필기 설정 | `allowFingerDrawing` 이 켜져 있으면 손가락이 올가미를 그린다. 스크롤과의 관계는 현행 필기와 동일하다 |

## 9. 열린 결정

| 결정 | 선택지 | 막는 것 |
|---|---|---|
| 올가미 아이콘 식별성 | 교체 / 유지 | `design/ui-design-direction.md` §8-3 의 기존 항목. 이 설계는 어느 쪽이든 영향받지 않는다 |
| 첫 사용 안내 | 도움말(HELP)에 한 줄 넣을지 | 기능 완료 후 문구 확정 |
