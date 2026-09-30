# 실기기 · 시뮬레이터 검증 요령

> 2026-09-30 에 [AGENTS.md](../AGENTS.md) 에서 옮겨 왔다. 매 세션 읽는 AGENTS.md 에는 어기면 데이터나 검증이 망가지는 규칙만 한 줄씩 남겼다.
> 실기기 검증 절차 전문은 [런북](./phase-0a-d-device-test.md), 실기기 CLI 조작은 [device-debugging-cli.md](./device-debugging-cli.md) 에 있다.

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
- **터치 자동화는 OS 와 입력 경로에 따라 다르다.** iPadOS 18.6 시뮬레이터는 `손가락 필사 허용` 을 켜면 합성 드래그 획이 저장되지만,
  **17.5 시뮬레이터는 허용을 켜도 획이 남지 않는다**(스크롤이 드래그를 가져간다). 어느 쪽도 Apple Pencil 입력을 뜻하지 않는다.
  **업데이트 · CloudKit 표본이 든 시뮬레이터는 조작하지 않는다.** `simctl clone` 은 격리가 아니다 — 같은 계정 · Development private DB 를
  공유할 수 있고, `get_app_container` 가 원본 경로를 돌려준 적이 있다. 독립 peer 는 새 기기로 만든다.
  화면 확인은 안전한 synthetic 표본과 Debug 전용 실행 인자 시나리오로 한다:
  `-ChapterLayoutAutoScroll`(11단계 스크롤) · `-ChapterLayoutAutoNext`(다음 장) · `-ChapterLayoutOverlay`(레이아웃 오버레이·HUD) ·
  `-SingleCanvas`(단일 Canvas 경로 강제 — Phase 3 flag `singleCanvasEnabled` 와 같은 효과, 기본은 단일 Canvas. 앱 안에서는 **설정 > 필사 캔버스** 토글, 키는 Domain `SingleCanvasFlag`).
- **표시 진단 인자(Debug 전용, 주로 실기기).** `-CanvasDisplayProbe`(읽기 전용 상태·drawing 샘플링) · `-CanvasDisplayExperiments`(원격 실험 명령 수신) ·
  ⚠️ **`-CanvasReuseStrokesOnApply` 는 D9 H 수정을 끄고 결함을 재현하는 opt-out** 이다 — 기본 검증은 이 인자 **없이** 돈다. 절차는 `docs/device-debugging-cli.md`.
- **광고 제거 구매 · 복원은 `CarveApp-StoreKit` 스킴의 테스트로 본다** — `xcodebuild test -scheme CarveApp-StoreKit -destination <iPad 시뮬레이터> -only-testing:CarveAppUITests/RemoveAdsStoreKitUITests`.
  스킴이 `CARVE_STOREKIT_UITEST=1` 을 넣고 UI 테스트 번들의 `Support/Carve.storekit` 으로 `SKTestSession` 을 연다. 표준 `Carve-Workspace` 실행에서는 건너뛴다.
  로컬 StoreKit 은 앱을 지우면 거래도 지우고, `buyProduct` 는 대상 앱이 한 번 떠 있어야 한다(설치 직후 실행 전에는 `unknown`).
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
