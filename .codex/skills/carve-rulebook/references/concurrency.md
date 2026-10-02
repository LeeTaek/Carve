# Concurrency Rules (Carve)

## Goal
- 자사 모듈은 Swift 언어 모드 6(Xcode 27 · Swift 6.4)으로 빌드한다 — 데이터 경합 가능성은 컴파일 오류다. 이 문서는 그 오류를 고치는 **우리 관례**와,
  컴파일러 검사를 끈 **탈출구가 어디에 왜 남았는지**(안전하지 않은 우회 감사)를 적는다.
- 동작은 바꾸지 않는다. 진단을 없애는 변경은 최소로 하고, 격리를 바꿔 실행 순서 · 스레드가 달라지는 곳은 시험이나 실행으로 확인한다.
- 범위 밖: Approachable Concurrency(`SWIFT_APPROACHABLE_CONCURRENCY`) · 기본 MainActor 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION`) — 동작이 바뀌는 별도 실험이다.

---

## Current state
- 툴체인 · 언어 모드의 원본은 AGENTS.md 「툴체인 제약」 이다. 자사 타깃(앱 · 위젯 · Feature · Domain · Supports · 단위 · UI 시험)은 `SWIFT_VERSION = 6`, 의존성 타깃은 각자의 언어 모드다.
- 언어 모드 6 은 **실행 중 격리 검사**(SE-0423)도 켠다 — MainActor 라고 표시한 코드가 다른 스레드에서 불리면 시험 · 앱이 `Incorrect actor executor assumption` 등으로 멈춘다.
- 전환 경위(2026-10-02): 자사 타깃에 Swift 6 동시성 검사를 경고로 켜고 모듈별로 고친 뒤 마지막에 언어 모드 6 으로 올렸다(plan 「Swift 6.4 · 언어 모드 6 전환」).

---

## 관례 — State · 전역 상태
1) TCA State 는 `Sendable` 을 붙이고 `static let initialState` 를 그대로 둔다.
   - Path · Destination 은 `extension X.Path.State: Sendable {}` 로 붙인다(TCA 1.26 방식 — `@Reducer(state:)` 인자형은 deprecated).
   - N-Canvas(@Model) · PencilKit · UIKit 타입을 담아 Sendable 이 될 수 없는 State 만 계산 프로퍼티 `static var initialState: Self { Self() }` 로 둔다
     (`CanvasFeature` · `SentencesWithDrawingFeature` · `CarveDetailFeature` · `DrawingChartFeature` 등).
   - State 에 `AlertState` · `ConfirmationDialogState` 가 있으면 그 Action 도 `Sendable` 이다.
2) 그 밖의 전역 · static 가변 상태는 `static let` 이다(타입이 Sendable 이 아니면 계산 프로퍼티). `static var` 저장 프로퍼티를 새로 두지 않는다.
3) DependencyKey 의 `liveValue` · `testValue` · `previewValue` 는 `static let` 이고 값 타입은 Sendable 이다(swift-dependencies 요구).
   클래스는 내부 가변 상태를 `LockIsolated` 로 감싸거나 타입 단위 `@MainActor` 로 둔다. MainActor 클래스의 기본값은 `nonisolated static let`(`PersistentCloudKitContainer`).
4) 공유 가변 상태는 `LockIsolated`(ConcurrencyExtras)다. 새 코드에 `NSLock` + `var` 를 쓰지 않는다. 남은 `NSLock` 은 async 함수 안에서 `lock()`/`unlock()` 대신 `withLock` 으로 잠근다.
   최소 배포가 iOS 17 이라 `Synchronization.Mutex`(iOS 18)는 쓰지 않는다.

## 관례 — 리듀서 · 격리
5) `@Reducer struct` 에 `Sendable` 을 붙인다(대부분 `@Dependency` 만 가져 그대로 된다). 그러면 effect(`.run`) 안에서 `self` 의 의존성을 그대로 쓴다.
   effect 에 캡처 목록을 쓰는 것은 리듀서가 Sendable 이 될 수 없을 때만이다.
6) Action 은 기본적으로 Sendable 이 필요 없다. effect 에서 `send` 로 넘기는 값의 타입만 Sendable 로 만든다.
7) UI 계층 타입(뷰 지원 클래스 · UIKit 브리지 · `Coordinator` · UI 시험 클래스)은 메서드마다가 아니라 **타입 단위로** `@MainActor` 다.
   의존성 기본값이 비격리 문맥에서 만들므로, 상태를 건드리지 않는 `init` 은 `nonisolated` 로 둔다(`SharedUndoManager` · `PersistentCloudKitContainer`).
8) MainActor 전용 SDK API 는 의존성의 클로저 · 메서드를 `@MainActor` 로 두고, 리듀서 **본문**에서 `MainActor.assumeIsolated` 로 부른다 — 리듀서 본문은 스토어(MainActor)에서 돈다.
   본보기: `SendFeedbackFeature`(`MailComposeAvailabilityClient.canSendMail: @MainActor @Sendable () -> Bool`) · `SettingsFeature`(`AdConsentClient.isPrivacyOptionsRequired`).
   effect(`.run`) 클로저는 MainActor 밖에서 돌 수 있으므로 거기서는 `assumeIsolated` 를 쓰지 않는다.
9) TestStore 를 쓰는 시험 스위트는 `@MainActor` 다.
10) SwiftData @Model 은 actor 밖으로 내보내지 않는다 — 저장소가 actor 안에서 DTO 로 바꿔 넘긴다(swiftdata.md 규칙 3 · 4). 예외는 N-Canvas 경계의 `UncheckedSendable` 하나다.

## 탈출구 — 쓰는 조건
| 탈출구 | 규칙 | 기계 검사 |
|---|---|---|
| `nonisolated(unsafe)` | 쓰지 않는다. static 상태는 관례 2, 공유 가변 상태는 관례 4 | `no_nonisolated_unsafe`(예외 없음) |
| `@unchecked Sendable` | 새로 늘리지 않는다. 남은 것은 아래 감사 표가 목록이고, 고치면 표와 lint `excluded` 에서 함께 뺀다 | `no_unchecked_sendable`(지금 쓰는 파일은 `excluded` 로 동결) |
| `@preconcurrency import` | SDK · 3자 모듈의 Sendable 미표기에만 쓴다. 자사 모듈에는 쓰지 않는다 | 없음(리뷰) |
| `UncheckedSendable`(ConcurrencyExtras) | N-Canvas 경계에만 쓴다(swiftdata.md). 감싼 곳마다 주석 `이행 중 예외(N-Canvas): N-Canvas 제거 때 지운다 — 룰북 swiftdata.md` | 없음(리뷰) |
| `MainActor.assumeIsolated` | 관례 8 의 리듀서 본문, 또는 메인 스레드임을 방금 확인한 곳(`Thread.isMainThread`)에만 쓴다. 가정이 틀리면 실행 중에 멈춘다 | 없음(리뷰) |

- 두 lint 규칙은 리듀서 파일만이 아니라 저장소 전체(제품 · 시험 · 위젯 · UI 시험)를 본다. 주석 · 문자열 속 이름은 판정하지 않는다.

## 실행 중 격리 검사가 잡았을 때
- 시험이 `Incorrect actor executor assumption` · `dispatch_assert_queue` 등으로 죽으면 `assumeIsolated` · `@preconcurrency` 로 덮지 않는다. 경로 · 스택을 기록하고 격리를 고친다.
- 호스트 없는 단위 시험은 SDK 콜백(PhotoKit · StoreKit · UMP · MetricKit · `CKAccountChanged` · MessageUI · AdMob)을 타지 않는다.
  그 경로의 격리를 바꿨으면 시뮬레이터 · 실기기에서 직접 연다(AGENTS.md 「실기기 · 시뮬레이터」 — 화면은 실행 인자로 연다).

---

## 안전하지 않은 우회 감사 (2026-10-02, 언어 모드 6 전환 끝)
코드는 고치지 않고 남은 것을 적었다. 줄 번호 대신 타입 · 함수 이름으로 적는다. 고치면 이 표에서 빼고, `@unchecked Sendable` 이면 `.swiftlint.yml` `no_unchecked_sendable` 의 `excluded` 에서도 뺀다.

### `@unchecked Sendable` — 제품 5
전환 전 6 에서 하나(App `GoogleNativeAdClient` — 타입 단위 `@MainActor` + 격리 채택으로 바꿨다) 줄었다.

| 타입 — 파일 | 왜 남았나 | 지울 조건 |
|---|---|---|
| `LiveDrawingEditEnvironment` — Domain `Drawing/DrawingEditEnvironment.swift` | 구독자 · 알림 토큰 둘 · 미반영 알림 수를 `NSLock` 으로 지킨다. 계정 변경 알림 콜백 안에서 **동기로** 막아야 해 actor 로 바꿀 수 없다 | 가변 상태 넷을 `LockIsolated` 하나(구조체)로 묶으면 그 밖의 저장 프로퍼티(actor 둘 · `NotificationCenter` · Sendable 프로토콜 · 이 표의 `FileEraseStateStore` · `LegacySeparationHoldState`)는 이미 Sendable 이다 — **LockIsolated 후보** |
| `LiveLocalDrawingChangeClient` — Domain `Drawing/LocalDrawingChangeClient.swift` | 구독자 사전을 `NSLock` 으로 지킨다 | `LockIsolated<[UUID: AsyncStream<LocalDrawingChange>.Continuation]>` — **LockIsolated 후보** |
| `LegacySeparationHoldState` — Domain `SwiftData/LegacySeparationGate.swift` | 보류 값 하나를 `NSLock` 으로 지킨다. DependencyKey 값이라 Sendable 이어야 한다 | `LockIsolated<LegacySeparationHold?>` — **LockIsolated 후보** |
| `FileEraseStateStore` — Domain `Drawing/EraseStateStore.swift` | 저장 프로퍼티는 `let` 둘이고 동시 쓰기는 파일 잠금(`flock`)이 막는다. `FileManager` 가 SDK 에서 Sendable 이 아니다(Xcode 27 SDK 확인) | `fileManager` 를 저장하지 않고 쓸 때 `FileManager.default` 를 쓰면(주입하는 곳이 없다) 또는 SDK 가 Sendable 로 표기하면 |
| `SentenceSettingCloudBackup` — Domain `SentenceSettingBackup/SentenceSettingCloudBackup.swift` | `UserDefaults` · `NSUbiquitousKeyValueStore`(`SentenceSettingCloudStore`)가 SDK 에서 Sendable 이 아니다. 알림 토큰은 `NSLock` 으로 지킨다 | SDK 가 두 타입을 Sendable 로 표기하면(토큰은 그때 `LockIsolated` 로). 그 전에는 남긴다 |

### `@unchecked Sendable` — 시험 대역 25(18파일)
대역 클래스가 `Sendable` 을 상속한 프로토콜을 따르려고 붙여 왔다. 전환에서 진단이 나지 않아 손대지 않았다.

| 지울 조건 | 타입 — 파일 |
|---|---|
| **`@unchecked Sendable` 만 빼면 된다** — 저장 프로퍼티가 모두 `let` 이고 Sendable 값이거나 `LockIsolated` 다(19) | Domain `CloudInitialWaitTesting`(`HeldAccountStatus`) · CarveFeature `CarveDetailFavoriteTesting`(`FavoriteRepositorySpy`) · `CarveDetailVerseImageTesting`(`PhotoLibrarySpy` · `RendererSpy`) · `ChapterCanvasArrivalTesting`(`ControlledArrivals`) · `ChapterCanvasEditSessionTesting`(`ControlledEditEnvironment` · `RecordingDraftStore`) · `ChapterCanvasImportTesting`(`ControlledLocalChanges`) · `ChapterCanvasStaleSaveTesting`(`OrderedApplySpy`) · `WidgetVerseClientSpy` · SettingsFeature `CloudSettingsEraseTesting`(`EraserStub` · `WidgetClearSpy`) · `CloudSettingsHoldTesting`(`ForbiddenEraser`) · `DraftRecoveryFeatureTesting`(`RepositoryStub` · `CleanerSpy` · `ControlledEnvironment`) · `DraftRecoveryImportTesting`(`RecordingChanges`) · `WidgetSettingsTesting`(`FavoritesStub` · `WidgetSpy`) |
| **LockIsolated 후보** — `NSLock` + `var`(5) | Domain `CloudInitialWaitTesting`(`CancellingAccountStatus` — `target`) · `CloudObservationOrderTesting`(`CountingAccountStatus` — `count`) · `LaunchRouteTesting`(`CountingAccountStatusClient` — `count`) · `LegacySeparationPerformanceProbeTesting`(`FootprintSampler` — `running` · `baseline` · `peak` · `thread`) · CarveFeature `TextLayoutKeyProbeTesting`(`LayoutBox` — `stored`) |
| **LockIsolated 후보** — `var` 하나(1) | CarveFeature `ChapterCanvasFeatureTesting`(`RepositorySpy` — `var snapshots` 클로저. 나머지는 이미 `LockIsolated`) |

### `UncheckedSendable`
| 어디 | 왜 | 지울 조건 |
|---|---|---|
| Domain `SwiftData/SwiftDatabaseActor+DrawingDatabase.swift`(`legacyCanvasDrawings(chapter:)`) · `SwiftData/DrawingDatabase.swift`(`fetchForLegacyCanvas(chapter:)`) → CarveFeature `CarveDetailFeature`(`.wrappedValue`) | **N-Canvas 경계.** N-Canvas 는 절마다 @Model 을 들고 편집한다(설계 §10-3 롤백 경로). 지울 경로를 DTO 로 고치지 않기로 했다(plan 결정 4). 쓰는 곳은 swiftdata.md 이행 중 예외 표 | N-Canvas 제거(별도 plan) |
| CarveFeature `Extension/CodableAppStorageKey.swift`(`storage: UncheckedSendable<UserDefaults>`) · 시험 `CodableAppStorageKeyTesting` | `SharedKey` 는 Sendable 이어야 하는데 `UserDefaults` 가 SDK 에서 Sendable 이 아니다. Sharing 의 `AppStorageKey` 와 같은 모양이고 전환 전부터 있었다. **N-Canvas 밖의 유일한 것** — 늘리지 않는다 | SDK 가 `UserDefaults` 를 Sendable 로 표기하면 |

### `MainActor.assumeIsolated` — 14곳
| 어디 | 무엇 | 안전하다고 보는 근거 | 지울 조건 |
|---|---|---|---|
| Domain `SwiftData/SwiftDataContextProvider+Dependency.swift`(`recordStoreOutcome`) | `Thread.isMainThread` 면 `PersistentCloudKitContainer.syncState` 를 곧바로 쓴다(아니면 `Task { @MainActor }`) | 동기 기본 경로(`ModelContainer.liveValue`)를 처음 읽는 스레드가 정해져 있지 않다. 메인 스레드임을 방금 확인했다. 앱 시작 경로(`ReleaseStoreBootstrapper`)는 여기를 지나지 않는다 | 동기 기본값이 저장소를 열지 않게 바꾸면 |
| CarveFeature N-Canvas 리듀서 5 — `CarveDetailFeature`(`setSentence` 의 `undoManager.clear()`) · `CanvasFeature`(`registUndoCanvas`) · `PencilPalatteFeature`(`view(.undo)` · `view(.redo)` · `setCanUndo`) | `SharedUndoManager` 호출 | 관례 8 — 리듀서 본문 | N-Canvas 제거 |
| SettingsFeature `SendFeedbackFeature` 2(`view(.onAppear)` · `sendFeedback`) · `SettingsFeature` 1(`view(.onAppear)`) | MessageUI · UMP 의 MainActor 의존성 | 관례 8 의 본보기 | 관례로 남긴다 |
| UIComponents `Ads/AdSlotFeature.swift` 2(`adLoaded` 의 `nativeAdClient.view(for:)` · `invalidate(_:)`) | AdMob 뷰 · 캐시(App `GoogleNativeAdClient` 는 타입 단위 `@MainActor`) | 리듀서 본문과 본문이 부르는 동기 함수 | 관례로 남긴다 |
| CarveFeature Debug 스파이크 `Debug/CanvasScrollSpikeHosting.swift` 3(`SpikeGestureBinder` 의 제스처 selector 2 · `SpikeOverlayCanvas` 의 `onAttach` 클로저) | `CanvasScrollSpikeMetrics`(MainActor) 기록 | UIKit 제스처 · `didMoveToWindow` 는 메인 스레드에서 불린다. 전환 전부터 있었다 | `SpikeGestureBinder` 를 타입 단위 `@MainActor`, `onAttach` 를 `@MainActor` 클로저로(관례 7) · 스파이크를 지우면 |

### `@preconcurrency`
| 어디 | 무엇 | 왜 | 지울 조건 |
|---|---|---|---|
| Domain `Model/PencilPalatte.swift` | `@preconcurrency import PencilKit` | Sendable 구조체 `PencilPalatte` 가 `PKInkingTool.InkType` 을 담는데 SDK 에 Sendable 표기가 없다. 전환 전부터 있었다 | 펜 종류를 Domain 값 타입으로 바꾸면(pencilkit.md 이행 중 예외와 같은 일) · SDK 표기 |
| CarveFeature `Extension/CodableAppStorageKey.swift` | `@preconcurrency import Foundation` | 알림 구독 토큰(`NSObjectProtocol`)에 Sendable 표기가 없는데 해지 클로저(`SharedSubscription`, `@Sendable`)가 쥔다. Sharing 의 `AppStorageKey` 와 같은 처리 | 토큰을 `LockIsolated` 로 감싸 넘기면 될 것으로 본다(파일 전체의 Foundation 검사를 끄는 범위가 넓다 — 후속) · SDK 표기 |
| SettingsFeature `Details/SendFeedback/MailComposeView.swift` | `Coordinator`(타입 단위 `@MainActor`)의 `@preconcurrency MFMailComposeViewControllerDelegate` 채택 | MessageUI delegate 프로토콜에 격리 표기가 없고 메인 스레드에서 불린다. 어긋나면 실행 중 격리 검사가 멈춘다 | 아래 「SDK delegate 관례」 를 정하면 |

### 격리 결정 · 격리 채택 — 우회는 아니지만 함께 본다
| 어디 | 무엇 | 근거 |
|---|---|---|
| Domain `SwiftData/SwiftDataContextProvider.swift` `PersistentCloudKitContainer` | 타입 단위 `@MainActor`(plan 결정 15). `init` 과 상태를 쓰지 않는 static 함수는 `nonisolated`, DependencyKey 값은 `nonisolated static let`. `syncState` · `activity` 와 그 publisher 는 MainActor 에서만 | `@Published` 라 `LockIsolated` 로 풀리지 않고, `@unchecked Sendable` 은 탈출구 규칙 위반이다. 기존 코드도 MainActor 에서만 바꿨다. 동기 기본 경로의 `assumeIsolated` 는 위 표 |
| CarveFeature N-Canvas `Presentation/Drawing/Canvas/SharedUndoManager.swift` | 타입 단위 `@MainActor`, `init` 만 `nonisolated`(`UndoManager` 는 처음 쓸 때 만든다) | `UndoManager` · `PKCanvasView` 가 MainActor 타입이다. 리듀서 호출 5곳은 위 표. N-Canvas 제거 때 함께 지운다 |
| App `Infrastructure/Ads/GoogleNativeAdClient.swift` | 격리 채택 `extension GoogleNativeAdClient: @MainActor NativeAdLoaderDelegate`(클래스는 타입 단위 `@MainActor`) | AdMob 은 로더 delegate 를 메인 스레드에서 부른다(`dispatchPrecondition` 으로 확인). 이 전환에서 `@unchecked Sendable` 하나를 이것으로 바꿨다 |
| CarveFeature `Presentation/Drawing/SentenceWithDrawing/SentencesWithDrawingView.swift` | 격리 채택 `View, @MainActor Equatable` | `==` 가 MainActor 의 store 를 비교한다. 컴파일러가 확인하는 격리라 지울 것은 없다 |

### SDK delegate 관례 — 아직 정하지 않았다
격리 표기가 없는 SDK delegate 를 MainActor 타입이 따를 때 두 방식이 섞여 있다 — `@preconcurrency` 채택(`MailComposeView.Coordinator`)과 격리 채택 `@MainActor`(`GoogleNativeAdClient`).
둘 다 SDK 가 메인 스레드에서 부른다고 가정하고, 어긋나면 실행 중 격리 검사가 잡는다. 차이는 컴파일 시점이다 — 격리 채택은 그 채택을 MainActor 밖에서 쓰면 컴파일 오류다(SE-0470).
어느 쪽을 관례로 할지 정하면 관례 7 에 적고 다른 쪽을 맞춘다(후속 과제).

---

## 후속 과제 (코드는 아직 고치지 않았다)
1. 시험 대역 19개의 `@unchecked Sendable` 을 뺀다 — 컴파일로 확인하고 `no_unchecked_sendable` `excluded` 에서 그 파일을 뺀다(한 파일의 대역을 모두 고쳐야 뺄 수 있다).
2. **LockIsolated 전환** — 제품 3(`LegacySeparationHoldState` · `LiveLocalDrawingChangeClient` · `LiveDrawingEditEnvironment`), 시험 6(`CancellingAccountStatus` · `CountingAccountStatus` · `CountingAccountStatusClient` · `FootprintSampler` · `LayoutBox` · `RepositorySpy.snapshots`).
   제품은 알림 콜백의 동기 잠금 순서(`LiveDrawingEditEnvironment.accountChangeNotified`)가 그대로인지 시험으로 확인한다.
3. `FileEraseStateStore` — 저장한 `FileManager` 대신 `FileManager.default` 로 바꾸고 `@unchecked` 를 뺀다.
4. SDK delegate 관례를 정한다(위 절).
5. `CodableAppStorageKey` — 알림 토큰을 `LockIsolated` 로 감싸 `@preconcurrency import Foundation` 을 되돌릴 수 있는지 본다.
6. Debug 스파이크 `SpikeGestureBinder` 를 타입 단위 `@MainActor` 로(관례 7).
7. SDK 표기를 기다리는 것 — `SentenceSettingCloudBackup` · `CodableAppStorageKey` 의 `UncheckedSendable<UserDefaults>` · `PencilPalatte` 의 `@preconcurrency import PencilKit`. Xcode 가 바뀔 때 다시 본다.
8. N-Canvas 제거 때 함께 — `UncheckedSendable<[BibleDrawing]>` 둘, 리듀서 `assumeIsolated` 5, `SharedUndoManager`.

---

## Definition of done (동시성)
- [ ] 자사 타깃의 Xcode 27 빌드에 동시성 오류 · 경고가 없다(남는 것은 의존성 쪽만)
- [ ] `no_nonisolated_unsafe` · `no_unchecked_sendable` error 0 — 새 `@unchecked Sendable` 이 없다
- [ ] 새 `@preconcurrency import` 는 SDK · 3자 모듈에만, `UncheckedSendable` 은 N-Canvas 경계 밖에 늘지 않았다
- [ ] 우회를 지웠으면 이 감사 표와 lint `excluded` 에서 함께 뺐다
- [ ] 격리를 바꾼 SDK 콜백 경로를 실행으로 확인했다
