# Carve 프로젝트 지침

## 환경
- 이 저장소는 Tuist를 사용한다.
- 자동화 및 무인 검증에는 CLI 기반 워크플로를 우선 사용한다.
- 자동화 및 무인 검증에서는 테스트 실행에 Xcode MCP를 의존하지 않는다.
- 명시적으로 요청되지 않은 한 의존성 버전이나 빌드 설정은 수정하지 않는다.
- 이 앱은 iPad 전용이다. 빌드나 테스트 검증 시 iPhone destination을 사용하지 않는다.

## 아키텍처
- 기존의 TCA + MicroArchitecture 구조를 따른다.
- 현재 모듈 경계를 유지하는 작고 국소적인 변경을 우선한다.
- 작업과 무관한 광범위한 리팩토링은 피한다.

## 검증
- 검증은 Xcode MCP가 아니라 CLI 기반으로 수행한다.
- 항상 가장 좁은 관련 테스트 범위부터 실행한다.
- 기본 검증 경로는 `xcodebuild test`를 우선 사용한다.
- Tuist 특화 흐름이나 selective testing이 필요할 때는 `tuist test`를 사용한다.
- CLI 검증을 수행할 때는 iPhone simulator가 아니라 iPad simulator destination을 사용한다.

## 툴체인 제약 ★ 먼저 읽을 것

**현행 작업 및 출시 후보의 주 검증 대상은 현재 호스트의 Xcode 27.0 / macOS 27.2다.** 기본 선택과 다른 Xcode를 임의로 바꾸지 말고, 실행 때 선택된 툴체인을 기록한다. Device Hub는 기기 확인·수동 스모크에 사용하며 컴파일러나 CLI 테스트를 대체하지 않는다.

| 버전 | 결과 |
|---|---|
| **Xcode 27.0** | 🎯 현행 주 검증·출시 후보 자격 확인 대상 (macOS 27.2). Tuist workspace Debug iPad simulator build와 전체 회귀가 iPadOS 17.5에서 998 통과·18.6/26.2/26.4/26.5에서 각각 999 통과·27.0에서 998 통과(각 총 1008, expected failure·skip 포함)했다. 초기 F60의 XCFramework 서명 실패는 재현되지 않았다. iOS 27 SwiftData error mapping은 확인된 1.0.x metadata에만 대응하도록 수정했다. iOS 17.5 로그의 임시 fixture SQLite 경고는 테스트 실패/runtime warning이 아니며 정리 시점 후속 분석이 남았다. live CloudKit proof와 서명 Archive·TestFlight는 미완료 |
| **Xcode 26.3** | 🧪 알려진 회귀 비교 기준 (17C529 / Swift 6.2.4). **2026-09-24 파일 제외 없는 전체 `Carve-Workspace` 회귀:** iPadOS 17.5는 998 통과·실패 0·6 skip·4 expected failure, iPadOS 18.6·26.2는 각각 999 통과·실패 0·5 skip·4 expected failure (각 총 1008). 이 결과는 Xcode 26.3에서만 얻은 과거 기준선이며 Xcode 27 검증을 대신하지 않는다. V1 migration 수정과 미완성 초안 이동 기록은 호환성 시험 계획에 있다. **2026-09-28:** `aebb5e63`(09-25)의 iOS 27 전용 `SwiftDataError.unknownDataStoreSchema` 때문에 HEAD가 Xcode 26.3에서 컴파일되지 않던 것을 `#if compiler(>=6.4)`로 고친 뒤 다른 Mac(macOS 26.3)에서 재실행 판정 수정까지 반영한 코드가 26.2·18.6 각 1022, 17.5 1021 통과(실패 0, 총 1032) — 상세는 호환성 시험 계획 09-28 절 |
| Xcode 26.6 | ⚠️ **미확인**. 과거 TCA **1.20.2** 에서 Swift 6.3.3 컴파일 실패했으나(`WritableKeyPath<Root, BindingState<Value>>` 의 `Sendable` 미충족) 그 핀은 더 이상 쓰지 않는다. 1.23.2 가 "Xcode 26.4 support" 를 넣었으므로 재확인 필요 |

Xcode 26.6은 미확인이다. TCA 1.20.2 + Swift 6.3.3에서 난 컴파일 오류는 과거 관측이며 현재 의존성의 결과로 일반화하지 않는다. Xcode 27.0 최초 generic-project F60 기록은 Swift 소스 컴파일 전 XCFramework 서명 실패였지만, 생성 workspace 재검증에서는 해당 단계가 통과했고 앱 컴파일·iPadOS 17.5/18.6/26.2/26.4/26.5/27.0 전체 회귀도 통과했다. iOS 27 SwiftData의 `.unknownDataStoreSchema` 분기 수정은 로컬 회귀 결과이며 live CloudKit proof·배포 자격을 대신하지 않는다. 경위는 [호환성 시험 계획](docs/icloud-sync-compatibility-test-plan.md)과 [핸드오프](docs/release-2.0.0-migration-sync-handoff.md)에 기록한다.
경위는 [로드맵 §4 TECH-0](docs/release-2.0.0-roadmap.md) 에 있다.

**현재 환경 스냅샷 (2026-09-24):** 이 Mac은 macOS 27.2 (26B5086k), 기본 Xcode 27.0 (27A266a)이며 `xcode-select -p`는 `/Applications/Xcode.app/Contents/Developer`를 가리킨다. Tuist 4.208.0은 `.mise.toml`로 고정돼 있다. Device Hub가 실행 중이고, 기본 Xcode 27 선택 상태에서는 이 세션의 `xcrun simctl list runtimes`와 `list devices available`이 성공했다. Xcode 26.3을 `DEVELOPER_DIR`로 지정한 sandbox 호출은 CoreSimulatorService 연결·로그 경로 권한 오류를 냈고, 권한을 높여 재확인하자 런타임 목록 조회가 성공했다. 확인한 runtime은 iOS 17.5·18.6·26.2·26.4·26.5·27.0이며 iOS 19~25는 현재 목록에 없다. iPad mini (6th generation) iOS 17.5 simulator (UDID `0347221E-08F5-48C9-9F8E-6D7995C25D9F`)에서 Xcode 26.3 전체 회귀를 수행했다. Device Hub에는 iPadOS 27.2 실기기가 보이고, 검사 당시 iPad (A16) iPadOS 18.6 simulator가 선택돼 있었다. 기기 상태는 검사 시점의 스냅샷이며 작업마다 다시 확인한다.

Xcode 26.3도 현재 Mac에 `/Applications/Xcode-26.3.0.app/Contents/Developer`로 설치돼 있다. 다른 Mac에서는 경로를 추측하지 말고 아래 명령으로 실제 위치와 버전을 확인한다. 기본 선택된 Xcode 27을 주 검증 대상으로 사용한다. Xcode 26.3과 비교할 때만 실제 경로를 확인한 뒤 `DEVELOPER_DIR`를 명시하고, 결과를 별도 툴체인 결과로 기록한다.

```bash
xcode-select -p
xcodebuild -version
mise x -- tuist version
xcrun simctl list runtimes
find /Applications -maxdepth 1 -name 'Xcode*.app' -print
```

```bash
# 알려진 과거 회귀 기준과 비교할 때만 사용한다. 경로는 실행 전에 확인한다.
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild -version
```

**tuist 는 `.mise.toml` 로 4.208.0 에 고정돼 있다.** `PATH` 기본값과 다르므로 반드시
`mise x -- tuist ...` 로 실행한다.

## 공통 명령어

```bash
# 기본 선택된 Xcode 27에서 우선 검증한다. 실행한 Xcode·Swift·runtime을 결과에 기록한다.

mise x -- tuist generate --no-open        # ★ .xcodeproj 는 gitignore — 클론·브랜치 전환 후 반드시 먼저
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace \
  -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=26.2'
mise x -- swiftlint lint --quiet --config .swiftlint.yml <파일들>
```

- 회귀 기준선은 `docs/single-canvas-design.md` §19-4-2 에 기록돼 있다. **줄어들면 회귀다.**
- SwiftLint 주의: `identifier_name` 최소 길이 **2** (`x`/`y`/`id` 만 예외),
  `line_length` 180, `type_body_length` 300.
- 툴체인을 바꾼 뒤에는 `DerivedData` 를 지우고 클린 빌드한다. 다른 Swift 버전이 만든
  모듈 캐시가 남아 있으면 `unable to resolve module dependency` 로 실패한다.
- **매크로를 쓰는 의존성(TCA 등)의 버전을 바꾼 뒤에도 똑같이 클린 빌드한다.** 매크로 타깃은
  재컴파일돼도 컴파일러가 실제로 로드하는
  `DerivedData/…/Build/Products/Debug-iphonesimulator/<Macros>` 사본은 갱신되지 않을 수 있다.
  낡은 플러그인이 새 라이브러리와 짝이 맞지 않으면 자사 코드와 무관해 보이는 적합성 오류가 난다
  (2026-09-09 TCA 1.26.2 에서 `type 'AppVersionFeature.Path' does not conform to protocol
  'CaseReducer'`). 진단은 빌드 로그의 `-load-plugin-executable` 경로와 그 바이너리 타임스탬프를
  본다. `xcodebuild clean` 이면 풀린다.

## 실기기 검증

절차 전문은 `docs/phase-0a-d-device-test.md` 에 있다.
**단일 Canvas 검증(D9)은 그 문서 §6-9, 기록 양식은 §8-7** — 설계 §13 의 마지막 게이트다.
**실기기 CLI 조작(빌드·설치·회전·로그 수집·표시 진단)은 `docs/device-debugging-cli.md`** 를 따른다. 요점만:

- **Instruments 기록에는 USB 연결이 필수다.** Wi-Fi(`Transport Type: localNetwork`)에서는
  1~2초 만에 `Device disconnected` 로 끊기고, `Deferred` 모드라 그때까지의 데이터도 유실된다.
  `xcrun devicectl device info details --device <id> | grep "Transport Type"` 로 확인한다.
- **`Allocations` 템플릿은 쓰지 않는다.** 오버헤드가 커서 앱이 사실상 멈춘다.
  메모리·CPU 측정에는 **`Activity Monitor`** 를 쓴다(`sysmon-process` 스키마의
  `memory-physical-footprint` 가 목표 지표다).
- **기기 식별자가 도구마다 다르다.** `devicectl` 은 CoreDevice UUID,
  `xctrace` 와 `xcodebuild -destination` 은 하드웨어 UDID 를 쓴다.
  `xcrun xctrace list devices` 로 확인한다.
- 앱 인자를 넘길 때는 `--` 로 구분한다:
  `xcrun devicectl device process launch --device <id> <bundle> -- -MyFlag`
- **실기기 UI 테스트는 시작 장을 인자로 정한다** — `-UITestChapter <BibleChapter JSON>`(Debug 전용, `UITestLaunchChapter`,
  UITests 에서는 `startChapterArguments`). 앱은 마지막으로 연 장에서 시작하므로 인자 없이는 기기 상태에 따라 결과가 갈린다.
  헤더 다음 장 버튼(`nextChapter`)과 절 메뉴 항목(`verseMenu.favorite` · `history` · `image` · `widget` · `erase`)은 접근성 이름이 아니라 식별자로 찾는다.
  절 메뉴는 2026-09-15 부터 필기가 없는 절에서도 「즐겨찾기」 로 뜬다 — 「이전 필사 내용 보기」 는 보관본이, 「지우기」 는 필기가 있어야 보인다.
  메뉴 항목은 누르지 않는다(「지우기」 는 실제 필사를 비우고 「즐겨찾기」 는 실제로 저장되며 「이미지 저장」 은 사진 추가 권한을 묻고 사진 보관함에 넣고 「위젯에 추가」 는 즐겨찾기에 보관하고 위젯 목록을 바꾼다). 즐겨찾기한 절 번호는 이름 「1절」 을 그대로 두고 값 「즐겨찾기」 만 더한다.
  누를 좌표는 **보이는 요소 기준**으로 만든다(절 메뉴는 「1절」 번호와 필사 열 라벨, 드래그는 창 기준 `windowPoint`). 창 모드(iPadOS 창 버튼)에서는
  앱 좌표 원점이 화면 원점이라 `app.coordinate` 에 창 크기 비율을 더한 좌표가 창 위치만큼 어긋난다 (2026-09-15 창 y=177 에서 헤더 위를 눌러 실패).
  사이드바(즐겨찾기 · 차트 · 설정)는 **가로에서도 접혀 있을 수 있다** — 「즐겨찾기」 가 트리에 없으면 먼저 「사이드바 보기」 버튼을 누른다 (2026-09-16).
  **새로 만든 시뮬레이터는 첫 실행 안내(FirstRunGuideView)가 롱탭을 먹는다** — 절을 누르기 전에 「건너뛰기」 버튼이 있으면 먼저 누른다 (2026-09-16).
- 기록 중에는 **`pgrep`/`pkill` 로 프로세스를 건드리지 않는다.** 마무리 단계에 끼어들면
  트레이스가 템플릿 메타데이터 없이 저장되어 `xctrace export` 가 실패한다.

## 시뮬레이터 측정

설계 §18-3 의 절차를 이 머신에서 재현할 때 (Phase 2 에서 확인):

- **Phase 2 측정 Mac에서는 `vmmap` 이 권한 오류로 실패했다** (`Failed to get DYLD info for task`). 같은 physical footprint 는
  `/usr/bin/footprint <pid>` 로 읽는다. CPU 는 §18-3 그대로 `ps -o time=` 델타. Mac이 바뀌면 권한 오류가 재현되는지 다시 확인한다.
- **`Log.debug` / `Log.info` 는 `log show` 에 남지 않는다.** 앱을 띄우기 **전에**
  `xcrun simctl spawn <UDID> log stream --level debug --predicate 'subsystem == "kr.co.carve.leetaek"'`
  를 붙여야 보인다. `PKCanvasView` 생성 1회당 `com.apple.pencilkit` 의 `isGenerationToolEnabled` 가 **1줄** 찍힌다
  (단일 Canvas 실행에서 정확히 1줄로 확인 — rev.15 문서의 "3줄" 은 정정). 캔버스 생성 횟수는 이 줄 수로 센다.
- **터치 자동화는 경로에 따라 다르다.** Phase 2의 이전 Mac에서는 `xcode-select`가 CLT를 가리켜 시뮬레이터 제어가 막혔고 `touch_path`도 동작하지 않았다(S4 §20-4). 현재 macOS 27.2 / Xcode 27.0 Mac에서는 Device Hub가 열리고 `simctl` 목록 조회가 된다. F59에서 별도 iPadOS 18.6 simulator의 `손가락 필사 허용`을 켠 뒤 Device Hub 포인터 드래그가 저장되는 것은 확인했지만, 이 결과는 Apple Pencil 입력이나 일반 터치 자동화 성공을 뜻하지 않는다. 업데이트·CloudKit 표본이 든 simulator는 만지지 말고, 안전한 synthetic 표본과 Debug 전용 실행 인자 시나리오를 쓴다:
  `-ChapterLayoutAutoScroll`(11단계 스크롤) · `-ChapterLayoutAutoNext`(다음 장) · `-ChapterLayoutOverlay`(레이아웃 오버레이·HUD) ·
  `-SingleCanvas`(단일 Canvas 경로 강제 — Phase 3 flag `singleCanvasEnabled` 와 같은 효과, 기본은 단일 Canvas. 앱 안에서는 **설정 > 필사 캔버스** 토글, 키는 Domain `SingleCanvasFlag`).
- **표시 진단 인자(Debug 전용, 주로 실기기).** `-CanvasDisplayProbe`(읽기 전용 상태·drawing 샘플링) · `-CanvasDisplayExperiments`(원격 실험 명령 수신) ·
  ⚠️ **`-CanvasReuseStrokesOnApply` 는 D9 H 수정을 끄고 결함을 재현하는 opt-out** 이다 — 기본 검증은 이 인자 **없이** 돈다. 절차는 `docs/device-debugging-cli.md`.
- **장 지정 시드는 저장된 앱 상태에 밀린다.** 앱이 한 번 장을 바꾼 뒤에는 컨테이너의
  `Library/Saved Application State` 가 마지막 장을 복원해, `title` 을 어느 plist 에 써도 무시된다
  (Phase 2 에서 시편 120편이 뜨는 무효 측정을 여러 번 했다). **`xcrun simctl uninstall <UDID> kr.co.carve.leetaek` 로
  컨테이너를 비운 뒤** 설치 → `xcrun simctl spawn <UDID> defaults write kr.co.carve.leetaek title -data <BibleChapter JSON 의 hex>` → 실행.
  시드가 먹었는지는 앱 로그의 `ChapterLayout 완성: <권>.<장>` 으로 반드시 확인한다. (dev sqlite 도 함께 지워진다 — 시뮬레이터에는 테스트 행뿐이다.)
  hex 예 — 시편 119편 `7b227469746c65223a2022312d31395073616c6d732e747874222c202263686170746572223a203131397d`,
  창세기 1장(소제목 있음) `7b227469746c65223a2022312d303147656e657369732e747874222c202263686170746572223a20317d`.
- **레이아웃 검증은 두 경로 모두 HUD 로 본다** — `-ChapterLayoutOverlay` 와 `-SingleCanvas -ChapterLayoutOverlay` 에서 `Δ max 0.00` 이고 `columnX` 가 `W`(= 컬럼 폭의 절반, 오른손 · iPad mini 세로 372.00) 와 같아야 하고, 단일 Canvas 에서는 `guard OPEN` 이어야 한다.
  ⚠️ **`Δ max` 는 컬럼 신장(R16) 계열을 잡지 못한다** — 행 높이가 실측 입력이라 레이아웃이 늘어난 렌더를 따라가기 때문이다(설계 §20-14).
  그 계열은 `H`(totalHeight)를 새 진입값과 비교해 본다 (런북 §6-9 D9-0-d).
  행 안의 `onGeometryChange` 는 중첩 `UIHostingController`(`touchIgnoringContextMenu`) 때문에 바깥 `.named` 공간을 보지 못하고 **조용히 global 을 쓴다** —
  그래서 행 frame 은 바깥 트리에서 재고 행 안 영역과 합친다(설계 §6-1 rev.16). Δ 가 0 이 아니면 레이아웃보다 측정 경로를 먼저 의심한다.
  ⚠️ **저장 당시 줄 수가 지금보다 많은 필사 절(slack)이 있어도 `Δ max 0.00` 이 기대값이다.** 레이아웃과 행은 텍스트 줄 수만큼만 차지하고,
  잉크가 초과 줄에 걸쳐 있으면 reflow 가 그 절 안에 같은 비율로 줄여 보여 준다(설계 §6-3 · §9-3). HUD 의 `slack v1+1·… = N줄 · 초과 필기는 절 안 축소` 는 그 후보 절이다.
  2026-09-14 실기기 시편 119편 `Δ max 195.63`(v1·v2·v4 +1) · 가로 586.90 은 레이아웃만 초과 줄만큼 늘리던 §6-3 Pass 2 의 결함이었다 (2026-09-15 제거).

## 변경 정책
- 변경은 최소 범위로 유지한다.
- 폴더 구조를 재구성하지 않는다.
- 의존성을 업데이트하지 않는다.
- 명시적으로 요청되지 않은 한 CI, signing, build setting은 변경하지 않는다.

## 출력
- 작업에 다른 언어가 명시적으로 필요하지 않은 한, 모든 assistant 응답, 코드 주석, 설명, 생성 문서는 한글로 작성한다.
- 변경한 파일과 변경 이유를 요약한다.
- 어떤 방식으로 결과를 검증했는지 요약한다.
- 남아 있는 위험 요소나 후속 작업이 있으면 함께 알린다.
