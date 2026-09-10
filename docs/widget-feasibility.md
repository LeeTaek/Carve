# 위젯 위험 확인 — WIDGET-0

작성: 2026-09-10 · 브랜치: `codex/widget-feasibility` · 상태: **가능 확인 완료 — 실기기·배포 서명은 미확인 (§6)**

## 0. 이 문서의 역할

로드맵 §7 은 절 이미지 저장·필사 위젯을 **"별도 합의 없이는 이월하지 않는 범위"** 로 못 박았다. 그런데 위젯은 2.0.0 범위에서 **새 타깃·공유 저장·서명이 걸리는 유일한 구조 변경**이다. 여기서 막히면 바뀌는 건 일정이 아니라 그 약속 자체다. 그래서 IMAGE·WIDGET 본 구현 전에 "된다/안 된다와 그 조건"만 먼저 확인했다.

이 문서는 **시뮬레이터에서 실제로 돌려 본 결과**다. 완성 UI 를 만들지 않았고 절 이미지 생성(IMAGE-CORE)도 구현하지 않았다 — 아무 더미 이미지로 경로만 증명했다. **실기기와 배포 서명은 확인하지 않았다**(§6). 추측과 관측을 구별해서 읽는다.

- 스파이크 코드는 `50b4296c` 에 있고 **이 커밋에서 제품 경로에서 되돌렸다**. 되살릴 구성은 §5 에 그대로 적어 뒀다.
- 검증 환경: Xcode 26.3 (17C529 / Swift 6.2.4) · tuist 4.39.0 · **iPad mini (A17 Pro) 시뮬레이터 iOS 26.2**.

---

## 1. 질문 1 — 위젯 타깃 추가가 현재 Tuist 구성과 자동 서명에서 그대로 되는가

### ✅ 된다. 기존 관용구를 바꿀 필요가 없었다

`Target+Templates.swift` 의 `makeAppTarget` 과 같은 모양으로 `makeWidgetExtensionTarget` 을 하나 더 만들면 끝이다. 다른 건 `product` 가 `.appExtension` 이고 Info.plist 에 `NSExtension` 이 들어간다는 것뿐이다.

| 확인 항목 | 결과 | 근거 |
|---|---|---|
| `Product.appExtension` 존재 | ✅ | tuist 4.39.0 `ProjectDescription.swiftinterface` L858 |
| `mise x -- tuist generate --no-open` | ✅ 성공 | `Project generated.` |
| `xcodebuild build -scheme CarveApp` | ✅ BUILD SUCCEEDED | |
| 앱 번들에 임베드 | ✅ `CarveApp.app/PlugIns/CarveWidget.appex` | `ls` |
| 위젯 갤러리 노출 | ✅ "새기다" 항목으로 뜬다 | 시뮬레이터 홈 화면 → 편집 → 위젯 추가 |
| 회귀 | ✅ **343 유지** (Swift Testing 341 + XCTest 2) | §7 |
| 위젯 타깃·스파이크 소스가 만든 새 경고 | ✅ **0 건** | 빌드 로그에서 `widget` 매칭 경고 0 |

**서명은 손대지 않았다.** `automaticCodeSigning(devTeam: "H4MSW7FUBB")` 은 `Project.makeModule(settings:)` 의 **프로젝트 레벨** 설정이라 새 타깃이 그대로 상속한다. 위젯 타깃 매니페스트에 서명 관련 키를 한 줄도 쓰지 않았고, `CODE_SIGN_STYLE = Automatic` · `DEVELOPMENT_TEAM = H4MSW7FUBB` 가 그대로 붙었다(`xcodebuild -showBuildSettings`).

⚠️ **단, 이건 시뮬레이터 한정이다.** 시뮬레이터 빌드는 앱·위젯 모두 `Signature=adhoc` · `TeamIdentifier=not set` 으로 서명된다(`codesign -dv`). 프로비저닝 프로파일을 전혀 쓰지 않으므로 **자동 서명이 실제로 통과했다는 증거가 아니다.** 실기기·배포 서명은 §6 에서 막힌 항목이다.

### 앱이 위젯 타깃에 의존해야 한다

Tuist 는 앱 타깃의 `dependencies` 에 위젯 타깃이 있어야 `PlugIns/` 에 임베드한다. 이 한 줄을 빠뜨리면 빌드는 성공하는데 위젯이 갤러리에 뜨지 않는다.

---

## 2. 질문 2 — 앱이 쓴 이미지를 위젯이 읽는 경로가 실제로 동작하는가

### ✅ 동작한다. SwiftData·CloudKit 을 위젯에서 열 필요가 없었다

설계 전제대로 위젯이 받는 건 **이미지 1장 + 권·장·절**뿐이다. App Group 컨테이너에 PNG 한 장과 작은 JSON 한 개를 놓고 위젯이 그것만 읽는다. Domain·SwiftData·TCA 를 위젯에 링크하지 않았다 — 위젯 타깃의 `dependencies` 는 **비어 있다**.

관측한 순서와 근거:

| # | 관측 | 근거 |
|---|---|---|
| 1 | 앱 설치만으로 App Group 컨테이너가 생성된다 | `xcrun simctl get_app_container <udid> kr.co.carve.leetaek groups` → `group.kr.co.carve.leetaek /…/Containers/Shared/AppGroup/<UUID>` |
| 2 | 앱이 그 컨테이너에 쓴다 | `WIDGET-0 seed: 기록 성공 (…/AppGroup/BE35245E-…)` · 컨테이너에 `designated-verse.png` · `designated-verse.json` 존재 |
| 3 | **위젯 프로세스가 같은 컨테이너에 닿는다** | `CarveWidget[…] container_create_or_lookup_app_group_path_by_app_group_identifier: success` |
| 4 | 위젯이 그 이미지와 권·장·절을 렌더한다 | 홈 화면 스크린샷 — 더미 이미지 + `창세기 1:1` 표시 |

`translation` 필드도 페이로드에 미리 넣어 뒀다. BIBLE-EN 이 들어오면 위젯의 대상 식별에 번역본이 필요하다(로드맵 §4 BIBLE-EN).

### ⚠️ 막혔다가 푼 것 — WidgetKit 은 이미지 면적에 상한이 있다

처음에는 위젯이 **아무것도 그리지 못하고 플레이스홀더만** 떴다. 원인은 아카이버가 이미지를 거부한 것이었다.

```
[com.apple.chrono:archiving] Widget archival failed due to image being too large [14]
  - (1200, 400), totalArea: 480000 > max[349905.600000].
[com.apple.chrono:timeline] Request ended for CarveVerseWidgetSpike:systemSmall:(noIntent)
  - error: WidgetKit.WidgetArchiver.ArchivingError.imageTooLarge(
      size: (1200.0, 400.0), maximumSize: (620.4000000000001, 564.0))
```

`UIGraphicsImageRenderer` 가 화면 배율(2x)로 그려 1200×400 픽셀이 됐고, `UIImage(data:)` 는 PNG 를 **scale 1.0** 으로 되살리므로 그대로 1200×400 **포인트**가 됐다. 렌더러 `format.scale = 1` 로 고정해 600×200(면적 120,000)으로 줄이니 통과했다(`Request ended … - success`).

**이건 IMAGE-CORE 로 넘어가는 제약이다.** 사진 앨범에 저장할 고해상도 절 이미지를 위젯에 그대로 줄 수 없다. 위젯용 축소 사본을 따로 만들어야 한다.

- 관측한 상한: **systemSmall 에서 면적 349,905.6 · `maximumSize (620.4, 564.0)`**. 이 값은 기기·패밀리별로 다를 수 있으며 **다른 패밀리에서는 재보지 않았다.**
- 실패 방식이 나쁘다 — 앱은 정상이고 위젯만 조용히 플레이스홀더로 남는다. 사용자에게는 "위젯이 안 나온다"로만 보인다. 로드맵 §6 의 "위젯·이미지 저장만 실패" 신호에 이 경로를 넣어 둔다.

---

## 3. 질문 3 — 위젯을 탭하면 앱의 해당 절로 들어가는가

### ✅ URL 은 온다. 절로 이동하는 배선은 아직 없다 (WIDGET 몫)

`widgetURL(_:)` → 앱 `.onOpenURL` 까지 **끝까지 관측했다**. 위젯을 탭하니 앱이 **콜드 런치**되고 쿼리가 그대로 도착했다.

```
CarveApp[34696] [kr.co.carve.leetaek:WidgetSpike] WIDGET-0 openURL:
  carve://verse?title=1-01Genesis.txt&chapter=1&verse=1&translation=NKRV
```

필요한 설정은 `CFBundleURLTypes` 에 `carve` 스킴 하나뿐이었다.

⚠️ **`xcrun simctl openurl` 로는 이 경로를 검증할 수 없다.** 다른 앱이 커스텀 스킴을 여는 형태라 SpringBoard 가 **`'새기다'에서 열겠습니까?` 확인창**을 띄우고, 사용자가 "열기"를 누르기 전에는 `onOpenURL` 이 호출되지 않는다. 처음에 이걸 "딥링크가 동작하지 않는다"로 오진했다. **위젯 탭에는 확인창이 없다** — 위젯은 자기 컨테이너 앱을 여는 것이라서 바로 들어온다. 앞으로 이 경로를 확인할 때는 `simctl openurl` 결과로 판단하지 않는다.

**아직 안 한 것:** `.onOpenURL` 이 URL 을 로그로 찍기만 한다. 실제 이동 배선은 넣지 않았다. 다행히 붙일 자리는 이미 있다 — `CarveNavigationFeature` 에 **`case moveToVerse(BibleVerse)`** 가 있고, 이 액션이 `selectedTitle` · `selectedChapter` · `currentTitle` 을 맞추고 `setScrollTarget(verse)` 와 `fetchSentence` 를 보낸다(`Feature/CarveFeature/Sources/Presentation/Carve/CarveNavigation/CarveNavigationFeature.swift:115`). URL → `BibleVerse` 변환과 `AppCoordinatorFeature` 를 통한 전달만 만들면 된다.

**"지정한 절" 포인터에 무엇을 담을지 (COMPAT-0 연결).** 위젯은 행(row)을 참조하지 않고 이미지 사본을 쓰므로 R27·R28 의 행 식별 결정이 풀리기를 기다리지 않아도 된다. 스파이크는 `titleRawValue` + `chapter` + `verse` + `translation` 을 담았다. ⚠️ 다만 `BibleTitle.rawValue` 는 **본문 파일명**(`"1-01Genesis.txt"`)이다(COMPAT-0 §1-3). 이걸 딥링크에 그대로 노출하면 BIBLE-EN 에서 번역본별 파일 경로가 바뀔 때 과거에 지정해 둔 위젯의 링크가 깨진다. **WIDGET 은 파일명이 아닌 안정 키를 쓸지 결정해야 한다**(§8).

---

## 4. 질문 4 — ⚠️ 다크 모드: 위젯은 앱의 `UIUserInterfaceStyle: Light` 를 상속하지 않는다

**로드맵의 WIDGET 완료 기준에 빠져 있던 항목이다. 확인했고, 실제로 깨진다.**

앱 Info.plist 는 `UIUserInterfaceStyle: Light` 로 고정돼 있다(`Plugins/ProjectDescriptionHelpers/InfoPlist.swift`). 위젯은 별도 번들이라 이 값을 읽지 않는다. 시뮬레이터 외관을 `xcrun simctl ui <udid> appearance dark` 로 바꿔 가며 4 단계를 관측했다.

| # | 시도 | 시스템 다크에서의 결과 | 판정 |
|---|---|---|---|
| 1 | 아무것도 안 함 | 위젯이 `colorScheme == .dark` 로 렌더. 검은 카드 위에 **흰 배경 더미 이미지가 그대로 떠 있다** | ⛔ **깨진다** |
| 2 | 위젯 **자신의** Info.plist 에 `UIUserInterfaceStyle: Light` 추가 | 여전히 `dark`. 타임라인 강제 리로드 후에도 같음 | ⛔ **무효** |
| 3 | 뷰에 `.environment(\.colorScheme, .light)` 주입 | 라벨은 `light` 로 바뀌고 글자색은 라이트가 되지만, `.containerBackground(.background, for: .widget)` 배경은 **여전히 검다** → 어두운 배경에 어두운 글자 | ⚠️ **절반만** |
| 4 | 3 + `.containerBackground(Color.white, for: .widget)` 로 배경을 명시 | 시스템이 다크여도 **흰 카드에 어두운 글자**. 흰 배경 이미지가 카드에 자연스럽게 이어진다 | ✅ **된다** |

관측 근거는 각 단계의 홈 화면 스크린샷이다(위젯이 자기 `colorScheme` 과 `widgetFamily` 를 화면에 찍도록 만들어 뒀다). 2 번은 빌드된 `.appex` Info.plist 에 키가 실제로 들어간 것(`plutil -p` 로 `"UIUserInterfaceStyle" => "Light"` 확인)과 타임라인 재요청 성공을 함께 확인한 뒤의 결과다.

**정리 — WIDGET 이 해야 할 일:**
- Info.plist 로는 못 막는다. **위젯 뷰에서 처리해야 한다.**
- 시맨틱 색(`.background` 등)은 위젯 호스트가 시스템 외관으로 해석한다. **배경은 명시 색으로 칠한다.**
- 또는 "지정 당시 이미지"를 흰 배경 전제로 만들지 말고 다크에서도 성립하게 설계한다. 어느 쪽을 고를지는 DESIGN-0 에서 정한다.
- 검증에는 **라이트·다크 양쪽 스크린샷**을 넣는다. 라이트만 보면 통과로 보인다.

---

## 5. 질문 5 — 위젯에 필요한 설정, 그리고 남길 것과 버릴 것

### 5-1. 필요한 설정 (WIDGET 이 그대로 복사할 것)

| 항목 | 값 | 위치 |
|---|---|---|
| 타깃 종류 | `product: .appExtension` | `Plugins/ProjectDescriptionHelpers/Target+Templates.swift` |
| 번들 ID | `kr.co.carve.leetaek.Widget` (앱 번들 ID + `.Widget`) | 같음 |
| destinations / deployment | `[.iPad]` · iOS 17.0 (앱과 동일) | 같음 |
| Info.plist 필수 키 | `NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension` | 같음 |
| 앱 → 위젯 의존 | 앱 타깃 `dependencies` 에 `.target(name: "CarveWidget")` — 없으면 임베드되지 않는다 | `App/CarveApp/Project.swift` |
| App Group | `group.kr.co.carve.leetaek` — **앱·위젯 entitlement 양쪽에** | `App/CarveApp/Support/Carve.entitlements` · `CarveWidget.entitlements` |
| 위젯 entitlement 범위 | App Group **만**. iCloud 컨테이너는 주지 않는다 (위젯이 CloudKit 을 열지 않음) | `CarveWidget.entitlements` |
| URL 스킴 | `CFBundleURLTypes` → `carve` | `Plugins/ProjectDescriptionHelpers/InfoPlist.swift` |
| 서명 | 추가 설정 불필요. 프로젝트 레벨 `automaticCodeSigning(devTeam: "H4MSW7FUBB")` 상속 | `App/CarveApp/Project.swift` |
| 공유 페이로드 | PNG 1 장 + JSON 1 개 (권·장·절·번역본·지정 시각) | App Group 컨테이너 루트 |

전체 코드는 `git show 50b4296c` 에 있다.

### 5-2. ⚠️ 버전 문자열 — 위젯이 이 문제를 실제 오류로 만든다

버전이 **두 곳에 따로** 박혀 있다.

| 위치 | 값 | 성격 |
|---|---|---|
| `App/CarveApp/Project.swift` — `.marketingVersion("1.3.1")` | `MARKETING_VERSION = 1.3.1` | **빌드 설정** |
| `Plugins/ProjectDescriptionHelpers/InfoPlist.swift` — `"CFBundleShortVersionString": "1.3.1"` | 리터럴 `1.3.1` | **앱 Info.plist 에 박힌 값** |

즉 앱의 실제 `CFBundleShortVersionString` 은 `MARKETING_VERSION` 을 **참조하지 않는다.** 빌드 산출물에서 `"CFBundleShortVersionString" => "1.3.1"` 리터럴로 확인했고, 사용자에게 보이는 앱 버전(`UIDevice.appVersion()`, `Supports/CarveToolkit/Sources/Extension/UIDevice+Extension.swift:82`)도 이 값을 읽는다.

스파이크 위젯은 `"$(MARKETING_VERSION)"` 을 썼고 지금은 **우연히 둘 다 1.3.1** 이라 일치한다(빌드된 `.appex` Info.plist 에서 `1.3.1` 확인). 문제는 RC 다 — `marketingVersion` 만 `2.0.0` 으로 올리면 **위젯은 2.0.0, 앱은 1.3.1** 이 된다.

- 확인한 것: 두 값이 서로 다른 출처를 본다는 것, 지금은 우연히 같다는 것.
- 확인하지 않은 것: App Store Connect 가 확장과 앱의 버전 불일치를 실제로 거부하는지는 **제출해 보지 않았다.** 다만 확장 버전은 컨테이너 앱과 맞춰야 한다는 게 일반적인 요구사항이므로, RC 전에 **한 출처로 합치는 것**을 권한다(`CFBundleShortVersionString` 을 `"$(MARKETING_VERSION)"` 로 바꾸는 쪽). **이건 RC 의 범위이며 WIDGET 브랜치에서 몰래 바꾸지 않는다.**

### 5-3. 남길 것과 버릴 것

| 스파이크 산출물 | 결정 |
|---|---|
| `makeWidgetExtensionTarget` 템플릿 | **재사용.** WIDGET 에서 그대로 되살린다 |
| App Group entitlement 두 개 | **재사용.** 값·범위 그대로 |
| `CFBundleURLTypes` (`carve` 스킴) | **재사용** |
| `VerseWidgetPayload` / `VerseWidgetStore` (공유 1 파일) | **구조는 재사용, 위치는 재검토.** 스파이크는 `App/CarveApp/WidgetSpike/Shared/**` 를 앱·위젯 두 타깃의 `sources` 에 중복으로 넣었다. 본 구현은 모듈 경계(로드맵 §8)에 맞는 자리를 정한다 |
| `WidgetSpikeSeed` (Debug 전용 더미 이미지 생성) | **버린다.** IMAGE-CORE 가 대체한다 |
| 위젯 뷰(진단값 표시) | **버린다.** DESIGN-0 전이라 UI 는 만들지 않았다. 다만 §4-4 의 `.containerBackground(명시 색)` + `.environment(\.colorScheme, .light)` 조합은 근거로 남긴다 |
| `.onOpenURL` 로그 출력 | **버린다.** 실제 이동 배선으로 대체 |

**이 커밋에서 제품 경로의 스파이크를 전부 되돌렸다.** 되돌리지 않으면 앱을 빌드할 때마다 더미 위젯이 임베드되어 사용자 위젯 갤러리에 노출된다 — 기존 앱 동작 변경이다.

---

## 6. 확인하지 못한 것

**통과로 읽지 않는다.**

| # | 항목 | 왜 못 했나 | 우회 |
|---|---|---|---|
| W1 | **실기기 동작** | 실기기 접근 없음. 시뮬레이터에서만 확인했다 | 없음. 기기 확보 시 mini·Air 에서 위젯 추가·표시·탭을 확인한다 |
| W2 | **자동 서명이 App Group 을 실제로 처리하는가** | 확인하려면 기기/아카이브 빌드가 필요하고, 그러면 Xcode 가 **개발자 포털에 App Group ID 를 등록하고 App ID 능력을 바꾸며 위젯용 App ID·프로파일을 새로 만든다.** 사용자 계정 설정 변경이라 수행하지 않았다 | 로컬 프로파일을 확인한 결과 `H4MSW7FUBB.kr.co.carve.leetaek` 프로파일에 **`application-groups` 가 없다**. 즉 WIDGET 에서 **① App Group ID 등록 ② 앱 App ID 에 App Groups 능력 추가 ③ `kr.co.carve.leetaek.Widget` App ID·프로파일 생성**이 필요하다. 사용자가 명시적으로 승인한 뒤 진행한다 |
| W3 | **시뮬레이터 엔타이틀먼트가 실기기와 같은가** | 시뮬레이터 빌드는 앱·위젯 모두 ad-hoc 서명(`TeamIdentifier=not set`)이라 프로파일 검증을 거치지 않는다 | W2 와 함께 확인 |
| W4 | **systemSmall 이외 패밀리의 이미지 면적 상한** | systemSmall 만 홈 화면에 올려 봤다 | WIDGET 에서 실제 쓰는 패밀리로 재측정. 갤러리에는 4 종(small·medium·large·extraLarge)이 노출됐다 |
| W5 | **긴 절·회전·저메모리에서의 위젯 동작** | 더미 이미지 한 장만 썼다 | IMAGE-CORE 완료 후 |
| W6 | **App Store 제출 시 버전 불일치 거부 여부** | 제출하지 않았다 | §5-2 |
| W7 | **위젯 탭 후 진행 중 편집 유실 여부** | 실제 이동 배선이 없어 판정 불가 | WIDGET 에서 확인 (로드맵 §4) |
| W8 | **CloudKit 동기화와 위젯 사본의 상호작용** | 범위 밖 — 위젯은 App Group 파일만 본다 | 원본 삭제 시 위젯 사본 처리는 §8 의 미결정 |

### 도구에서 막힌 것 (기록)

- **SpringBoard 의 접근성 트리를 XcodeBuildMCP `snapshot_ui` 로 읽지 못했다.** 앱 안에서는 정상인데 홈 화면만 빈 트리로 돌아왔고, SpringBoard 재시작·기기 재부팅·`simctl erase` 로도 복구되지 않았다. **좌표 기반 입력**(iOS Simulator 제어 도구의 `tap` — device point)으로 우회해 위젯 추가를 끝냈다. AGENTS.md 의 "터치 주입은 불가하다"는 항목은 이 머신에서 **더 이상 사실이 아니다**(`xcode-select` 가 Xcode 26.3 을 가리킴). 다만 요소 기반 자동화는 홈 화면에서 신뢰할 수 없다.
- 위젯을 홈 화면에 올리는 CLI 는 없다. `simctl` 에 해당 명령이 없어 UI 조작이 필요하다.
- **entitlement 파일을 바꾼 뒤에는 클린 빌드가 필요하다.** 스파이크를 되돌린 직후 같은 DerivedData 로 테스트를 돌리니 `Entitlements file "Carve.entitlements" was modified during the build, which is not supported` 로 빌드가 실패했다. `xcodebuild clean` 후 통과했다. WIDGET 이 App Group 을 추가할 때 같은 곳에서 막힐 수 있다 — 코드 문제로 오진하지 않는다.

---

## 7. 검증

| 명령 | 결과 |
|---|---|
| `mise x -- tuist generate --no-open` | ✅ `Project generated.` |
| `xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)'` — **스파이크 적용 상태** | ✅ **TEST SUCCEEDED · 343** (Swift Testing 341 + XCTest 2) |
| 같은 명령 — 스파이크 되돌린 최종 상태 (`xcodebuild clean` 후) | ✅ **TEST SUCCEEDED · 343** |
| `xcodebuild build -workspace Carve.xcworkspace -scheme CarveApp -destination …` | ✅ BUILD SUCCEEDED |
| 위젯 타깃·스파이크 소스가 만든 새 경고 | ✅ 0 건 |

기준선 대조: 같은 명령을 브랜치 시작점(`3780ac5a`)에서 먼저 돌려 **343** 을 실측하고, 스파이크 적용 후·되돌린 후를 같은 수치와 대조했다.

**빌드 경고에 대한 정확한 진술 — "현재 0 건" 은 사실이 아니다.** 최종 상태의 **클린** 테스트 빌드에서 컴파일러 경고가 **173 건**(중복 포함) 나온다. 전부 선재 경고이며 대부분 deprecation 이다 — `@Reducer(state:action:)` 36 · `hashable` 28 · `undoManager`(N-Canvas 전용) 27 · `reduce(into:action:)` 27 · `@ViewAction` 에서의 `store.send` 24 등. 로드맵 §4 TECH-0 이 적어 둔 TCA 1.26.2 deprecation 경고와 같은 계열이다.

"0 건" 으로 보였던 것은 **증분 빌드가 미재컴파일 모듈의 경고를 생략**하기 때문이다. 브랜치 시작점에서 증분으로 잰 앱 빌드는 경고 1 건(`appintentsmetadataprocessor` 의 도구 알림)만 보였다.

이 브랜치가 늘린 경고는 **0 건**이다. 근거는 둘이다. ① 스파이크 빌드 로그에서 위젯 타깃·`WidgetSpike/**` 소스에 귀속되는 경고가 0 건. ② 최종 커밋의 코드 diff 가 **비어 있다**(`git diff 3780ac5a -- . ':!docs'` 무출력) — 문서만 바뀌었다.

---

## 8. WIDGET 본 구현에 넘기는 결정 사항

| # | 결정할 것 | 이 문서가 제공하는 근거 |
|---|---|---|
| D-W1 | **다크 모드 대응 방식** — 흰 카드로 고정할 것인가, 다크에서도 성립하는 이미지를 만들 것인가 | §4. Info.plist 로는 못 막고, 배경은 명시 색이어야 한다. DESIGN-0 과 함께 정한다 |
| D-W2 | **위젯용 이미지 크기 규격** | §2. 면적 상한이 있고 초과하면 조용히 플레이스홀더가 된다. IMAGE-CORE 가 사진용 원본과 위젯용 축소 사본을 나눠 만들지 결정한다 |
| D-W3 | **"지정한 절" 포인터의 키** | §3. 지금은 `BibleTitle.rawValue` = 본문 파일명이다. BIBLE-EN 이 경로를 바꾸면 과거 위젯 링크가 깨진다. 안정 키로 갈지 정한다 |
| D-W4 | **공유 페이로드 코드의 자리** | §5-3. 두 타깃이 함께 컴파일하는 파일을 어느 모듈에 둘지 (로드맵 §8 의 모듈 경계) |
| D-W5 | **App Group 등록 승인** | §6 W2. 개발자 포털 변경이 필요하다. 사용자 승인 후 진행 |
| D-W6 | **버전 문자열 단일화 시점** | §5-2. RC 의 범위. WIDGET 브랜치에서 바꾸지 않는다 |
| D-W7 | **원본 필사 삭제 시 위젯 사본 처리** | 로드맵 §4 의 "구현 전 세부 결정" 그대로 미결. 위젯이 App Group 파일만 보므로 앱이 명시적으로 지워야 사라진다 |
| D-W8 | **위젯 미지정·이미지 생성 실패의 표시** | §2. 스파이크는 "지정된 절 없음" 과 "App Group 접근 실패" 를 구분했다. 실제 문구는 HELP·DESIGN 과 맞춘다 |

---

## 9. 로드맵에 반영할 것

- §3-1 WIDGET-0: **완료** — 타깃·공유 저장·딥링크 가능 확인. 실기기·배포 서명은 이월(§6 W1·W2).
- §4 "절 롱탭 메뉴·이미지 저장·필사 위젯": **다크 모드 항목을 WIDGET 완료 기준에 추가**한다. 현재 완료 기준에 빠져 있다.
- §4 같은 절: 위젯용 이미지에 **면적 상한**이 있다는 것을 IMAGE-CORE 의 완료 기준에 넣는다.
- §7 출시 체크리스트: 위젯 항목에 "라이트·다크 양쪽 확인" 을 명시한다.
