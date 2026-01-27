
# Navigation Rules (Carve)

## Goal
- **Feature 내부 네비게이션은 Feature 내부에서 완결**한다.
- **Feature 간 네비게이션은 App 모듈(Composition Root)에서 단일하게 조립/제어**한다.
- App 모듈은 TCA의 **트리 기반(root)** + **스택 기반(path)** 네비게이션으로 앱 전환을 구성한다.

---

## Core principles
1) **Intra-feature**: 내부 네비게이션은 Feature가 책임지고, 외부로 노출하지 않는다.
2) **Inter-feature**: Feature 간 이동은 AppCoordinator가 root/path를 조작하여 처리한다.
3) Feature가 외부로 전달할 것은 “화면 전환”이 아니라 **이동 요청 이벤트(event)** 이다.
4) AppCoordinator는 child 이벤트를 관찰해 **root 교체 또는 path push/pop**만 수행한다.

---

## Navigation boundaries

### Intra-feature navigation (Feature 내부)
- 같은 Feature 안에서 발생하는 화면 이동(탭, 시트, 내부 push 등)은 **해당 Feature의 State/Action/Reducer에서 완결**한다.
- 외부(AppCoordinator/상위 Feature)는 Feature 내부 화면 구조를 **알 필요가 없어야 한다**.
- 외부로 알려야 하는 경우는 “destination”이 아니라 **의미 있는 이벤트**로 표현한다.


### Inter-feature navigation (Feature 간)
- Feature 간 이동(예: Carve → Settings, Carve → Chart)은 **App 모듈**에서만 처리한다.
- 각 Feature는 “어디로 이동할지”를 직접 결정하지 않고, **이동 요청 이벤트만 방출**한다.
- AppCoordinator는 이동 요청 이벤트를 받아 `root` 또는 `path`를 변경한다.

---

## Preferred architecture: Tree + Stack

### Tree-based root
- 앱의 큰 흐름(예: Launch → Main)을 나타낸다.
- `@Presents var root` + `PresentationAction`으로 관리한다.

### Stack-based path
- 루트 화면 위에 쌓이는 push 목적지를 나타낸다.
- `StackState<Path.State>` + `StackActionOf<Path>`로 push/pop을 관리한다.

---

## What can be exposed (Feature 외부로 허용되는 것)
Feature 내부의 다음 항목은 외부 노출을 피한다.
- 내부 path/state 구조
- UIKit/PencilKit 타입
- persistence(SwiftData) 세부 구현

---

## Reducer responsibilities

### AppCoordinator responsibilities
- child 이벤트를 감지해 **root 교체** 또는 **path push/pop** 수행
- 이동 후 후속 동작이 필요하면 `Effect.send(...)` 형태로 전달(필요한 경우에만)

### Child Feature responsibilities
- UI 상호작용을 Action으로 모델링
- 자신의 내부 네비게이션/state를 관리
- Feature 간 이동이 필요할 때는 **이동 요청 이벤트만 방출**

---

## Testing checklist
- Feature 내부 네비게이션:
  - 해당 Feature의 Reducer 테스트에서 state 변화로 검증한다.
- Feature 간 네비게이션:
  - AppCoordinator Reducer 테스트에서
    - 특정 child 이벤트 입력 → `root` 또는 `path` 변화가 맞는지 검증한다.
    - push/pop 이후의 후속 액션(send)이 있다면 함께 검증한다.

---

## Notes (iPad)
- iPad는 회전/리사이즈가 잦으므로, 네비게이션 상태(root/path)는 예측 가능하게 유지되어야 한다.
- 좌표/레이아웃 이슈는 `overview.md`의 Geometry 원칙 및 `pencilkit.md`의 기준 좌표계 규칙을 따른다.
