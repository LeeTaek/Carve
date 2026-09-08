# Carve 실기기 조작 및 표시 진단 절차

2026-09-08에 실제 실행한 CLI 중심 절차다. 대상은 iPad이며 테스트에 Xcode MCP를 사용하지 않는다. D9 H 결과·구현안은 [회전 표시 결함 조사](./single-canvas-rotation-display-investigation.md), 일반 백업·성능·필기 검증은 [실기기 런북](./phase-0a-d-device-test.md)을 따른다.

> ⚠️ **2026-09-08 인자 의미가 바뀌었습니다.** 표시용 획 재구성이 **정식 경로**가 됐으므로
> (`ef053111`) 예전의 `-CanvasFreshStrokesOnApply` 는 사라졌습니다. 지금 남은
> **`-CanvasReuseStrokesOnApply` 는 의미가 정반대**입니다 — 수정을 **끄고 결함을 재현하는**
> Debug 전용 opt-out 이며, 회전 왕복 A/B 의 양성 대조와 긴 장 성능 비교에만 씁니다.
> **기본 검증은 이 인자 없이** 돕니다.

## 1. 도구와 기기 확인

저장소 루트에서 실행한다. Xcode 앱 경로와 기기 식별자는 머신마다 다시 조회한다.

```bash
xcode-select -p
xcodebuild -version
xcrun devicectl list devices
xcrun devicectl device orientation set --help
xcrun devicectl device process launch --help
```

빌드는 **Xcode 26.3 / 17C529**를 사용한다. 이번 Mac에서는 `/Applications/Xcode.app/Contents/Developer`가 이미 선택돼 있어 `DEVELOPER_DIR`를 지정하지 않았다. 다른 버전이 선택된 머신에서만 실제로 설치된 26.3 경로를 찾아 지정한다. Tuist는 반드시 `mise x -- tuist`로 실행한다.

아래 변수를 설정한다. 새 터미널을 열면 다시 설정해야 한다. UUID에는 위 목록에서 **iPad mini(A17 Pro)**의 Identifier를 넣고, iPhone을 고르지 않는다.

```bash
CARVE_DEVICE_ID='<devicectl에서 조회한 iPad의 Identifier>'
CARVE_DEVICE_BUILD='/tmp/carve-device-build'
CARVE_DEVICE_LOGS='/tmp/carve-device-logs'
mkdir -p "$CARVE_DEVICE_LOGS"

xcrun devicectl device info details --device "$CARVE_DEVICE_ID"
xcrun devicectl device info lockState --device "$CARVE_DEVICE_ID"
```

`transportType: wired`, Developer Mode, 기기 잠금을 확인한다. 이번 실측은 iPad mini(A17 Pro), iPadOS 27.0 beta `24A5408d`, USB였다. Instruments 기록은 USB가 필수다. `devicectl`의 CoreDevice UUID와 `xcodebuild`/`xctrace`의 하드웨어 UDID를 섞지 않는다. 하드웨어 UDID가 필요하면 `xcrun xctrace list devices`로 확인한다.

Codex 샌드박스에서는 CoreDevice 초기화 timeout이나 CoreSimulator connection invalid가 발생했다. 같은 명령을 도구의 `sandbox_permissions: require_escalated`로 재실행해 해결했다. 이를 곧바로 기기·OS 고장으로 판정하거나 시스템 설정을 바꾸지 않는다. `mise` 캐시 접근 실패도 같은 방식으로 재실행했다.

## 2. 빌드와 업데이트 설치

```bash
mise x -- tuist generate --no-open
xcodebuild build -workspace Carve.xcworkspace -scheme CarveApp \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$CARVE_DEVICE_BUILD" -allowProvisioningUpdates \
  > "$CARVE_DEVICE_LOGS/build.log" 2>&1
```

명령 종료 코드와 `BUILD SUCCEEDED`를 확인한 뒤 설치한다. 위 `/tmp` 빌드 경로는 재사용 가능한 예시다. 조사 당시에는 이미 있던 `/Users/leetaek/carve-build/device` 캐시를 재사용했으며 이 경로를 다른 머신에 하드코딩할 필요는 없다.

```bash
xcrun devicectl device install app --device "$CARVE_DEVICE_ID" \
  "$CARVE_DEVICE_BUILD/Build/Products/Debug-iphoneos/CarveApp.app"
```

앱을 uninstall하지 않고 업데이트 설치한다. 이번에는 기존 필기가 유지됐다. 기존 데이터의 백업 정책은 런북 §2-4를 따르며, 이 세션에서 신규 전체 기기 백업을 만들었다는 뜻은 아니다. 실기기 저장소·앱 상태를 초기화하거나 표본을 다른 버전으로 승격시키지 않는다.

## 3. 실행 및 콘솔 로그 수집

기본 경로 재현용 실행이다. 먼저 가로 방향으로 만든다.

```bash
xcrun devicectl device orientation set --device "$CARVE_DEVICE_ID" landscapeLeft
xcrun devicectl device process launch --device "$CARVE_DEVICE_ID" \
  --terminate-existing --console kr.co.carve.leetaek -- \
  -SingleCanvas -ChapterLayoutOverlay -CanvasDisplayProbe \
  > "$CARVE_DEVICE_LOGS/baseline.log" 2>&1
```

`--` 뒤가 앱 실행 인자다. `--console` 명령은 앱이 끝날 때까지 유지된다. 일반 터미널에서는 이 창을 그대로 두고 다른 터미널에서 회전 명령을 실행한다. Codex에서는 짧은 yield로 `exec_command`의 session ID를 받은 뒤 별도 호출로 회전했다. `functions.wait`의 cell ID와 셸 실행의 session ID를 혼동하지 않는다.

로그는 다음처럼 필요한 줄만 읽는다.

```bash
rg 'CanvasDisplay (create|apply|sample|finish|experiment)' "$CARVE_DEVICE_LOGS/baseline.log"
```

`sample`의 `store / delivered / applied`, `attached`, `storeDiff`, `deliveredDiff`, 전체 bounds, offset/zoom/transform을 본다. `finish`의 `appliedAtCallback`은 완료 세대가 아니다. 전체 콘솔이나 기기 정보에는 작업과 무관한 식별 정보가 있을 수 있으므로 공유 기록에는 필요한 값만 추린다.

## 4. 회전과 화면 판정

```bash
xcrun devicectl device orientation set --device "$CARVE_DEVICE_ID" portrait
# 로그에서 새 revision과 레이아웃이 안정된 것을 확인하고 화면을 판정한다.
xcrun devicectl device orientation set --device "$CARVE_DEVICE_ID" landscapeLeft
```

**방향은 위치 인자다. `--orientation portrait`가 아니다.** 이 툴체인의 `--help`와 실제 실행으로 확인했다. 명령 성공은 방향 설정 성공일 뿐 필기 표시 정상의 증거가 아니다. 매 단계에서 화면 판정을 먼저 남기고 다음 실험을 진행한다.

이번 세션은 CLI 로그를 수집하면서 사용자에게 “필기가 오른쪽/왼쪽으로 밀렸는가, 정상화됐는가”를 물어 실제 화면 결과를 얻었다. 필기를 새로 입력할 필요가 없다. 시편 120편의 legacy 2·4절은 증거 표본이므로 건드리지 않는다.

### 화면 캡처와 GUI의 범위

- 이번에 사용한 `devicectl` 명령에는 스크린샷 캡처 명령이 없었다. 원본 PNG는 사용자가 제공했고 새 실험의 화면은 사용자 확인으로 판정했다.
- Xcode의 **Window → Devices and Simulators → 기기 선택 → Take Screenshot** UI 경로가 존재한다. 이번에는 메뉴와 버튼까지만 확인했고 **대상 iPad 캡처 성공은 확인하지 못했다.** “자동 캡처 성공”으로 기록하지 않는다.
- Codex에서 GUI를 확인할 때는 CUA의 `cua.getApp('com.apple.dt.Xcode')` 후 최신 AX 상태를 읽고 메뉴를 조작했다. 사용자 창이 바뀌었다는 응답이 오면 이전 element index로 계속 클릭하지 않는다. 빌드·테스트는 계속 CLI로 수행한다.
- 실제 필기·지우개 입력은 이 세션에서 자동 주입하지 않았다. 다른 앱이나 본문 위를 클릭해 필기를 만들지 않는다.

## 5. 명시적인 수동 표시 실험

이 절은 조사 코드가 있는 **Debug 전용**이다. 아래 두 인자가 함께 있어야 원격 실험 명령을 받는다. 자동 비교 인자 `-CanvasReuseStrokesOnApply`는 함께 넣지 않는다.

```bash
xcrun devicectl device process launch --device "$CARVE_DEVICE_ID" \
  --terminate-existing --console kr.co.carve.leetaek -- \
  -SingleCanvas -ChapterLayoutOverlay -CanvasDisplayProbe -CanvasDisplayExperiments \
  > "$CARVE_DEVICE_LOGS/experiments.log" 2>&1
```

다른 터미널에서 회전해 증상을 만들고 아래 명령을 **하나씩** 실행한다. 각각 `CanvasDisplay experiment` 로그와 화면 결과를 확인한다. 진단 코드는 미보고 편집 또는 진행 중 그리기 제스처가 있으면 동작을 건너뛴다. 통지가 도착했다는 로그만으로 실제 교체가 실행됐다고 단정하지 않는다.

```bash
# 1. 일반 다시 그리기/레이아웃 요청
xcrun devicectl device notification post --device "$CARVE_DEVICE_ID" \
  --name kr.co.carve.canvas-probe.redraw

# 2. 같은 drawing 재대입
xcrun devicectl device notification post --device "$CARVE_DEVICE_ID" \
  --name kr.co.carve.canvas-probe.reassign

# 3. 표시를 비우고 같은 drawing을 즉시 복원
xcrun devicectl device notification post --device "$CARVE_DEVICE_ID" \
  --name kr.co.carve.canvas-probe.clear

# 4. 증상을 다시 만든 뒤 같은 공개 속성으로 새 획 생성
xcrun devicectl device notification post --device "$CARVE_DEVICE_ID" \
  --name kr.co.carve.canvas-probe.fresh
```

3·4번은 표시 drawing을 바꾸는 실험이다. `isApplyingDrawing`으로 편집 보고를 억제하며, 이 억제를 제거하면 안전성 테스트가 실패하는 것을 확인했다. `clear`를 DB 삭제 명령으로 구현하거나 원본 표본에 새 필기를 추가하지 않는다.

## 6. 양성 대조(결함 재현) 모드와 종료

```bash
xcrun devicectl device process launch --device "$CARVE_DEVICE_ID" \
  --terminate-existing --console kr.co.carve.leetaek -- \
  -SingleCanvas -ChapterLayoutOverlay -CanvasDisplayProbe -CanvasReuseStrokesOnApply \
  > "$CARVE_DEVICE_LOGS/reuse-apply.log" 2>&1
```

§4대로 가로 → 세로 → 가로를 수행한다. **이 모드에서는 필기가 밀리는 결함이 재현돼야 정상이다** — 수정을 끄는 opt-out 이기 때문이다. 기본 검증(인자 없음)이 정상이고 이 모드가 결함을 재현하면 양성 대조가 성립한다. 2026-09-08 A/B 에서 실제로 그렇게 나왔다 ([조사 문서](./single-canvas-rotation-display-investigation.md) §3).

`--console` 프로세스에 Ctrl-C를 보내면 신호가 앱으로 전달될 수 있다(`process launch --help`). 이번에는 **콘솔 없이 앱을 다시 실행**해 이전 수집을 끝내고 비교 모드의 앱을 남겼다.

```bash
xcrun devicectl device process launch --device "$CARVE_DEVICE_ID" \
  --terminate-existing kr.co.carve.leetaek -- \
  -SingleCanvas -ChapterLayoutOverlay -CanvasReuseStrokesOnApply
```

기본 경로로 돌아가려면 위 실행에서 `-CanvasReuseStrokesOnApply`를 뺀다. 재실행은 미저장 필기가 없는 진단 상황에서 한다. 종료 기록에는 마지막 실행 인자를 남겨 다음 사람이 비교 모드를 정식 수정으로 오해하지 않게 한다.

## 7. 시뮬레이터와 기록 체크

```bash
xcrun simctl list devices available
xcodebuild test -workspace Carve.xcworkspace -scheme CarveFeatureTest \
  -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=26.2' \
  -only-testing:CarveFeatureTest/ChapterCanvasControllerTesting \
  -only-testing:CarveFeatureTest/SingleCanvasDisplayWiringTesting

xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace \
  -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=26.2'
```

실제 사용 가능한 iPad 이름·OS로 조정한다. 이번에는 iPhone 시뮬레이터도 켜져 있었지만 검증 destination에는 사용하지 않았다. 함수 단위 `only-testing`으로 0개가 실행된 사례가 있으므로 `TEST SUCCEEDED`만 보지 말고 실제 실행 개수도 확인한다. 현재 전체 기준선은 304개이며 [설계 §19-4-2](./single-canvas-design.md)를 기준으로 유지한다.

기록할 항목은 기기·OS build·Xcode·USB 상태, 코드 revision/diff, **전체 실행 인자**, 회전 순서, 안정 후 로그, 사용자 또는 스크린샷의 화면 판정, 실제 테스트 개수와 종료 코드, 미검증 항목이다. `Activity Monitor`를 이용한 성능 기록은 기존 런북을 따르며 이 세션에서 새 성능 측정을 완료한 것으로 적지 않는다.
