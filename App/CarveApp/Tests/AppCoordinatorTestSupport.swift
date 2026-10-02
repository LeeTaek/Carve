//
//  AppCoordinatorTestSupport.swift
//  CarveAppTest
//
//  코디네이터 화면 전환 시험의 공용 준비물 — 상태 비교, 화면 전송을 모으는 analytics, 저장소에 닿지 않는 스텁, 시작 상태, TestStore.
//

import CarveFeature
import ChartFeature
import ClientInterfaces
import Domain
import Foundation
import SettingsFeature

import ComposableArchitecture

// MARK: - 상태 비교

// TestStore 는 State: Equatable 을 요구한다. 코디네이터 State 는 Equatable 이 아니고, 루트 · 쌓인 화면의 자식 State(필사 화면 · 차트)도 아니다.
// 코디네이터 소스는 이 시험 모듈에 함께 컴파일되므로 이 준수는 retroactive 가 아니다. 제품 쪽에 Equatable 이 생기면 지운다.
// - 루트 · 쌓인 화면은 어느 화면인지(case)만 견준다. 자식 State 의 내용은 그 Feature 의 시험이 본다.
// - `lastSeenAppVersion`(@Shared)은 넣지 않는다. 단언 중에는 스냅숏을 읽으므로 시험이 `store.state` 로 직접 본다.

extension AppCoordinatorFeature.State: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rootScreen == rhs.rootScreen
            && lhs.pathScreens == rhs.pathScreens
            && lhs.patchnote == rhs.patchnote
            && lhs.settings == rhs.settings
            && lhs.showsRelaunchGuidance == rhs.showsRelaunchGuidance
            && lhs.didShowRelaunchGuidance == rhs.didShowRelaunchGuidance
            && lhs.beforeConnectionNotice == rhs.beforeConnectionNotice
            && lhs.didShowBeforeConnectionNotice == rhs.didShowBeforeConnectionNotice
            && lhs.showsCanvasRemovalNotice == rhs.showsCanvasRemovalNotice
            && lhs.pendingWidgetVerse == rhs.pendingWidgetVerse
            && lhs.pendingLaunchRoute == rhs.pendingLaunchRoute
    }
}

/// 코디네이터의 루트 화면.
enum RootScreen: Equatable {
    case launchProgress
    case carve
}

/// 루트 위에 쌓인 화면.
enum PathScreen: Equatable {
    case chart
    case favorites
}

extension AppCoordinatorFeature.State {
    /// 지금 루트 화면.
    var rootScreen: RootScreen? {
        switch root {
        case .launchProgress?: .launchProgress
        case .carve?: .carve
        case nil: nil
        }
    }

    /// 아래에서 위로 쌓인 화면.
    var pathScreens: [PathScreen] {
        path.map { screen -> PathScreen in
            switch screen {
            case .chart: .chart
            case .favorites: .favorites
            }
        }
    }

    /// 루트가 필사 화면이면 그 상태.
    var carve: CarveNavigationFeature.State? {
        guard case .carve(let carve)? = root else { return nil }
        return carve
    }
}

// MARK: - 스텁

/// 코디네이터가 보낸 화면 전송을 모은다.
final class AnalyticsRecorder: AnalyticsClient {
    struct Screen: Equatable, Sendable {
        let name: String
        let parameters: [String: AnalyticsValue]
    }

    let screens = LockIsolated<[Screen]>([])

    /// 보낸 화면 이름(보낸 순서).
    var screenNames: [String] { screens.value.map(\.name) }

    func track(_ name: String, parameters: [String: AnalyticsValue]) {
        // 코디네이터는 이벤트를 보내지 않는다 — 화면 전송만 본다.
    }

    func screen(_ name: String, parameters: [String: AnalyticsValue]) {
        screens.withValue { $0.append(Screen(name: name, parameters: parameters)) }
    }
}

/// 본문을 읽지 못하는 클라이언트.
///
/// 코디네이터가 장 · 절 이동을 보내면 필사 화면이 본문을 읽으러 간다. 여기서 멈춰야 그 뒤의 공유 SwiftData 저장소(`drawingData`)와
/// 테스트값이 없는 `undoManager` 에 닿지 않는다. 필사 화면이 장을 여는 과정은 CarveFeature 시험이 본다.
struct UnreadableBibleTextClient: BibleTextClient {
    struct Unreadable: Error {}

    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        throw Unreadable()
    }
}

/// 쓰이지 않아야 하는 필사 저장소. 연결 전 필기를 세는 효과가 붙잡아 두기만 한다 — 초안 리더가 없으면 읽지 않고 끝난다.
struct UnusedDrawingRepository: DrawingRepository {
    struct Unused: Error {}

    func load(chapter: BibleChapter) async throws -> DrawingChapterLoad {
        throw Unused()
    }

    func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter, generation: DrawingStoreGeneration) async throws {
        throw Unused()
    }

    func archiveAndReset(_ command: VerseDrawingArchiveCommand, chapter: BibleChapter) async throws -> VerseDrawingArchiveOutcome {
        throw Unused()
    }
}

// MARK: - 시작 상태

enum CoordinatorFixture {
    /// 이번 실행의 앱 버전.
    static let appVersion = "2.0.1"

    /// 위젯이 여는 절 — 시편 23편 1절. 위젯 URL 에는 본문이 없어 빈 문장으로 온다.
    static let widgetVerse = BibleVerse(title: BibleChapter(title: .psalms, chapter: 23), verse: 1, sentence: "")

    /// 위젯이 그 절에 붙이는 URL(`VerseWidgetPayload.deepLinkURL`).
    static var widgetURL: URL? {
        VerseWidgetPayload(
            titleRawValue: BibleTitle.psalms.rawValue,
            bookDisplayName: "시편",
            chapter: 23,
            verse: 1,
            translation: Translation.NKRV.rawValue,
            translationDisplayName: Translation.NKRV.displayName,
            sentence: "여호와는 나의 목자시니 내가 부족함이 없으리로다",
            designatedAt: Date(timeIntervalSince1970: 0)
        ).deepLinkURL
    }

    /// 연결을 보류한 실행에서, 지금 계정으로 저장소 소유가 확인된 환경 — 다시 열면 연결된다(`connectsOnRelaunch`).
    static var relaunchable: DrawingEditEnvironment {
        var environment = DrawingEditEnvironment.ownedForTesting
        environment.connectionHeld = true
        return environment
    }

    /// 들어갈 수 있는 시작 화면 — 일반 실행이고 동기화가 끝났다(`route == .enterWriting`).
    static func launchReadyToEnter() -> LaunchProgressFeature.State {
        var launch = LaunchProgressFeature.State()
        launch.mode = .normal
        launch.syncState = .syncCompleted
        return launch
    }

    /// 시작 화면에 있는 코디네이터. `lastSeenAppVersion` 은 이 설치가 마지막으로 본 버전이다 — nil 이면 처음 들어간다.
    /// `launchRoute` 는 앱 진입점이 `-UITestRoute` 에서 읽어 넣어 둔 화면이다.
    /// - Important: `makeCoordinatorStore` 의 초기 상태 자리에서 만든다. 그래야 @Shared 가 그 시험의 UserDefaults 에 붙는다.
    static func launching(
        _ launch: LaunchProgressFeature.State = launchReadyToEnter(),
        lastSeenAppVersion: String? = nil,
        launchRoute: AppCoordinatorFeature.UITestRoute? = nil
    ) -> AppCoordinatorFeature.State {
        var state = AppCoordinatorFeature.State()
        state.root = .launchProgress(launch)
        state.$lastSeenAppVersion.withLock { $0 = lastSeenAppVersion }
        state.pendingLaunchRoute = launchRoute
        return state
    }

    /// 필사 화면에 있는 코디네이터. 그 위에 띄운 설정 · 패치노트와 쌓인 화면을 함께 줄 수 있다.
    static func writing(
        settings: SettingsFeature.State? = nil,
        patchnote: PatchnoteFeature.State? = nil,
        path: [AppCoordinatorFeature.Path.State] = []
    ) -> AppCoordinatorFeature.State {
        var state = AppCoordinatorFeature.State()
        state.root = .carve(.initialState)
        state.settings = settings
        state.patchnote = patchnote
        for screen in path {
            state.path.append(screen)
        }
        return state
    }
}

// MARK: - TestStore

/// 코디네이터 TestStore. 비망라(`exhaustivity = .off`)라 시험은 전환이 바꾸는 필드와 보내는 액션만 확인한다.
///
/// - 자식 화면이 받은 액션의 효과까지 실제로 돈다. 저장소 · 본문에 닿는 의존성은 스텁으로 막는다.
/// - 편집 환경 스텁(`StubDrawingEditEnvironment`)은 변화 알림이 곧바로 끝나므로 보류 · 연결 전 필기 구독이 남지 않는다.
/// - `appStorage` 는 기본값이면 시험마다 새 것이다. 2.0.x 「필사 캔버스」 키(N-Canvas 제거 안내)를 미리 넣거나 뒤에 확인하는 시험이 자기 것을 넘긴다.
@MainActor
func makeCoordinatorStore(
    _ initialState: @autoclosure () -> AppCoordinatorFeature.State,
    appVersion: String = CoordinatorFixture.appVersion,
    hold: LegacySeparationHold? = nil,
    environment: DrawingEditEnvironment = .ownedForTesting,
    analytics: AnalyticsRecorder = AnalyticsRecorder(),
    appStorage: UserDefaults = .inMemory
) -> TestStoreOf<AppCoordinatorFeature> {
    let store = TestStore(initialState: initialState()) {
        AppCoordinatorFeature()
    } withDependencies: {
        // 시험마다 새 UserDefaults — `lastSeenAppVersion` · 현재 장 같은 @Shared(.appStorage) 와 N-Canvas 제거 안내가 읽는 키가 다른 시험과 섞이지 않는다.
        $0.defaultAppStorage = appStorage
        $0.appVersion = appVersion
        $0.analyticsClient = analytics
        $0.legacySeparationHoldState = LegacySeparationHoldState(hold: hold)
        $0.drawingEditEnvironment = StubDrawingEditEnvironment(environment)
        $0.verseDraftRecoveryReader = nil
        $0.drawingRepository = UnusedDrawingRepository()
        $0.bibleTextClient = UnreadableBibleTextClient()
    }
    store.exhaustivity = .off
    return store
}
