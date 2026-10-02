# Carve 프로젝트 지침

## 환경
- 이 저장소는 Tuist를 사용한다.
- 자동화 및 무인 검증에는 CLI 기반 워크플로를 우선 사용한다.
- 자동화 및 무인 검증에서는 테스트 실행에 Xcode MCP를 의존하지 않는다.
- 명시적으로 요청되지 않은 한 의존성 버전이나 빌드 설정은 수정하지 않는다.
- 이 앱은 iPad 전용이다. 빌드나 테스트 검증 시 iPhone destination을 사용하지 않는다.

## 아키텍처
- 기존의 TCA + MicroArchitecture 구조를 따른다.
- 아키텍처 규칙 원문은 `.codex/skills/carve-rulebook/`(`SKILL.md` 와 `references/`)이고, 모듈 안 경계(리듀서의 PencilKit · UIKit 타입 · 직접 시각 읽기, Feature 의 SwiftData, Domain 의 UI import)와
  동시성 탈출구(`nonisolated(unsafe)` · `@unchecked Sendable`)는 `.swiftlint.yml` `custom_rules` 가 error 로 검사한다.
- 현재 모듈 경계를 유지하는 작고 국소적인 변경을 우선한다.
- 작업과 무관한 광범위한 리팩토링은 피한다.

### 모듈 지도

의존은 표의 위에서 아래로만 흐른다. Feature 끼리는 import 하지 않고, 화면 사이 이동은 App 의 `AppCoordinatorFeature` 가 한다.
외부 클라이언트는 ClientInterfaces 에 프로토콜과 미구현 기본값만 두고, 실제 구현은 App 이 `App/CarveApp/Sources/App/App.swift` 의 `withDependencies` 로 넣는다.

| 모듈 | 경로 | 맡는 것 | 의존 (내부 모듈) |
|---|---|---|---|
| App | `App/CarveApp` | 조립 · 화면 이동 · 실제 클라이언트 구현(`Sources/Infrastructure`) · 위젯(`Widget`) | 세 Feature, ClientInterfaces |
| CarveFeature | `Feature/CarveFeature` | 성경 탐색 · 필사 화면과 캔버스 · 절 메뉴 · 즐겨찾기 · 팔레트 | ClientInterfaces, Domain, UIComponents, Resources |
| ChartFeature | `Feature/ChartFeature` | 필사 기록 차트 · 주간 요약 | 위와 같음 |
| SettingsFeature | `Feature/SettingsFeature` | 설정 화면 · 광고 제거 · 필기 가져오기 · iCloud | 위와 같음 |
| Domain | `Domain/Domain` | 모델 · 본문 · SwiftData 스키마와 저장소 · 동기화 · 기기 안 초안 | CarveToolkit, ClientInterfaces, Resources |
| UIComponents | `Supports/UIComponents` | 공용 뷰 · 디자인 시스템 · 광고 슬롯 | ClientInterfaces, CarveToolkit, Resources |
| ClientInterfaces | `Supports/ClientInterfaces` | 외부 클라이언트 프로토콜 · 공유 키 | (TCA 만) |
| CarveToolkit | `Supports/CarveToolkit` | Logger · 리듀서 액션 · UIKit 브리지 | Resources |
| Resources | `Shared/Resources` | 에셋 · 폰트 | — |

- 모듈마다 `Framework` 타깃 하나와 `<모듈>Test` 하나다. ClientInterfaces · Resources 는 테스트 타깃이 없다. Interface · Testing · Example 타깃은 없다.
- App 에는 호스트 앱 없는 단위 테스트 `CarveAppTest` 와 UI 테스트 `CarveAppUITests` 가 있다. `CarveAppTest` 는 앱 타깃에 의존하지 않고
  `AppCoordinatorFeature` · `LaunchProgressFeature` · `VerseWidgetPayload` 소스를 함께 컴파일한다 — 앱 타깃에 새로 만든 파일은 이 시험에 들어가지 않으므로, 코디네이터가 쓰는 타입은 그 파일 안이나 Feature · Supports 모듈에 둔다.
- 새 타깃은 `Plugins/ProjectDescriptionHelpers` 의 `makeModule` · `makeFrameworkTarget` · `makeTestTarget` 으로 만든다.
- Tuist 매니페스트(`Project.swift` · `Workspace.swift` · `Tuist.swift` · `Tuist/`)는 여러 작업이 함께 건드리는 공유 파일이다.

### 본보기 파일

새 코드는 먼저 아래 것을 따라 한다.

- 현재 시각 · 기다림: `CarveDetailFeature.swift` 의 `@Dependency(\.date)` · `@Dependency(\.continuousClock)` → `date.now` · `clock.sleep(for:)`. 테스트는 `$0.date = .constant(…)` · `TestClock()`
- SwiftData 를 Feature 밖에 두는 저장소: Domain `FavoriteVerseRepository`(프로토콜) + `SwiftDataFavoriteVerseRepository`(구현) + `FavoriteVerseRepositoryTesting`
- 리듀서 테스트: `Feature/ChartFeature/Tests/ChartTestSupport.swift` 의 `ChartTestTime.now` · `fixedTimeDependencies` 로 시각을 고정한 TestStore 시험

### 용어

| 말 | 코드 |
|---|---|
| 성경 탐색 (권 · 장 고르기) | `CarveNavigationFeature` |
| 필사 · 필기 | `BibleDrawing`(SwiftData 모델) · `DrawingDatabase` · 필사 화면 `CarveDetailFeature` |
| 장 · 절 | `BibleChapter` · Verse(`VerseRowFeature` 등) |
| 필사 캔버스 · 단일 Canvas | `ChapterCanvasFeature`(리듀서 하나를 `ChapterCanvas*.swift` 여러 파일로 나눔) · `ChapterCanvasController`(PencilKit) · `SingleCanvasFlag` |
| 절 메뉴 | `ChapterCanvasVerseMenu` · `VerseMenuOverlay` |
| 이전 필사 내용 보기 | `VerseDrawingHistoryFeature` |
| 초안 · 확인이 필요한 필기 | `VerseDraft`(`LocalPreservationWriter.swift`) · 설정 `DraftRecoveryFeature` |
| 즐겨찾기 | `FavoriteVerse` · `FavoriteListFeature` |
| 기록 차트 · 주간 요약 | `DrawingChartFeature` · `DailyRecordChartFeature` · `DrawingWeeklySummaryFeature` |
| 팔레트 · 라이선스 | **철자가 `Palatte` · `Lisence` 다** — `PencilPalatteFeature` · `ColorPalatteFeature` · `LineWidthPalatteFeature` · `LisenceFeature`. `Palette` · `License` 로 찾으면 안 나온다 |
| 첫 실행 안내 · 광고 제거 | `FirstRunGuideView` · `RemoveAdsFeature` |

## 검증
- 검증은 Xcode MCP가 아니라 CLI 기반으로 수행한다.
- 항상 가장 좁은 관련 테스트 범위부터 실행한다.
- 기본 검증 경로는 `xcodebuild test`를 우선 사용한다.
- Tuist 특화 흐름이나 selective testing이 필요할 때는 `tuist test`를 사용한다.
- CLI 검증을 수행할 때는 iPhone simulator가 아니라 iPad simulator destination을 사용한다.

## 툴체인 제약 ★ 먼저 읽을 것

**주 검증과 출시 후보 빌드는 Xcode 27(Swift 6.4) 하나다. 자사 모듈은 Swift 언어 모드 6 이다.** Xcode 26.x 는 지원하지 않는다(2026-10-02 언어 모드 6 전환에서 26.3 회귀 비교 기준을 내렸다).
머신마다 기본 Xcode 와 설치 경로가 다르다. 기본 Xcode 가 27 이 아니면 `xcode-select` 로 바꾸지 말고, Carve 명령(`xcodebuild` · `tuist` · `swift` · `xcrun`)에만
`DEVELOPER_DIR=<Xcode 27 경로>/Contents/Developer` 를 붙인다. 경로는 실행 전에 확인하고 하드코딩하지 않는다 — 없는 경로를 `DEVELOPER_DIR` 로 주면
`missing DEVELOPER_DIR path` 로 모든 명령이 죽는다. 결과에는 실제로 쓴 Xcode · Swift · runtime 을 적는다.

```bash
xcode-select -p
xcodebuild -version                                          # 27.x 가 아니면 아래에서 Xcode 27 을 찾는다
find /Applications -maxdepth 1 -name 'Xcode*.app' -print
DEVELOPER_DIR=<확인한 경로>/Contents/Developer xcodebuild -version   # Xcode 27.x 인지
DEVELOPER_DIR=<확인한 경로>/Contents/Developer swift --version       # Swift 6.4 인지
mise x -- tuist version
xcrun simctl list runtimes
```

| 버전 | 상태 |
|---|---|
| **Xcode 27** (Swift 6.4) | 🎯 주 검증 · 출시 후보 빌드. 전체 회귀 기준선은 [docs/regression-baseline.md](docs/regression-baseline.md). 여러 런타임을 함께 돌린 마지막 회귀는 2026-09-25 코드(언어 모드 6 전)의 iPadOS 17.5 · 18.6 · 26.2 · 26.4 · 26.5 · 27.0 통과다 |
| Xcode 26.x | 지원하지 않는다. 언어 모드 6 의 동시성 진단이 Swift 6.2.x 와 6.4 에서 달라 둘 다 맞추지 않는다 |

- **언어 모드 6:** 자사 타깃(앱 · 위젯 · Feature · Domain · Supports · 단위 · UI 시험)은 `SWIFT_VERSION = 6` 이다 — `Plugins/ProjectDescriptionHelpers` 가 넣는다.
  의존성 타깃은 각자의 언어 모드 그대로다. 실행 중 격리 검사(SE-0423)도 켜져 있어, 시험이 `Incorrect actor executor assumption` 으로 죽으면 덮지 말고 격리를 고친다.
  관례 · 탈출구(`nonisolated(unsafe)` 금지 · `@unchecked Sendable` 동결)와 남은 우회의 이유는 룰북 `references/concurrency.md` 다.
- iOS 27 SDK 에만 있는 심볼은 `#available(iOS 27, *)` 판정만으로 쓴다. 최소 배포가 iOS 17 이라 런타임 판정은 그대로 필요하다.
- 툴체인 경위는 [로드맵 §4 TECH-0](docs/release-2.0.0-roadmap.md), 실행별 수치와 한계는 [호환성 시험 계획](docs/icloud-sync-compatibility-test-plan.md)에 있다.

**tuist 는 `.mise.toml` 로 4.208.0 에 고정돼 있다.** `PATH` 기본값과 다르므로 반드시
`mise x -- tuist ...` 로 실행한다.

## 공통 명령어

```bash
# 실행한 Xcode · Swift · runtime 을 결과에 적는다(툴체인 절).
# 기본 Xcode 가 27 이 아니면 tuist · xcodebuild 앞에 DEVELOPER_DIR=<확인한 Xcode 27 경로>/Contents/Developer 를 붙인다.

mise x -- tuist generate --no-open        # ★ .xcodeproj 는 gitignore — 클론·브랜치 전환 후 반드시 먼저
xcodebuild test -workspace Carve.xcworkspace -scheme Carve-Workspace \
  -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=26.2'
mise x -- swiftlint lint --quiet --config .swiftlint.yml <파일들>
```

- **전체 회귀 기준선은 [docs/regression-baseline.md](docs/regression-baseline.md) 한 곳에 둔다.** **통과 수가 줄면 회귀다** — 수치를 낮추는 것은
  테스트를 의도적으로 지운 커밋에서만 한다. 기준선을 고칠 때는 그 파일만 고친다.
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

## 실기기 · 시뮬레이터

요령(Instruments · 로그 수집 · 장 시드 · 레이아웃 HUD · 표시 진단 인자 · UI 테스트 좌표 · 터치 자동화)은 [docs/device-simulator-verification.md](docs/device-simulator-verification.md) 에 있다.
실기기 검증 절차 전문은 `docs/phase-0a-d-device-test.md`(단일 Canvas 검증 D9 는 §6-9, 기록 양식은 §8-7 — 설계 §13 의 마지막 게이트), 실기기 CLI 조작은 `docs/device-debugging-cli.md` 에 있다.
여기에는 어기면 데이터나 검증이 망가지는 것만 둔다.

- **업데이트 · CloudKit 표본이 든 시뮬레이터는 조작하지 않는다.** `simctl clone` 은 격리가 아니다 — 같은 계정 · Development private DB 를 공유할 수 있다. 독립 peer 는 새 기기로 만든다.
- **실기기 UI 테스트는 절 메뉴 항목을 누르지 않는다** — 「지우기」 는 실제 필사를 비우고, 「즐겨찾기」 · 「이미지 저장」 · 「위젯에 추가」 도 실제로 저장한다. 시작 장은 `-UITestChapter` 로 정한다.
- ⚠️ **`-CanvasReuseStrokesOnApply` 는 D9 H 수정을 끄고 결함을 재현하는 opt-out 이다** — 기본 검증은 이 인자 **없이** 돈다.
- **Instruments 기록 중에는 `pgrep`/`pkill` 로 프로세스를 건드리지 않는다** — 트레이스가 메타데이터 없이 저장돼 `xctrace export` 가 실패한다.
- 광고 제거 구매 · 복원은 `CarveApp-StoreKit` 스킴의 `RemoveAdsStoreKitUITests` 로 본다. 표준 `Carve-Workspace` 실행에서는 건너뛴다.
- **UI 테스트 · 시뮬레이터 확인은 화면을 탭으로 찾아가지 않고 실행 인자로 연다** — `-UITestRoute <경로>`(`navigation` · `chart` · `favorites` · `settings[/<하위>]` · `verse/<절>`)와
  억제 스위치 `-UITestSkipFirstRunGuide` · `-UITestSkipPatchnote` · `-UITestNoAds`(모두 Debug 전용). 전체 목록은 `LaunchArgument`, 쓰는 법은 위 문서의 「화면 바로 열기」 절.

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
