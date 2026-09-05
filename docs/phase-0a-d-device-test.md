# Phase 0A-D 실기기 검증 런북

> 상태: **실행 대기 (미실행)** · 대상 문서: [single-canvas-design.md](./single-canvas-design.md) §11 / §13 / §16 / §18 / §19
> 대상 기기: **iPad mini (A17 Pro)**, **iPad Air (M2)** — 둘 다 60Hz · 8GB (§13 사각지대)
> 이 문서를 만들면서 **소스·프로젝트·signing 을 변경하지 않았고, 빌드·테스트도 실행하지 않았습니다.**
> 아래 명령은 **이 머신에서 실제로 실행하거나 `--help` 로 조회해 확인한 것**과
> **기기가 연결돼야만 확인 가능한 것**을 표기로 구분했습니다.

---

## 0. 이 런북을 읽는 방법

### 표기 규칙

| 표기 | 뜻 |
|---|---|
| ✅ **확인함** | 이 머신에서 실제로 실행했거나 `--help` 로 하위 명령·옵션 존재를 조회함 |
| 🔌 **기기 연결 후 확인** | 명령 형태는 확인했으나, 결과는 실기기가 붙어야 알 수 있음 |
| ❓ **미확인** | 확인할 수단이 없었음. 추측하지 않고 그대로 남김 |
| ⚠️ | 되돌릴 수 없는 손실 가능성 |

### 절 번호 참조 규칙

이 문서와 설계 문서의 절 번호가 겹칩니다. 다음과 같이 구분합니다.

| 표기 | 가리키는 곳 |
|---|---|
| `§11`, `§13`, `§18-3`, `§19-5` 처럼 **이 문서에 없는 번호** | [single-canvas-design.md](./single-canvas-design.md) |
| `§2-4`, `§8-3` 처럼 **이 문서에 있는 번호** | 이 문서 |
| **`설계 §7-3`** 처럼 `설계` 를 붙인 것 | 번호가 겹칠 때 설계 문서 쪽 |
| **`이 문서 §7`** | 번호가 겹칠 때 이 문서 쪽 |

### 판정 3분류

| 분류 | 정의 |
|---|---|
| **지금 가능** | 코드 변경 없이 현재 저장소 상태의 빌드로 검증까지 끝낼 수 있음 |
| **부분 가능** | 현재 구조(N-Canvas)에 대한 baseline·현상 확인만 가능. §11 통과 기준 판정은 S4 spike 구현 후 |
| **차단됨** | 선행 Phase 산출물이 저장소에 없어서 검증 대상 자체가 존재하지 않음 |

---

## 1. 사전 상태 점검

### 1-1. 저장소가 지금 어떤 상태인가 (근거 확인 완료)

| 확인 항목 | 결과 | 근거 |
|---|---|---|
| 새 아키텍처 착수 여부 | **미착수.** `ChapterLayout` / `ChapterCanvasFeature` / `DrawingCodecClient` / `DrawingRepository` 없음 | 설계 문서 rev.9 머리말과 동일 |
| 스키마 | **V3까지.** V4 없음 | `Domain/Domain/Sources/SwiftData/Model/` = `DrawingSchemaV1/V2/V3.swift` 3개 |
| S4 스크롤 spike | **미구현.** `CanvasScrollSpike` 계열 파일 없음 | `Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/` = `CanvasFeature` / `CanvasView` / `CombinedCanvasFeature` / `CombinedCanvasView` / `SharedUndoManager` 5개뿐 |
| 화면에 실제로 쓰이는 구조 | **N-Canvas.** `CombinedCanvasView` 호출부는 주석 처리 | `CarveDetailView.swift:72` 주석 블록. 살아 있는 것은 `ScrollView`(58) + `LazyVStack`(125) + 절별 `CanvasView` |
| 계측 코드 | **없음.** `os_signpost` / `OSSignposter` / `MetricKit` / `CADisplayLink` 전부 0건 | 전 저장소 grep |
| Pencil 더블탭 | **이미 배선됨** (`.onPencilDoubleTap`, iOS 17.5+) | `CarveDetailView.swift:46` |
| 두 손가락 더블탭 undo | **이미 배선됨** — 단, 깨진 `SharedUndoManager` 로 흐름 | `CarveDetailView.swift:112` → `CarveDetailFeature.swift:195` → `PencilPalatteFeature.swift:99` |
| 화면 방향 | **세로 고정.** scene manifest / `UIRequiresFullScreen` 키 없음 | `Plugins/ProjectDescriptionHelpers/InfoPlist.swift:23` |
| URL scheme | **없음** (`CFBundleURLTypes` 0건) → 딥링크로 시편 119편 진입 불가, UI 로 이동해야 함 | 전 저장소 grep |
| 1.2.0 실제 배포 | **태그 존재** (`ver1.2.0`, `ver1.2.1`) → §10-2 의 절대좌표 데이터가 존재할 개연성 | `git tag` |

### 1-2. 이 머신의 도구 실측 ★

| 항목 | 실측값 | 상태 |
|---|---|---|
| `xcode-select -p` | `/Library/Developer/CommandLineTools` — **여기엔 `xcodebuild`도 `devicectl`도 없습니다** | ✅ 확인함 |
| 설치된 Xcode | **`/Applications/Xcode-beta.app` 하나뿐** = **Xcode 27.0 (27A5209h)** | ✅ 확인함 |
| `devicectl` | `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/devicectl`, **버전 636.3** | ✅ 확인함 |
| `xctrace` | **16.0 (27A5209h)** | ✅ 확인함 |
| Instruments 템플릿 | `Allocations` / `Time Profiler` / `Animation Hitches` / `SwiftUI` / `App Launch` / `Leaks` **전부 존재** | ✅ `xctrace list templates` 실행 |
| tuist | `mise x -- tuist version` → **4.39.0** (PATH 기본값과 다름, §18-1 그대로 유효) | ✅ 확인함 |
| 생성된 워크스페이스 | `Carve.xcworkspace` **이미 존재** | ✅ 확인함 |
| 스킴 | `Carve-Workspace`, `CarveApp`, … 총 16개 | ✅ `xcodebuild -list` 실행 |
| 실기기 destination | `{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device }` — CarveApp 스킴에서 **유효** | ✅ `xcodebuild -showdestinations` 실행 |
| 현재 연결된 실기기 | **없음.** `devicectl list devices` 는 시뮬레이터만, `xctrace list devices` 의 `== Devices ==` 는 Mac 뿐 | ✅ 확인함 |
| `idevicebackup2` / `ideviceinfo` / `cfgutil` | **미설치** (libimobiledevice · Apple Configurator 없음) → 백업 추출 CLI 경로 없음 | ✅ `which` 확인 |

> ⚠️ **`xcrun devicectl ...` 을 그냥 치면 실패합니다.**
> `xcode-select` 가 CommandLineTools 를 가리키고 있어 `xcrun: error: unable to find utility "devicectl"` 이 납니다.
> 이 문서의 모든 명령은 앞에 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` 를 붙입니다.
> (`sudo xcode-select -s` 로 영구 전환해도 되지만, 그건 **머신 설정 변경**이므로 이 런북은 환경변수만 씁니다.)

**세션 시작 시 한 번 실행:**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/leetaek/Documents/Dev/Carve
```

### 1-3. §18 기록과 지금 머신이 다른 점 — 재현 시 주의

| 항목 | §18 (rev.8 기록) | 지금 이 머신 | 영향 |
|---|---|---|---|
| Xcode | 26.3 | **27.0 beta 하나뿐** | §18-3 baseline 을 **같은 툴체인으로 재현할 수 없습니다.** D5 를 §18-3 수치와 비교하지 말아야 할 이유가 하나 더 늘었습니다 (이 문서 §7 참조) |
| iPad 시뮬레이터 런타임 | iOS 26.2 하나뿐 | **26.2 / 26.4 / 27.0** 세 종류 | §18-5 4번(런타임 부족) 이 부분 완화. 단 iOS 17/18 iPad 런타임은 여전히 없음 |
| 워킹 트리 | — | `docs/single-canvas-design.md` 만 수정(rev.9, 미커밋). 나머지 clean | 이 런북 작성 시점 기준 |

> **빌드 직전 확인:** 이 세션 초반에는 iCloud 동기화 충돌 사본(`… 2.swift`)이 소스 트리에 다수 있었고 지금은 사라졌습니다.
> Tuist 의 `sources: "Sources/**"` 글롭은 이런 사본까지 컴파일 대상으로 잡아 **중복 선언 빌드 실패**를 일으킬 수 있으므로,
> 기기 빌드 전에 `git status --short` 로 `… 2.swift` 가 없는지 한 번 확인하십시오. ✅ 현재는 0건.

---

## 2. ⚠️ 데이터 안전 — 실행 전 반드시 읽으십시오

### 2-1. 위험의 정체 — Debug 빌드가 App Store 앱과 **같은 번들 ID** 를 씁니다

| 항목 | 값 | 근거 |
|---|---|---|
| Debug 번들 ID | `kr.co.carve.leetaek` | `Plugins/ProjectDescriptionHelpers/Target+Templates.swift:111` (`defaultBundleID`), `makeAppTarget` 이 `bundleId: bundleID` 를 그대로 사용 |
| Release 번들 ID | `kr.co.carve.leetaek` — **동일** | 위와 같음. configuration 별 분기 없음 |

즉, **Debug 빌드를 설치하면 iPad 에 설치된 App Store 판 "새기다" 를 대체합니다.**
side-by-side 로 공존하지 않습니다.

### 2-2. 안전하다고 **근거를 가지고** 말할 수 있는 것

| # | 사실 | 근거 |
|---|---|---|
| 1 | Debug 빌드는 로컬 DB 로 **`Carve.dev.sqlite`** 를 씁니다. 실사용 파일 `Carve.sqlite` 를 **열지 않습니다** | `SwiftDataContextProvider.swift:26` — `localDBPath = id.contains("dev") ? "Carve.dev.sqlite" : "Carve.sqlite"` |
| 2 | Debug 빌드의 CloudKit 미러링 대상은 **dev 컨테이너**(`iCloud.Carve.SwiftData.iCloud.dev`) 입니다. **prod 컨테이너에 쓰지 않습니다** | `App/CarveApp/Project.swift:36` (Debug 의 `CLOUDKIT_CONTAINER_ID`) + `SwiftDataContextProvider+Dependency.swift:36` (`cloudKitDatabase: .private(containerId.id)`) |
| 3 | 따라서 **앱을 실행하는 동안** 실사용 필사 데이터가 덮어써질 경로는 코드상 존재하지 않습니다 | 위 1·2의 조합 |
| 4 | prod CloudKit 컨테이너의 데이터는 그대로 남아 있으므로, 최악의 경우 **App Store 판 재설치 + 같은 iCloud 계정 로그인**으로 복구할 여지가 있습니다 | 위 2 |

### 2-3. 안전하다고 **확인하지 못한** 것 ⚠️

| # | 불확실한 것 | 왜 확인 못 했나 |
|---|---|---|
| 1 | **개발 서명 빌드를 App Store 서명 앱 위에 설치할 때 iOS 가 기존 데이터 컨테이너를 보존하는가, 삭제하는가** | ❓ **미확인.** 기기가 없어 실증 불가. 서명 주체가 달라질 때 iOS 가 앱을 먼저 제거하고 설치하는 동작이 보고돼 있으나, 이 조합에서 어떻게 되는지 단정할 근거가 없습니다 |
| 2 | 설치 후에도 컨테이너 안에 `Carve.sqlite` 가 남아 있는가 | 위 1에 종속. **D8 의 성패가 여기에 달려 있습니다** |
| 3 | prod CloudKit 컨테이너에 **모든** 필사 기록이 실제로 올라가 있는가 | ❓ 미확인. 동기화 실패·미로그인·용량 초과 이력이 있었다면 로컬에만 있는 데이터가 존재할 수 있습니다 |

> ⚠️ **1번이 "삭제" 쪽이면 로컬 실사용 필사 데이터가 사라집니다.**
> prod CloudKit 에 올라가 있지 않은 부분은 **되돌릴 수 없습니다.**
> 그래서 아래 백업이 **선택이 아니라 전제**입니다.

### 2-4. 필수 백업 — Step B0 (다른 어떤 단계보다 먼저)

**절차 (Finder GUI. 이 머신에 CLI 백업 도구가 없음을 `which` 로 확인했습니다)**

1. iPad 를 Mac 에 케이블로 연결
2. Finder 사이드바 → 해당 iPad 선택 → **일반** 탭
3. **"iPad의 모든 데이터를 이 Mac에 백업"** 선택
4. **"로컬 백업 암호화"** 체크 (권장 — 계정/키체인까지 포함돼 완전 복원이 가능)
5. **"지금 백업"** 클릭 → 완료 표시를 **눈으로 확인**
6. 완료 시각을 이 문서 §8-1 기록표에 적어 둡니다

**백업 존재 확인 (선택, 읽기 전용):**

```bash
ls -la ~/Library/Application\ Support/MobileSync/Backup/
```

> 🔌 이 경로에 디렉터리가 새로 생겼는지로 확인합니다. 기기 백업을 한 번도 안 했다면 경로 자체가 없을 수 있습니다.
> ❓ **백업 파일에서 앱 컨테이너만 골라 꺼내는 CLI 도구는 이 머신에 없습니다.**
> 백업은 "복원용 안전망"이지 "D8 의 추출 경로"가 아닙니다.

**추가 안전 조치 (권장):**

- **두 대 중 실사용 필사 데이터가 적은 쪽을 D8 대상으로 고르십시오.** 어느 쪽이 legacy 데이터를 가졌는지는 사용자만 압니다.
- 나머지 실기기 항목(D1~D6)은 **가능하면 데이터가 없는 쪽 기기**에서 수행해 노출을 줄이십시오.
- iCloud 백업도 켜져 있다면 설정 → Apple 계정 → iCloud → iCloud 백업 → **"지금 백업"** 을 추가로 한 번.

### 2-5. 개인 데이터 취급 — fixture 로 만들 때 ⚠️

D8 이 꺼내는 것은 **사용자 본인의 실제 필사 데이터**입니다.

| 규칙 | 내용 |
|---|---|
| **저장소 커밋 금지** | 내려받은 `.sqlite` / `_EXTERNAL_DATA` / 컨테이너 덤프를 **git 에 추가하지 마십시오** |
| **작업 위치** | 저장소 밖. 예: `~/carve-device-dump/<날짜>/` |
| **fixture 로 승격할 때** | ① 필요한 **`lineData` 블롭 1~3개만** 골라내고, ② `titleName` / `titleChapter` / `verse` / `creationDate` / `updateDate` 같은 **식별·시각 메타는 버리거나 고정 더미값으로 치환**하고, ③ base64 상수로 테스트 파일에 내장 — §19-4 가 이미 쓴 방식 그대로 |
| **왜 base64 상수인가** | 테스트 타깃에 resource 설정이 없어 파일 추가가 프로젝트 설정 변경을 부르기 때문 (§19-4, AGENTS.md) |
| **필기 내용 자체** | PKDrawing 블롭은 획 좌표이므로 텍스트가 들어 있진 않지만, **어느 절을 언제 필사했는지**는 개인 기록입니다. 커밋 메시지·문서에도 구체 절/날짜를 남기지 마십시오 |
| **정리** | 검증이 끝나면 컨테이너 덤프 원본을 삭제하거나 저장소 밖 암호화 위치로 옮기십시오 |

---

## 3. D1~D8 실행 가능성 판정 ★

### 3-1. 요약표

| ID | 항목 | **판정** | 한 줄 근거 |
|---|---|---|---|
| **D1** | Pencil hover offset / live stroke pencil-up 스냅 | **부분 가능** | issue #6 이 겨냥한 "전체 캔버스 overlay" 구조가 지금 화면에 없음(주석 처리). 현재 N-Canvas baseline 만 |
| **D2** | `.pencilOnly` 손가락 스크롤 / `anyInput` 스크롤 UX | **부분 가능** | §11 기준 **10** 은 지금 판정 가능. 기준 **9** 는 "PKCanvasView 가 유일한 스크롤러"(옵션 B) 전제라 대상 부재 |
| **D3** | 실제 Pencil 지우개로 S1 결과 재확인 | **지금 가능** | 지우개·저장 경로가 현재 빌드에 살아 있고, `7ba5bc46` 이후 stroke 0개도 DB 도달 |
| **D4** | Pencil 더블탭(지우개) / 두 손가락 더블탭(undo) | **지금 가능** | 두 제스처 모두 **이미 배선돼 있음** |
| **D5** | 시편 119편 layout 시간·peak memory·프레임 드랍 | **부분 가능** | peak memory·hitch 는 지금 측정 가능. **정밀 layout 시간은 signpost 필요 → Phase 2 이월** |
| **D6** | Stage Manager / 외부 디스플레이 (Air M2) | **지금 가능** | 코드 변경 없이 관측 가능. 결과가 §11 기준 3 의 적용 가능 여부를 결정 |
| **D7** | Phase 1 V4 스키마의 CloudKit 제약 검증 | **차단됨** | V4 스키마가 저장소에 없음 (V1/V2/V3 만) |
| **D7-pre** | *(신설)* 실기기에서 dev CloudKit 미러링이 동작하는가 | **지금 가능** | §18-5 가 시뮬레이터로 못 한 부분. D7 의 전제 조건 확보 |
| **D8** | 진짜 legacy `lineData` 1회 추출 (S5 fixture) | **지금 가능** ⚠️ | 추출 명령 존재 확인. 위험은 검증이 아니라 **설치 단계** |

### 3-2. 항목별 근거 (저장소에서 직접 확인)

**D1 — 부분 가능**

- 현재 화면 경로는 `CarveDetailView.swift:58 ScrollView` → `:125 LazyVStack` → 절별 `SentencesWithDrawingView` → `CanvasView`(절당 `PKCanvasView` 1개).
- `CombinedCanvasView` 를 overlay 로 올리던 블록은 `CarveDetailView.swift:72` 이후 **전부 주석**입니다.
- issue #6 은 §2-D5 에 "스크롤 컨테이너 2개 → offset drift" 로 진단돼 있고, 그 구조는 지금 화면에 없습니다.
- → **지금 재현되는지 아닌지를 확인하는 것은 baseline 으로서 가치가 있지만**, §11 기준 7·8 판정은 S4 spike(A/B 하네스)가 있어야 성립합니다.

**D2 — 부분 가능**

- `allowFingerDrawing` 토글이 설정 화면에 있고(`SentenceSettingsView.swift:95` "손가락 필사 허용"), 값에 따라 `drawingPolicy = .anyInput / .pencilOnly` 로 전환됩니다(`CanvasView.swift:123`).
- 따라서 §11 **기준 10** ("`allowFingerDrawing == true` 일 때 스크롤 방법이 명확한가")은 **현재 빌드에서 그대로 판정 가능**합니다. 오히려 지금 구조가 그 문제를 가장 잘 드러냅니다.
- §11 **기준 9** ("`.pencilOnly` 에서 한 손가락 스크롤")는 옵션 B(=PKCanvasView 가 유일한 `UIScrollView`)를 전제한 항목인데, 현재 스크롤러는 SwiftUI `ScrollView` 이고 캔버스는 절 단위 오버레이입니다. **판정 대상 구조가 없습니다.**

**D3 — 지금 가능**

- 지우개는 `pencilType == .monoline` 일 때 `PKEraserTool(.bitmap)`(`CanvasView.swift:111`).
- `7ba5bc46` 으로 저장 가드가 제거돼 **stroke 0개인 drawing 도 DB 에 저장**됩니다(rev.9 §19-5).
- 실기기에서 Pencil 로 그리고 → 지우고 → 컨테이너를 내려받아 `Carve.dev.sqlite` 의 `lineData` 블롭을 확보하면, S1-1/1-2/1-4/1-5 를 실제 Pencil 입력으로 재확인할 재료가 갖춰집니다.
- 범위 경계: **블롭 확보까지가 이 런북**입니다. 확보한 블롭을 `PencilKitDataModelTesting.swift` 에 base64 상수로 넣어 비교하는 것은 코드 작업(Phase 0B)입니다.

**D4 — 지금 가능**

| 제스처 | 배선 | 예상 |
|---|---|---|
| Apple Pencil 더블탭 | `CarveDetailView.swift:46` `.onPencilDoubleTap` (iOS 17.5+) → `switchToEraser` / `switchToPreviousPenType` (`CarveDetailFeature.swift:149`) | 동작할 것으로 기대 — **실기기에서만 확인 가능** |
| 두 손가락 더블탭 | `CarveDetailView.swift:112` `.onTwoFingerDoubleTap` → `CarveDetailFeature.swift:195` → `PencilPalatteFeature.swift:99` `undoManager.undo()` | **오동작 예상.** `SharedUndoManager.undo()` 는 액션 소유자가 아니라 `canvases.last` 의 undoManager 를 호출하고, `guard ... else { return }` 가 `isPerformingUndoRedo = true` 를 남긴 채 빠져나갑니다 (§13 "SharedUndoManager 를 제거해야 하는 근거") |

**D5 — 부분 가능**

| 하위 항목 | 판정 | 근거 |
|---|---|---|
| peak memory | **지금 가능** | Instruments / Xcode Debug Navigator, 코드 변경 불필요 |
| 스크롤 프레임 드랍 | **지금 가능** | `Animation Hitches` 템플릿 존재 확인 |
| **정밀 layout 소요 시간** | **차단** | `os_signpost` 가 저장소에 0건. §18-3 이 이미 "Phase 2 이월"로 적어 둔 항목과 동일 |
| 단일 Canvas 대비 A/B | **차단** | 비교 대상(S4 spike / Phase 2 VStack)이 없음 |

**D6 — 지금 가능**

- `InfoPlist.swift:23` 이 `UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait` **단일 값**이고, `UIApplicationSceneManifest` / `UISupportsMultipleScenes` / `UIRequiresFullScreen` 키가 **하나도 없습니다.**
- 세로 고정 + scene manifest 부재 조합에서 iPadOS 최신 버전이 이 앱을 어떻게 리사이즈하는지는 ❓ **미확인**입니다.
- → **이 관측 자체가 §11 기준 3("Split View resize 후 재필기 위치가 맞음")이 애초에 적용 가능한 기준인지**를 결정합니다. 그래서 값이 큽니다.

**D7 — 차단됨 / D7-pre — 지금 가능**

- V4 가 없습니다: `Domain/Domain/Sources/SwiftData/Model/` 에 `DrawingSchemaV1/V2/V3.swift` 만 존재.
- §18-5 1번이 기록한 대로 **시뮬레이터는 entitlement 가 비어 CloudKit 미러링이 전혀 동작하지 않습니다.** 실기기에서는 `Carve.entitlements` 에 두 컨테이너가 선언돼 있으므로 동작할 여지가 있습니다.
- → **D7-pre**(dev 컨테이너로 실제 미러링이 붙는가)는 지금 확인 가능하고, 이걸 확인해 두면 Phase 1 착수 시 D7 을 바로 실행할 수 있습니다.

**D8 — 지금 가능 (최우선)**

- 추출 명령 존재 ✅ 확인: `devicectl device copy from --domain-type appDataContainer --domain-identifier <bundleID>`.
- 읽기 안전성 ✅ 확인: Debug 빌드는 `Carve.dev.sqlite` 만 열므로 `Carve.sqlite` 를 건드리지 않습니다.
- ⚠️ 위험은 **설치 단계** 하나입니다 (§2-3).

> ★ **§18-4 의 경로 (a) 정정 제안**
> §18-4 는 확보 경로를 `(a) 실기기에서 dev CloudKit 컨테이너로 내려받기` / `(b) 파일 복사` 로 적었습니다.
> 그런데 Debug 빌드가 붙는 곳은 **dev 컨테이너**이고, 실사용 데이터는 **prod 컨테이너**에 있습니다
> (`Project.swift:36` vs `:40`). dev 컨테이너를 예전에 채워 둔 적이 없다면 (a)로는 **아무것도 내려오지 않습니다.**
> **실제로 성립하는 경로는 (b)** — 기기 데이터 컨테이너의 파일을 그대로 가져오는 것이고, 이 런북의 D8 은 (b)를 씁니다.

> ★ **마이그레이션이 블롭을 보존한다는 점 (D8 의 성립 근거)**
> 기기의 `Carve.sqlite` 가 이미 V3 로 마이그레이션됐더라도 괜찮습니다.
> `DrawingDataMigrationPlan.swift` 의 V1→V2 커스텀 스테이지는 `new.lineData = old.lineData` 로
> **블롭을 바이트 그대로 옮깁니다.** 즉 V3 저장소 안에도 **1.2.0 시절 PencilKit 인코딩의 블롭**이 그대로 남아 있습니다.
> 이것이 §10-2 가 원하는 것입니다.

---

## 4. 실행 순서 — 무엇을 먼저 하면 가장 많이 풀리나

| 순서 | 항목 | 이걸 하면 풀리는 것 | 지금 아니면 못 하는가 |
|---:|---|---|---|
| **0** | **P0 준비** (백업 → 서명 확인 → 빌드 → 설치) | 이후 전부의 전제 | — |
| **1** | **D8** — legacy `lineData` 추출 | **S5 fixture 확보 → Phase 0B 의 회귀 판정 기준이 열림.** 지금 Phase 0B 의 "실제 legacy 샘플 fixture" 항목이 입력 없이 막혀 있습니다 | ⚠️ **예.** 기기를 초기화하거나 앱을 지우면 원본이 사라집니다 |
| **2** | **D5 baseline** (N-Canvas, 실기기) | **Phase 2 의 `LazyVStack → VStack` 판정 기준.** §13 이 S0-4 를 "특히 중요" 라고 한 것과 **같은 논리** — 바꾼 뒤에는 기존 경로를 다시 잴 수 없습니다 | ⚠️ **예.** Phase 2 착수 전에만 가능 |
| **3** | **D7-pre** — dev CloudKit 미러링 동작 확인 | Phase 1 착수 판단. §18-5 1번이 남긴 공백을 메움 | 아니오 |
| **4** | **D6** — Stage Manager / 리사이즈 | **§11 기준 3 이 적용 가능한 기준인지** 결정 → S4 통과 기준표가 확정됨 | 아니오 |
| **5** | **D3** — 실제 Pencil 지우개 | 설계 §7-3 승계 전략 / 설계 §7-4 `.bitmap` 확정을 시뮬레이터 결론에서 실기기 결론으로 승격 | 아니오 |
| **6** | **D4** — 두 제스처 | 현재 배선의 실동작 확인. undo 결함이 실기기에서도 재현되면 §13 의 `SharedUndoManager` 제거 근거가 실증됨 | 아니오 |
| **7** | **D1 · D2** — Pencil 입력 / 스크롤 UX baseline | S4 spike 설계 입력(무엇을 A/B 로 비교할지) | 아니오 |
| **8** | **D7** | — | **차단.** Phase 1 이후 |

> **1번과 2번이 "지금 아니면 못 한다" 는 이유가 서로 다릅니다.**
> D8 은 **데이터가 사라지면 끝**이고, D5 는 **구조를 바꾸면 before 를 못 잰다**는 뜻입니다. 둘 다 되돌릴 수 없습니다.

---

## 5. P0 — 공통 준비

### P0-0. ⚠️ 백업 (§2-4)

**먼저 하십시오.** 완료 전에는 아래 어떤 단계도 실행하지 마십시오.

### P0-1. 툴체인 고정

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/leetaek/Documents/Dev/Carve
git status --short          # "… 2.swift" 중복 사본이 없어야 함
mise x -- tuist version     # 4.39.0 이어야 함
```

✅ 세 명령 모두 이 머신에서 실행 확인.

### P0-2. 프로젝트 생성 (필요 시)

`Carve.xcworkspace` 가 이미 있습니다. 재생성이 필요하면:

```bash
mise x -- tuist install
mise x -- tuist generate
```

> ❗ `tuist generate` 는 프로젝트 파일을 다시 씁니다. **`Project.swift` / signing 설정은 건드리지 마십시오.**

### P0-3. Signing — Xcode GUI 에서 **확인만** ⚠️ 변경 금지

`App/CarveApp/Project.swift:22` 에 이미 다음이 들어 있습니다.

```
.automaticCodeSigning(devTeam: "H4MSW7FUBB")
```

즉 자동 서명 + 팀 `H4MSW7FUBB` 가 **이미 설정돼 있습니다.** 별도 설정이 필요 없을 가능성이 높습니다.

**확인 절차 (GUI):**

1. `open Carve.xcworkspace`
2. 좌측 네비게이터 → **CarveApp** 프로젝트 → **CarveApp** 타깃 → **Signing & Capabilities** 탭
3. **Debug** 를 선택
4. 다음을 **눈으로 확인만** 합니다
   - `Automatically manage signing` 체크됨
   - `Team` 이 본인 개발자 계정으로 잡혀 있음
   - `Bundle Identifier` = `kr.co.carve.leetaek`
   - `iCloud` capability 에 `iCloud.Carve.SwiftData.iCloud` / `…​.dev` 두 컨테이너
5. **Team 이 비어 있거나 오류가 나는 경우에만** 드롭다운에서 본인 팀을 선택합니다.
   Xcode → Settings → Accounts 에 Apple 계정이 없으면 먼저 추가합니다.

> ⚠️ **`Project.swift` 나 `Carve.entitlements` 를 편집하지 마십시오** (AGENTS.md: signing/build setting 변경 금지).
> Xcode GUI 에서 팀을 고르는 것은 생성된 `.xcodeproj` 에만 반영되며 `tuist generate` 로 되돌아갑니다.
> 그래도 되돌아가면 GUI 에서 다시 고르십시오 — 저장소 파일을 고치는 쪽으로 해결하지 마십시오.

**기기 신뢰:**

- iPad 를 연결하고 iPad 화면의 **"이 컴퓨터를 신뢰하시겠습니까?"** 에서 신뢰
- iPad 설정 → 개인정보 보호 및 보안 → **개발자 모드** 켜기 (재부팅 필요)
- 🔌 개발자 모드 항목은 Xcode 가 기기를 한 번 인식한 뒤에 나타납니다

### P0-4. 기기 인식 확인

```bash
xcrun devicectl list devices
```

✅ 명령 실행 확인 (현재는 시뮬레이터만 나옵니다).
🔌 iPad 를 연결하면 `Reality` 열이 `physical` 인 행이 추가됩니다. 그 행의 **Identifier(UUID)** 를 아래에서 씁니다.

```bash
# 나중에 쓰기 편하게 변수로
DEV="<위에서 확인한 Identifier 또는 기기 이름>"
```

**대안 (GUI):** Xcode → **Window > Devices and Simulators** → Devices 탭.

### P0-5. 실기기용 빌드

```bash
DD=~/carve-build/device
xcodebuild build \
  -workspace Carve.xcworkspace \
  -scheme CarveApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates
```

- ✅ `-destination 'generic/platform=iOS'` 가 CarveApp 스킴에서 유효한 destination 임을 `xcodebuild -showdestinations` 로 확인했습니다 (`name:Any iOS Device`).
- 🔌 **빌드 성공 여부는 미검증**입니다 (이 문서는 빌드를 실행하지 않았습니다).
- `-allowProvisioningUpdates` 는 명령줄 플래그이며 저장소 설정을 바꾸지 않습니다.
- 산출물 예상 경로: `$DD/Build/Products/Debug-iphoneos/CarveApp.app`

> **`-derivedDataPath` 를 저장소 안으로 잡지 마십시오.**
> ✅ 확인: `.gitignore` 에는 `build/` · `DerivedData/` · `Derived/` · `Tuist/.build/` 만 있습니다.
> `./.build-device` 같은 이름은 **추적 대상이 됩니다.** 위처럼 저장소 밖(`~/carve-build/device`)을 쓰십시오.

**대안 (GUI):** Xcode 에서 상단 destination 을 연결된 iPad 로 바꾸고 `⌘R`. 서명 문제를 대화형으로 해결하기에는 GUI 가 편합니다.

### P0-6. ⚠️ 설치 — 되돌릴 수 없는 단계

> **여기서 §2-3 의 불확실성이 현실이 됩니다. 백업이 끝났는지 다시 확인하십시오.**

```bash
xcrun devicectl device install app --device "$DEV" \
  "$DD"/Build/Products/Debug-iphoneos/CarveApp.app
```

✅ 하위 명령·인자 형태 확인 (`devicectl device install app [<options>] --device <...> <path>`).
🔌 실행 결과 미검증.

**설치 직후 확인 (앱을 실행하기 전에):**

```bash
xcrun devicectl device info apps --device "$DEV" \
  --bundle-id kr.co.carve.leetaek \
  --include-container-paths
```

✅ `--bundle-id` / `--include-container-paths` / `--require-container-access` 옵션 존재 확인.

> `devicectl` 의 도움말은 컨테이너 접근 조건을 이렇게 명시합니다 —
> **"Third-party (not system app) / Installed via Xcode (profile validated) / Not enterprise signed."**
> 즉 **App Store 로 설치된 앱의 컨테이너는 내려받을 수 없습니다.** D8 이 설치를 먼저 요구하는 이유입니다.

### P0-7. 실행

```bash
xcrun devicectl device process launch --device "$DEV" \
  --terminate-existing kr.co.carve.leetaek
```

✅ 하위 명령·옵션 확인. 🔌 결과 미검증.

> **앱이 비어 보이는 것은 정상입니다.** Debug 빌드는 `Carve.dev.sqlite` 를 새로 만들고 dev CloudKit 컨테이너를 봅니다.
> 실사용 데이터가 사라진 것이 아니라 **다른 파일을 보고 있는 것**입니다 (§2-2 1·2번).

---

## 6. 항목별 런북

각 항목은 **준비 → 실행 → 판정 → 기록** 순서입니다. 기록표는 §8 에 모아 뒀습니다.

---

### 6-1. D8 — 진짜 legacy `lineData` 1회 추출 ★ 최우선

**푸는 것:** S5 fixture → Phase 0B 회귀 판정 기준

#### 준비

- §2-4 백업 완료
- P0-6 설치 완료, P0-7 로 앱을 **한 번만** 실행 (컨테이너 접근 권한 활성화 목적)
- 작업 디렉터리를 **저장소 밖**에 만듭니다

```bash
mkdir -p ~/carve-device-dump/$(date +%Y%m%d)
```

#### 실행

**1단계 — 컨테이너 안에 무엇이 있는지 먼저 봅니다 (읽기만)**

```bash
xcrun devicectl device info files --device "$DEV" \
  --domain-type appDataContainer \
  --domain-identifier kr.co.carve.leetaek \
  --subdirectory "Library/Application Support"
```

✅ `--domain-type appDataContainer` / `--domain-identifier` / `--subdirectory` / `--recurse` 옵션 존재 확인.
🔌 실제 파일 목록은 기기 연결 후 확인.

**여기서 판정합니다:**

| 관측 | 의미 |
|---|---|
| `Carve.sqlite` 가 **보인다** | ✅ 설치가 컨테이너를 보존했습니다. 2단계로 진행 |
| `Carve.dev.sqlite` 만 보인다 | ⚠️ **설치 과정에서 기존 컨테이너가 지워졌습니다.** 여기서 멈추고 §2-4 백업으로 복원 판단. D8 은 이 기기에서 실패 |

**2단계 — `Library/Application Support` 를 통째로 내려받습니다**

```bash
xcrun devicectl device copy from --device "$DEV" \
  --domain-type appDataContainer \
  --domain-identifier kr.co.carve.leetaek \
  --source "Library/Application Support" \
  --destination ~/carve-device-dump/$(date +%Y%m%d)/
```

✅ `devicectl device copy from` 의 `--source` / `--destination` / `--domain-type` / `--domain-identifier` 인자 존재 확인.
🔌 `--source` 가 도메인 루트 기준 상대 경로로 어떻게 해석되는지는 **기기 연결 후 1단계 출력을 보고 맞추십시오.**
잘 안 되면 `--source .` 로 컨테이너 전체를 받는 것도 방법입니다.

> ★ **`Carve.sqlite` 파일 하나만 받으면 안 됩니다.**
> `lineData` 는 `@Attribute(.externalStorage)` 입니다 (`DrawingSchemaV3.swift`).
> 큰 블롭은 sqlite 바깥의 `_EXTERNAL_DATA` 디렉터리에 별도 파일로 나가므로,
> **`Application Support` 디렉터리 전체**(`Carve.sqlite`, `-wal`, `-shm`, `.Carve.sqlite_SUPPORT/` 포함)를 받아야 합니다.

**대안 (GUI):** Xcode → **Window > Devices and Simulators** → Devices → 기기 선택 → **Installed Apps** 에서 앱 선택 →
기어 아이콘 → **Download Container…**. 결과는 `.xcappdata` 번들이고, 우클릭 → 패키지 내용 보기 → `AppData/Library/Application Support/`.
🔌 이 메뉴가 활성화되려면 개발 설치된 앱이어야 합니다 (P0-6 이후).

**3단계 — 내려받은 것이 쓸 만한지 확인 (읽기 전용)**

```bash
D=~/carve-device-dump/$(date +%Y%m%d)
ls -laR "$D" | head -50
sqlite3 "$D/.../Carve.sqlite" \
  "SELECT COUNT(*), MIN(ZCREATIONDATE), MAX(ZCREATIONDATE) FROM ZBIBLEDRAWING;"
sqlite3 "$D/.../Carve.sqlite" \
  "SELECT Z_PK, ZTITLENAME, ZTITLECHAPTER, ZVERSE, ZDRAWINGVERSION, LENGTH(ZLINEDATA) FROM ZBIBLEDRAWING LIMIT 20;"
```

🔌 실제 경로와 테이블/컬럼명은 **연결 후 `.tables` / `.schema` 로 확인**하십시오.
§18-3 이 `length(ZLINEDATA)` 를 이미 썼으므로 명명 규칙은 이 형태일 가능성이 높지만, 이 문서에서 검증하진 못했습니다.

#### 판정

| # | 판정 기준 | 통과 | 실패 |
|---|---|---|---|
| D8-1 | 설치 후 컨테이너에 `Carve.sqlite` 가 남아 있다 | 존재 | 부재 → 즉시 중단, 복원 검토 |
| D8-2 | `ZBIBLEDRAWING` 행이 1건 이상이고 `ZLINEDATA` 길이가 0이 아니다 | 행 ≥ 1 | 0건 → legacy 데이터 없음 |
| D8-3 | `ZCREATIONDATE` 최솟값이 **1.2.0 배포 이전**을 가리킨다 (= 구 인코딩 블롭 존재 가능성) | 그렇다 | 아니면 "진짜 legacy" 가 아닐 수 있음 — §10-2 재검토 |
| D8-4 | `_EXTERNAL_DATA` 로 나간 블롭까지 함께 받았다 | 디렉터리 존재 또는 external 블롭 없음이 확인됨 | 누락 → 다시 받기 |

#### 기록 → §8-3

#### 사후

- 확보한 덤프는 **저장소 밖**에 둡니다 (§2-5).
- fixture 승격(base64 상수화)은 **Phase 0B 의 코드 작업**입니다. 이 런북 범위 밖.

---

### 6-2. D5 — 시편 119편 실측 (N-Canvas baseline) ★ 두 번째

**푸는 것:** Phase 2 판정 기준. **지금 아니면 못 잽니다.**
**측정 방법의 근거는 이 문서 §7 에 따로 정리했습니다. 실행 전에 반드시 읽으십시오.**

#### 준비

- Instruments 는 **Xcode-beta 안의 것**을 씁니다: `/Applications/Xcode-beta.app/Contents/Applications/Instruments.app` ✅ 존재 확인
- **딥링크가 없으므로** 시편 119편에는 앱 UI 로 이동합니다 (§1-1: `CFBundleURLTypes` 0건).
  §18-3 이 쓴 `UserDefaults "title"` 시드 방식은 시뮬레이터 컨테이너를 호스트 파일시스템에서 직접 고치는 방법이라 **실기기에 그대로 쓸 수 없습니다.**
- 절차를 두 기기에서 **똑같이** 반복해야 하므로, 스크롤 횟수·방향·대기 시간을 먼저 정해 적어 두십시오.

#### 실행

**(1) peak memory — Xcode Debug Navigator**

1. Xcode 에서 기기를 destination 으로 잡고 `⌘R`
2. 좌측 네비게이터 → **Debug Navigator** (⌘7) → **Memory**
3. 창세기 1장 진입 후 **8초 대기**(§18-3 의 settle 기준과 동일) → footprint 기록
4. 시편 119편으로 이동 → 8초 대기 → footprint 기록
5. 장 끝까지 스크롤(횟수 고정) → footprint 및 최대치 기록
6. 시편 120편(7절)으로 이동 → 6초, 추가 25초 → footprint 기록 (§18-3 (D) 대응)

> **왜 Debug Navigator 인가:** Xcode 의 Memory gauge 가 보여 주는 값은 앱의 **memory footprint** 계열로,
> §18-3 이 쓴 `vmmap --summary` 의 Physical footprint 와 **같은 종류의 지표**입니다
> (Instruments Allocations 의 "All Heap & Anonymous VM" 합계는 **다른 지표**이므로 footprint 값으로 쓰지 마십시오).
> ❓ 다만 두 값을 같은 대상에 대해 실측 대조하지는 못했습니다. **절대값 등가로 다루지 말고 A/B 비교용으로만** 쓰십시오.
> 디버거가 붙어 있는 것 자체도 오버헤드입니다.

**(2) 메모리 귀속 — Instruments Allocations**

```bash
xcrun xctrace record \
  --template 'Allocations' \
  --device "$DEV" \
  --attach 'CarveApp' \
  --time-limit 90s \
  --output ~/carve-device-dump/d5-alloc-<기기>-<장>.trace
```

✅ `xctrace record` 의 `--template` / `--device` / `--attach` / `--time-limit` / `--output` 옵션 확인,
`Allocations` 템플릿 존재 확인.
🔌 `--attach` 에 프로세스 이름과 pid 중 무엇이 먹는지는 기기 연결 후 확인 (`--attach <pid|name>`).

**대안 (GUI, 권장):** Instruments.app → Allocations → 기기·앱 선택 → Record. GUI 가 마킹·구간 선택에 훨씬 낫습니다.

**(3) 프레임 드랍 — Instruments Animation Hitches**

```bash
xcrun xctrace record \
  --template 'Animation Hitches' \
  --device "$DEV" \
  --attach 'CarveApp' \
  --time-limit 60s \
  --output ~/carve-device-dump/d5-hitch-<기기>-<장>.trace
```

✅ `Animation Hitches` 템플릿 존재 확인.
기록 중 **창세기 1장 전체 스크롤 → 시편 119편 전체 스크롤**을 같은 리듬으로 수행합니다.

- 읽을 값: **hitch time ratio (ms/s)** 와 개별 hitch 의 지속시간·원인 구간
- ❓ 절대 임계값은 이 문서에서 단정하지 않습니다. **두 장 사이 / 두 기기 사이의 상대 비교**로 판정하십시오.

**(4) CPU 분포 — Time Profiler (선택)**

같은 형태로 `--template 'Time Profiler'`. §18-3 의 "flick 중 한 코어 95~100%" 관측이 실기기에서도 나오는지 확인용입니다.

**(5) layout 소요 시간 — 지금은 정밀 측정 불가**

- `os_signpost` 가 저장소에 없어 정밀 측정은 **Phase 2 이월**입니다 (§18-3 "측정 못 한 것" 과 동일).
- 코드 변경 없이 가능한 대체:
  - **`SwiftUI` 템플릿** — View body 평가 횟수·시간, Core Animation commit 을 보여 줍니다. "레이아웃 비용이 어디서 나는가" 의 근사치로는 가장 낫습니다. ✅ 템플릿 존재 확인
  - **`App Launch` 템플릿** — cold launch 구간 분해
  - **화면 녹화 기반 wall clock** — 장 전환 탭부터 본문이 그려질 때까지. 거칠지만 A/B 에는 쓸 수 있습니다

#### 판정

| # | 판정 기준 | 비고 |
|---|---|---|
| D5-1 | 두 기기 모두에서 시편 119편 진입·스크롤 중 **크래시·jetsam 종료가 없다** | 절대 기준으로 쓸 수 있는 유일한 항목 |
| D5-2 | 절 수에 대한 메모리 증분이 **선형 근사에서 크게 벗어나지 않는다** | §18-3 의 `증분 ≈ 37 + 0.41·N` 은 **기울기/절편 구조만** 참고. 값 자체를 비교하지 마십시오 |
| D5-3 | 장 전환 후 메모리 **미회수 현상이 실기기에서도 재현되는가** | §18-3 (D). 재현되면 "기존부터 존재" 가 실기기에서도 확정됩니다 |
| D5-4 | hitch time ratio 가 **창세기 1장 대비 시편 119편에서 유의하게 나쁜가** | 상대 비교 |
| D5-5 | mini 와 Air 사이에 유의한 차이가 있는가 | 둘 다 60Hz·8GB 라 큰 차이는 기대하지 않음 (§13) |

#### 기록 → §8-4

---

### 6-3. D7-pre — 실기기에서 CloudKit 미러링이 동작하는가

**푸는 것:** §18-5 1번의 공백. Phase 1 착수 판단.

#### 준비

- iPad 가 iCloud 에 로그인돼 있고 네트워크 연결됨
- P0-6/P0-7 완료

#### 실행

1. 앱 실행 후 필사를 몇 획 남깁니다 (dev DB 에 기록 생성)
2. Xcode 콘솔에서 `cloudEvent` 로그를 봅니다 — `SwiftDataContextProvider.swift:105` 가 `Log.debug("cloudEvent", ...)` 를 남깁니다
3. `NSPersistentCloudKitContainer.Event` 의 `type == .import` / `.export` 가 실제로 오는지 확인
4. 설치된 앱의 entitlement 가 실제로 채워졌는지 확인:

```bash
codesign -d --entitlements - \
  "$DD"/Build/Products/Debug-iphoneos/CarveApp.app
```

✅ 명령 형태는 §18-5 가 시뮬레이터에서 쓴 것과 동일합니다. 🔌 실기기 빌드 결과는 미검증.

#### 판정

| # | 판정 기준 | 통과 | 실패 |
|---|---|---|---|
| D7-pre-1 | 기기 빌드의 entitlement 에 `com.apple.developer.icloud-container-identifiers` 가 **비어 있지 않다** | 두 컨테이너 나옴 | `<dict></dict>` → 서명 프로파일 문제 |
| D7-pre-2 | `CKAccountStatus` 가 `.available` (실패 로그 `"CloudKit 초기화 실패…"` 가 안 남는다) | 통과 | 계정/네트워크 확인 |
| D7-pre-3 | `NSPersistentCloudKitContainer` import/export 이벤트가 관측된다 | 통과 | 미러링 미동작 → **D7 은 실기기로도 검증 불가**. 이 경우 CloudKit 제약은 코드 리뷰·문서로만 판단해야 하며 리스크로 승격 |

> ⚠️ **prod 컨테이너를 확인하려고 Release 빌드를 설치하지 마십시오.** 실사용 데이터에 직접 쓰게 됩니다.
> D7-pre 는 **dev 컨테이너에서만** 수행합니다.

#### 기록 → §8-3

---

### 6-4. D6 — Stage Manager / 리사이즈 / 외부 디스플레이

**푸는 것:** §11 기준 3(Split View resize)과 기준 4(왼손잡이 전환)의 적용 가능 여부

#### 준비

- iPad Air (M2) 권장 (§13 표가 지목한 기기)
- 설정 → 멀티태스킹 및 제스처 → Stage Manager 켜기 (버전에 따라 위치가 다릅니다)

#### 실행 / 판정

| # | 확인 | 판정 기준 |
|---|---|---|
| D6-1 | Stage Manager 에서 앱 창이 **리사이즈되는가** | 리사이즈됨 / 전체화면 고정 |
| D6-2 | 리사이즈 시 본문 폭이 바뀌고 필사가 재배치되는가 | `CarveDetailView.swift` 의 `contentView.id("\(sentenceSetting)-\(halfWidth)")` 때문에 **폭이 바뀌면 전체가 재생성**됩니다. 재생성 후 획 위치가 유지되는지 봅니다 |
| D6-3 | Split View / Slide Over 진입이 되는가 | ❓ 세로 고정 + scene manifest 부재 조합의 결과를 확인 |
| D6-4 | 왼손잡이 전환 후 좌표 정합 (§11 기준 4) | `SentencesWithDrawingView` 의 `isLeftHanded` 로 좌우 배치가 바뀝니다 |
| D6-5 | 외부 디스플레이 연결 시 동작 | 미러링만 되는지, 확장 창이 뜨는지 |
| D6-6 | 화면 회전 | 세로 고정이므로 가로에서 어떻게 되는지 관측 |

> ★ **D6-1/D6-3 의 결과가 §11 통과 기준표를 바꿉니다.**
> 앱이 애초에 리사이즈되지 않는다면 §11 기준 3 은 **S4 통과 기준에서 빼거나, "리사이즈 지원을 추가한 뒤 재평가" 로 이월**해야 합니다.
> 이 판단을 D6 결과에 근거해 설계 문서에 반영하십시오.

#### 기록 → §8-3

---

### 6-5. D3 — 실제 Apple Pencil 지우개로 S1 재확인

**푸는 것:** 설계 §19-5 가 남긴 "실제 Pencil 지우개 미확인" → 설계 §7-3 / 설계 §7-4 확정

#### 준비

- Apple Pencil 페어링
- Debug 빌드 실행 중
- **깨끗한 절을 하나 고릅니다** (dev DB 이므로 실사용 데이터와 무관)

#### 실행

1. 절 하나에 **가로로 긴 획 1개**를 Pencil 로 긋습니다 (§19-2 의 264pt 획에 대응)
2. 앱을 잠시 대기 (trailing debounce 0.3s + 저장 완료)
3. 도구를 지우개(`monoline`)로 바꿔 **획의 가운데를 지웁니다** → 두 조각이 되는지 눈으로 확인
4. 다시 대기
5. **같은 절의 남은 조각을 전부 지웁니다** (stroke 0개 상태)
6. 앱 종료 후 컨테이너를 내려받습니다 (D8 2단계와 동일한 명령, 단 `Carve.dev.sqlite` 대상)

각 단계 사이에 컨테이너를 받아 **3개의 블롭 스냅샷**(원본 / 분할 후 / 전부 지운 뒤)을 확보하는 것이 이상적입니다.

#### 판정

시뮬레이터 결과(§19-1, §19-2)와 **같은가 다른가**를 봅니다.

| # | 시뮬레이터 결론 (S1) | 실기기 판정 기준 |
|---|---|---|
| D3-1 | S1-1 `randomSeed` 라운드트립 보존 | 보존되면 통과 |
| D3-2 | S1-2 bitmap 지우개는 **분할 + 마스킹 동시** | 조각 수와 `mask` 유무가 시뮬레이터와 같으면 통과 |
| D3-3 | S1-4 IdentityKey 구성요소 전부 불변 (`randomSeed`, `creationDate`, `path.count`, control point 값) | 전부 같으면 통과 |
| D3-4 | S1-5 `mask` / `maskedPathRanges` 보존 | 보존되면 통과 |
| D3-5 | S1-3 완전히 지운 stroke 는 제거됨 | `strokes == 0` 이고 **DB 길이가 줄어들면** 통과 (rev.9 §19-5 의 `515 → 317` 대응) |

> **하나라도 다르면 설계 §7-3 승계 전략과 설계 §7-4 `.bitmap` 확정을 재검토해야 합니다.**
> 이건 "성능 차이" 가 아니라 **데이터 모델 전제의 차이**이므로 설계에 직접 영향이 갑니다.

> **범위 경계:** 블롭 확보까지가 이 런북입니다. 실제 필드 비교(`randomSeed` 등)는
> `PencilKitDataModelTesting.swift` 에 base64 상수를 추가하는 **코드 작업**이며 Phase 0B 에서 합니다.

#### 기록 → §8-3

---

### 6-6. D4 — Pencil 더블탭 / 두 손가락 더블탭

**푸는 것:** 현재 배선의 실동작. `SharedUndoManager` 제거 근거의 실증.

#### 준비

- Apple Pencil (더블탭 지원 모델: Pencil 2세대 / Pro)
- iPad 설정 → Apple Pencil → 더블탭 동작이 "끄기" 로 돼 있지 않은지 확인

#### 실행 / 판정

| # | 조작 | 기대 (코드 근거) | 판정 기준 |
|---|---|---|---|
| D4-1 | 필기 중 Pencil 더블탭 | 지우개로 전환 (`CarveDetailView.swift:46` → `switchToEraser`) | 전환되면 통과 |
| D4-2 | 지우개 상태에서 다시 더블탭 | 직전 펜 타입으로 복귀 (`switchToPreviousPenType`, `lastUsedPencil`) | 복귀하면 통과 |
| D4-3 | 두 손가락 더블탭 | undo (`CarveDetailView.swift:112` → `PencilPalatteFeature.swift:99`) | **오동작 예상.** 방금 그은 획이 아니라 다른 캔버스가 undo 되거나 아무 일도 안 일어나면 §13 근거 확정 |
| D4-4 | D4-3 이후 팔레트의 undo 버튼 | `canUndo` 상태가 실제와 맞는가 | 어긋나면 `isPerformingUndoRedo` 누수 정황 |
| D4-5 | 두 손가락 더블탭이 스크롤·탭 제스처와 충돌하는가 | `.onTapGesture { tapForHeaderHidden }` 과 공존 | 헤더가 의도치 않게 토글되면 기록 |

#### 기록 → §8-3

---

### 6-7. D1 — Pencil hover / live stroke (baseline)

**푸는 것:** S4 spike 설계 입력. **§11 기준 7·8 의 판정은 아닙니다.**

#### 실행 / 판정

| # | 조작 | 판정 기준 (현재 N-Canvas 구조 기준) |
|---|---|---|
| D1-1 | Pencil 을 화면 위 hover | 본문·밑줄·캔버스가 **움직이지 않는다** |
| D1-2 | 획을 긋고 pencil-up | live stroke 가 **확대되거나 이동하지 않는다** (issue #6 증상) |
| D1-3 | 스크롤 도중 필기 | 획이 손끝 위치에 그려진다 |
| D1-4 | 절 경계를 넘는 획 | **끊긴다** (현재 구조의 알려진 한계, §1-1). 끊기는 지점을 기록 |
| D1-5 | 빠른 fling 직후 필기 | 좌표가 어긋나지 않는다 |

> **D1-2 가 현재 구조에서 재현되지 않는다면**, issue #6 은 `CombinedCanvasView` 구조 고유의 문제였다는 뜻이고
> S4 spike 에서 **정확히 그 구조를 재현해 비교해야** 한다는 결론이 나옵니다. 그것이 이 항목의 가치입니다.

#### 기록 → §8-3

---

### 6-8. D2 — 손가락 입력과 스크롤 UX (baseline)

#### 실행 / 판정

| # | 조작 | 판정 기준 |
|---|---|---|
| D2-1 | `allowFingerDrawing = false` (기본) 에서 한 손가락 스크롤 | 정상 스크롤 (현재는 SwiftUI ScrollView 가 처리) |
| D2-2 | 설정에서 **"손가락 필사 허용"** 켜기 (`SentenceSettingsView.swift:95`) 후 스크롤 시도 | **§11 기준 10 — 지금 판정 가능.** 캔버스 위에서 손가락이 획이 되어 스크롤 방법이 사라지는지 확인 |
| D2-3 | D2-2 상태에서 스크롤 가능한 영역이 남아 있는가 | 본문 쪽(캔버스 밖)에서만 되는지, 두 손가락으로 되는지 기록 |
| D2-4 | 손바닥 거치(palm rejection) | Pencil 모드에서 손바닥이 획을 만들지 않는다 |

> **§11 기준 9 는 여기서 판정하지 않습니다.** 옵션 B(PKCanvasView 단독 스크롤) 구조가 없기 때문입니다.

#### 기록 → §8-3

---

## 7. ★ D5 측정 방법 — 실기기 대응

### 7-1. §18-3 의 방법이 실기기에 그대로 안 되는 이유

| §18-3 방법 | 실기기에서 | 왜 |
|---|---|---|
| `vmmap --summary <pid> \| grep "Physical footprint"` | ❌ 불가 | `vmmap` 은 **호스트 macOS 프로세스**를 봅니다. 시뮬레이터 앱은 Mac 위의 프로세스라서 통했습니다. iPad 에는 셸도 없고 그 프로세스를 볼 수단도 없습니다 |
| `ps -o time=` 델타, 0.25s 샘플링 | ❌ 불가 | 같은 이유 |
| `UserDefaults "title"` 에 JSON 시드 후 재기동 | ❌ 불가 | 시뮬레이터 컨테이너를 호스트 파일시스템에서 직접 고치는 방식입니다. 기기에서는 `devicectl device copy to` 로 밀어 넣어도 `cfprefsd` 캐시 때문에 신뢰할 수 없고, ❓ 이 문서에서 검증하지 못했습니다. **앱 UI 로 이동하십시오** (URL scheme 도 없음) |
| 자동 flick 11회 `(372,900)→(372,200)` | ⚠️ 그대로 불가 | 좌표는 iPad mini 744×1133pt 기준이며, 실기기에는 동일한 자동 입력 수단이 없습니다. **손가락 제스처를 횟수·방향·속도를 정해 반복**하고, 그 절차를 기록표에 적으십시오 |

### 7-2. ⚠️ §18-3 수치와 **직접 비교하면 안 되는** 이유

| # | 이유 |
|---|---|
| 1 | **메모리 회계가 다릅니다.** 시뮬레이터의 Physical footprint 는 호스트 macOS 커널의 값이고, 실기기는 iOS 커널의 `phys_footprint` 입니다. 공유 캐시·dyld·Metal 스택 구성이 다릅니다 |
| 2 | **CPU 시간이 무의미합니다.** 시뮬레이터는 앱 코드를 **Mac 의 M 시리즈 CPU** 에서 네이티브로 돌립니다. A17 Pro / M2 의 성능이 아닙니다 |
| 3 | **렌더 파이프라인이 다릅니다.** 시뮬레이터는 macOS WindowServer 를 경유합니다. 프레임 타이밍·hitch 는 실기기와 같은 종류의 값이 아닙니다 (§11 이 기준 7~11 을 Device 전용으로 둔 이유) |
| 4 | **압력이 없습니다.** 시뮬레이터에는 jetsam 메모리 압박도, thermal throttling 도 없습니다 |
| 5 | **입력이 다릅니다.** §18-3 은 자동 마우스 flick, 실기기는 손가락입니다. 스크롤 속도·거리·관성이 다릅니다 |
| 6 | **툴체인이 다릅니다.** §18-3 은 Xcode 26.3, 이 머신은 **Xcode 27.0 beta 하나뿐**입니다 (§1-3). 같은 시뮬레이터 측정조차 재현되지 않습니다 |

**비교해도 되는 것:**

| 비교 가능 | 설명 |
|---|---|
| **A/B 상대값** | 같은 기기·같은 절차에서 구조 A vs 구조 B |
| **스케일링 형태** | `증분 ≈ 37 + 0.41·N` 의 **기울기/절편 구조** — 절 수에 선형인가, 초선형인가 |
| **알고리즘 복잡도** | O(N) 인가 O(N²) 인가. 절 수를 31 / 176 두 점으로만 봐도 판단 가능 |
| **정성적 현상의 재현 여부** | 예: §18-3 (D) "작은 장으로 옮겨도 메모리가 회수되지 않는다" 가 실기기에서도 그런가 |

> 이것이 §11 통과 기준 11번에 붙은 **△ 표기**("시뮬레이터 수치는 절대값으로 쓸 수 없고 A/B 상대 비교와 알고리즘 복잡도 확인에만 사용")의 뜻입니다.
> **실기기 D5 는 그 △ 를 ✅ 로 바꾸는 작업이지, §18-3 표에 새 열을 붙이는 작업이 아닙니다.**

### 7-3. 도구 선택과 근거

| 측정 대상 | 도구 | 근거 | 상태 |
|---|---|---|---|
| **peak memory (footprint)** | **Xcode Debug Navigator > Memory** | §18-3 의 Physical footprint 와 **같은 종류의 footprint 지표**를 코드 변경 없이 볼 수 있는 유일한 수단. Instruments Allocations 총합은 다른 지표. ❓ 두 값의 실측 대조는 못 했으니 **절대값 등가로 다루지 마십시오** | ✅ Instruments.app 존재 확인 |
| **메모리 귀속** | **Instruments `Allocations`** | 무엇이 얼마나 쌓이는지. §18-3 이 "PencilKit 캔버스 1개당 실제 점유" 를 못 쟀다고 적은 부분을 여기서 근사 | ✅ 템플릿 존재 |
| **프레임 드랍 / hitch** | **Instruments `Animation Hitches`** | 스크롤 hitch 를 ms/s 비율로 정량화. §18-3 이 "`CADisplayLink` 또는 Instruments 필요" 로 이월한 항목 그대로 | ✅ 템플릿 존재 |
| **CPU 분포** | **Instruments `Time Profiler`** | §18-3 의 "flick 중 한 코어 95~100%" 재현 확인 | ✅ 템플릿 존재 |
| **레이아웃 비용 근사** | **Instruments `SwiftUI`** | View body 평가·Core Animation commit. 코드 변경 없이 얻을 수 있는 최선의 layout 근사 | ✅ 템플릿 존재 |
| **정밀 layout 시간** | **`os_signpost`** | **코드 변경 필요 → Phase 2 이월.** 저장소에 signpost 0건 | ❌ 지금 불가 |
| **MetricKit** | **쓰지 않습니다 (지금은)** | ① 저장소에 `MetricKit` 0건 → 구독 코드 추가가 필요(코드 변경), ② 보고가 **하루 단위 집계**로 도착해 A/B 스파이크에 부적합, ③ 개별 조작과 수치를 대응시킬 수 없음 | ❌ 지금 불가 |

> ★ **MetricKit 은 버리지 말고 위치를 옮기십시오.**
> §13 이 리스크로 적은 두 사각지대 — **120Hz ProMotion 기기**와 **저메모리 iPad** — 는 보유 기기로 덮을 수 없고,
> 대응이 "TestFlight 베타에서 확인" 으로 돼 있습니다. **MetricKit(`MXAnimationMetric` 의 hitch time ratio, `MXMemoryMetric` 의 peak memory)은
> 바로 그 베타 단계에서 실사용자 기기의 값을 모으는 수단으로 가장 적합합니다.**
> Phase 2~3 에서 계측을 넣을 때 signpost 와 함께 검토하십시오.

### 7-4. 측정 절차를 반드시 문서화하십시오

§18-3 이 "재측정 시 그대로 반복" 이라고 적고 절차를 남긴 것과 같은 이유입니다.
아래를 §8-4 기록표에 채우십시오.

```
기기 / iOS 버전 / 화면 크기(pt)
Xcode 버전 / 빌드 configuration
장 지정 방법            (앱 UI 이동 — 딥링크 없음)
settle 대기 시간        (§18-3 은 cold launch 후 8초)
스크롤 절차             (방향 / 1회 이동량 / 횟수 / 간격 / 끝 도달 확인 방법)
측정 도구 및 버전       (Debug Navigator / Instruments 템플릿명)
디버거 부착 여부        (footprint 값에 영향)
```

---

## 8. 기록 양식

> 아래 표를 이 문서에 그대로 채워 넣으십시오.
> 완료 후 설계 문서의 **§18·§19 와 같은 부록**(예: "§21 부록 E — Phase 0A-D 실측 결과") 으로 옮길 수 있는 형태입니다.

### 8-1. 실행 환경 및 안전 조치

| 항목 | 값 |
|---|---|
| 실행일 | |
| 실행자 | |
| Mac / macOS | |
| Xcode | |
| tuist (`mise x -- tuist version`) | |
| 저장소 커밋 (`git rev-parse --short HEAD`) | |
| 워킹 트리 상태 | |
| **기기 A** — 모델 / iOS / 화면(pt) | |
| **기기 B** — 모델 / iOS / 화면(pt) | |
| **⚠️ 백업 완료 여부 / 시각 (기기 A)** | |
| **⚠️ 백업 완료 여부 / 시각 (기기 B)** | |
| 백업 방식 (Finder 암호화 / iCloud) | |
| 설치 전 App Store 판 버전 | |
| 설치한 Debug 빌드 configuration / 번들 ID | |
| **설치 후 기존 데이터 컨테이너 보존 여부** (D8-1 결과) | |

### 8-2. D1~D8 판정 요약 (실행 후 갱신)

| ID | 사전 판정 | 실제 실행 여부 | 결과 (통과 / 실패 / 보류 / 미실행) | 비고 |
|---|---|---|---|---|
| D1 | 부분 가능 | | | |
| D2 | 부분 가능 | | | |
| D3 | 지금 가능 | | | |
| D4 | 지금 가능 | | | |
| D5 | 부분 가능 | | | |
| D6 | 지금 가능 | | | |
| D7 | 차단됨 | | | Phase 1 이후 |
| D7-pre | 지금 가능 | | | |
| D8 | 지금 가능 | | | |

### 8-3. 항목별 상세 기록

**D8 — legacy `lineData` 추출**

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D8-1 | 설치 후 컨테이너에 `Carve.sqlite` 존재 | | |
| D8-2 | `ZBIBLEDRAWING` 행 ≥ 1, `ZLINEDATA` 길이 > 0 | | |
| D8-3 | `ZCREATIONDATE` 최솟값이 1.2.0 이전 | | |
| D8-4 | `_EXTERNAL_DATA` 포함 확보 | | |

| 항목 | 값 |
|---|---|
| 덤프 저장 위치 (저장소 밖) | |
| `ZBIBLEDRAWING` 행 수 | |
| `ZLINEDATA` 길이 분포 (최소 / 중앙 / 최대) | |
| `ZDRAWINGVERSION` 분포 | |
| fixture 후보로 고른 블롭 (개수 / 길이) | |
| 개인정보 제거 조치 | |

**D7-pre — CloudKit 미러링**

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D7-pre-1 | entitlement 에 컨테이너 2개 존재 | | |
| D7-pre-2 | `CKAccountStatus == .available` | | |
| D7-pre-3 | import/export 이벤트 관측 | | |

**D6 — Stage Manager / 리사이즈**

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D6-1 | Stage Manager 에서 리사이즈됨 | | |
| D6-2 | 리사이즈 후 필사 위치 유지 | | |
| D6-3 | Split View / Slide Over 진입 | | |
| D6-4 | 왼손잡이 전환 후 좌표 정합 (§11 기준 4) | | |
| D6-5 | 외부 디스플레이 동작 | | |
| D6-6 | 화면 회전 동작 | | |

> **§11 기준 3 적용 가능 여부 결론:** ______

**D3 — 실제 Pencil 지우개**

| # | 판정 기준 (S1 결론과 동일한가) | 관측 | 판정 |
|---|---|---|---|
| D3-1 | `randomSeed` 라운드트립 보존 | | |
| D3-2 | 분할 + 마스킹 동시 | | |
| D3-3 | IdentityKey 구성요소 전부 불변 | | |
| D3-4 | `mask` / `maskedPathRanges` 보존 | | |
| D3-5 | 완전히 지운 stroke 제거 + DB 길이 감소 | | |

| 스냅샷 | 블롭 길이 | stroke 수 | 비고 |
|---|---|---|---|
| 원본 (획 1개) | | | |
| 가운데 지운 뒤 | | | |
| 전부 지운 뒤 | | | |

**D4 — 제스처**

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D4-1 | Pencil 더블탭 → 지우개 전환 | | |
| D4-2 | 다시 더블탭 → 직전 펜 복귀 | | |
| D4-3 | 두 손가락 더블탭 → undo | | |
| D4-4 | `canUndo` 상태 정합 | | |
| D4-5 | 다른 제스처와 충돌 | | |

**D1 — Pencil 입력 baseline**

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D1-1 | hover 중 화면 이동 없음 | | |
| D1-2 | pencil-up 시 live stroke 스냅 없음 | | |
| D1-3 | 스크롤 중 필기 위치 정확 | | |
| D1-4 | 절 경계 획 끊김 지점 | | |
| D1-5 | fling 직후 필기 좌표 정합 | | |

**D2 — 스크롤 UX baseline**

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D2-1 | pencilOnly 에서 한 손가락 스크롤 | | |
| D2-2 | **§11 기준 10** — anyInput 에서 스크롤 방법이 명확한가 | | |
| D2-3 | anyInput 에서 스크롤 가능한 영역 | | |
| D2-4 | palm rejection | | |

### 8-4. D5 실측 기록

**측정 절차 (이 문서 §7-4 항목을 채우십시오)**

| 항목 | 값 |
|---|---|
| 장 지정 방법 | |
| settle 대기 | |
| 스크롤 절차 (방향/이동량/횟수/간격) | |
| 끝 도달 확인 방법 | |
| 디버거 부착 여부 | |
| 사용 도구 / 템플릿 | |

**(A) Cold launch (스크롤 없음)** — footprint, Debug Navigator

| 기기 | 장 | 절 수 | footprint | peak |
|---|---|---:|---:|---:|
| mini (A17 Pro) | 창세기 1장 | 31 | | |
| mini (A17 Pro) | 시편 119편 | 176 | | |
| Air (M2) | 창세기 1장 | 31 | | |
| Air (M2) | 시편 119편 | 176 | | |

**(B) 앱 내 장 전환 진입**

| 기기 | 전환 | 절 수 | footprint 전 → 후 | 증분 | 체감 지연 |
|---|---|---:|---|---:|---|
| mini | 창세기 1장 → 2장 | 25 | | | |
| mini | 시편 118편 → 119편 | 176 | | | |
| Air | 창세기 1장 → 2장 | 25 | | | |
| Air | 시편 118편 → 119편 | 176 | | | |

**(C) 장 전체 스크롤**

| 기기 | 장 | 절 수 | footprint 전 → 후 | 증분 | peak | hitch time ratio (ms/s) | hitch 최대 (ms) |
|---|---|---:|---|---:|---:|---:|---:|
| mini | 창세기 1장 | 31 | | | | | |
| mini | 시편 119편 | 176 | | | | | |
| Air | 창세기 1장 | 31 | | | | | |
| Air | 시편 119편 | 176 | | | | | |

**(D) 메모리 회수 — §18-3 (D) 재현 여부**

| 기기 | 시점 | footprint |
|---|---|---:|
| mini | 시편 119편 스크롤 완료 | |
| mini | 시편 120편(7절) 진입 6초 후 | |
| mini | 추가 25초 대기 | |
| Air | 시편 119편 스크롤 완료 | |
| Air | 시편 120편(7절) 진입 6초 후 | |
| Air | 추가 25초 대기 | |

**(E) 판정**

| # | 판정 기준 | 결과 |
|---|---|---|
| D5-1 | 크래시·jetsam 종료 없음 | |
| D5-2 | 절 수 대비 메모리 증분의 **형태**가 선형 | |
| D5-3 | 장 전환 후 미회수 현상 재현 | |
| D5-4 | 시편 119편의 hitch 가 창세기 1장 대비 유의하게 나쁨 | |
| D5-5 | mini vs Air 유의차 | |

> ⚠️ **이 표의 수치를 §18-3 표와 나란히 놓고 "개선/악화" 를 말하지 마십시오.** 이유는 §7-2.

### 8-5. §11 통과 기준 — 실기기 항목 (7~11)

| # | 기준 | 지금 판정 가능? | 관측 | 판정 |
|---|---|---|---|---|
| 7 | live stroke 가 pencil-up 순간 확대·이동하지 않음 | **아니오** — S4 spike 필요. D1-2 는 N-Canvas baseline | | |
| 8 | Pencil hover 중 좌표 변화 없음 | **아니오** — 위와 같음. D1-1 은 baseline | | |
| 9 | `.pencilOnly` 에서 한 손가락 스크롤 가능 | **아니오** — 옵션 B 구조 부재 | | |
| 10 | `allowFingerDrawing == true` 일 때 스크롤 방법이 명확 | **예** — D2-2 로 판정 | | |
| 11 | 시편 119편 layout 시간·peak memory (baseline 대비) | **부분** — memory/hitch 는 D5, layout 시간은 Phase 2 | | |

### 8-6. 후속 작업 / 설계 문서 반영 사항

| # | 발견 | 영향 | 반영할 곳 |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

---

## 9. 정리 — 기기 원복

검증이 끝나면:

**1) Debug 빌드 제거**

```bash
xcrun devicectl device uninstall app --device "$DEV" kr.co.carve.leetaek
```

✅ `devicectl device uninstall app` 하위 명령 존재 확인. 🔌 결과 미검증.

> ⚠️ **이 명령은 `Carve.dev.sqlite` 뿐 아니라 컨테이너 전체를 지웁니다.**
> **D8 덤프를 이미 저장소 밖에 확보했는지 확인한 뒤에 실행하십시오.**

**2) App Store 판 재설치**

App Store 에서 "새기다" 를 다시 설치하고, 같은 iCloud 계정으로 prod 컨테이너에서 동기화되는지 확인합니다.
동기화가 안 되면 §2-4 백업으로 복원합니다.

**3) 개발자 모드**

필요 없으면 iPad 설정 → 개인정보 보호 및 보안 → 개발자 모드 끄기.

**4) 덤프 정리**

`~/carve-device-dump/` 를 암호화 위치로 옮기거나 삭제 (§2-5).

**5) 저장소 정리**

```bash
git status --short   # 빌드 산출물이 저장소 안에 남지 않았는지 확인
```

---

## 10. 이 문서가 확인하지 **못한** 것

| # | 항목 | 왜 |
|---|---|---|
| 1 | **개발 서명 빌드 설치가 기존 데이터 컨테이너를 보존하는가** | ❓ 실기기 없이는 실증 불가. **D8 의 성패와 데이터 안전의 핵심 변수** |
| 2 | `devicectl device copy from --source` 가 `appDataContainer` 도메인에서 상대 경로를 어떻게 해석하는가 | 🔌 기기 연결 후 `device info files` 출력으로 맞추십시오 |
| 3 | `xcodebuild ... -destination 'generic/platform=iOS'` 빌드가 실제로 성공하는가 | 이 문서는 빌드를 실행하지 않았습니다. destination 유효성만 확인 |
| 4 | Xcode 27.0 beta 로 이 프로젝트가 문제없이 빌드되는가 | §18 은 Xcode 26.3 기록입니다. 이 머신에는 26.3 이 없습니다 |
| 5 | `xctrace record --attach` 가 실기기 프로세스에 이름으로 붙는가 (pid 필요한가) | 🔌 연결 후 확인 |
| 6 | 기기의 `Carve.sqlite` 스키마·테이블명 (`ZBIBLEDRAWING` 등) | 🔌 연결 후 `sqlite3 .schema` 로 확인. §18-3 이 `ZLINEDATA` 를 쓴 것으로 미루어 짐작만 함 |
| 7 | Stage Manager 에서 세로 고정 + scene manifest 부재 앱이 어떻게 처리되는가 | ❓ D6 이 답할 질문 |
| 8 | prod CloudKit 컨테이너에 실사용 데이터가 **전부** 올라가 있는가 | ❓ 확인 수단 없음. 백업을 필수로 두는 이유 |
| 9 | Apple 이 제시하는 hitch time ratio 절대 임계값 | ❓ 이 문서에서 단정하지 않습니다. A/B 상대 비교로 판정 |
| 10 | 백업에서 앱 컨테이너만 추출하는 CLI 경로 | ✅ 이 머신에 도구 없음을 확인 (libimobiledevice / Apple Configurator 미설치) |
