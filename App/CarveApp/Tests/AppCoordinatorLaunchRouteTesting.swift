//
//  AppCoordinatorLaunchRouteTesting.swift
//  CarveAppTest
//
//  화면 바로 열기(`-UITestRoute`)와 억제 스위치(`-UITestSkipFirstRunGuide` · `-UITestSkipPatchnote`) — Debug 실행 인자.
//  앱 진입점이 읽어 둔 경로는 시작 화면이 끝나 필사 화면에 들어간 직후(위젯 보류 절과 같은 때) 열리고, 모르는 경로는 무시된다.
//  억제는 Store 를 만들기 전에 저장해 두는 값이라, 시험은 초기 상태 자리(그 시험의 UserDefaults)에서 부른다.
//  「필사 백업」(settings/backup) 화면의 백업 전 flush 중계도 여기서 본다 — 설정의 「백업 만들기」 ↔ 코디네이터 ↔ 필사 화면(설계 backup-import-design §5-2).
//

import CarveFeature
import CarveToolkit
import Domain
import Foundation
import SettingsFeature
import SwiftUI
import Testing

import ComposableArchitecture

@Suite("코디네이터 — 화면 바로 열기 · 억제 스위치")
@MainActor
struct AppCoordinatorLaunchRouteTesting {
    private typealias Route = AppCoordinatorFeature.UITestRoute

    /// 시작 화면이 진입을 알린다.
    private static var syncCompleted: AppCoordinatorFeature.Action {
        .root(.presented(.launchProgress(.syncCompleted)))
    }

    /// 성경 탐색의 열을 모두 연다(`CarveNavigationFeature.openNavigation` — 헤더 제목은 번역본 메뉴다, 결정 19).
    private static func isOpenNavigation(_ action: AppCoordinatorFeature.Action) -> Bool {
        guard case .root(.presented(.carve(.openNavigation))) = action else {
            return false
        }
        return true
    }

    // MARK: 경로 읽기

    @Test("경로 문자열을 읽는다 — 이름은 대소문자를 가리지 않는다")
    func parsesRouteValues() {
        #expect(Route("navigation") == .navigation)
        #expect(Route("chart") == .chart)
        #expect(Route("favorites") == .favorites)
        #expect(Route("notebooks") == .notebooks)
        #expect(Route("Notebooks") == .notebooks)
        #expect(Route("settings") == .settings(nil))
        #expect(Route("verse/16") == .verse(16))
        #expect(Route("Settings/RemoveAds") == .settings(.removeAds))
        #expect(Route("settings/backup") == .settings(.backup))
    }

    @Test("설정 하위 경로는 설정 사이드바의 행마다 하나씩 있다")
    func parsesEverySettingsSubroute() {
        let names: [String: SettingsFeature.SidebarItem] = [
            "icloud": .iCloud, "draftRecovery": .draftRecovery, "backup": .backup, "widget": .widget, "appearance": .appearance,
            "language": .language,
            "help": .help, "patchnote": .patchnote, "sendFeedback": .sendFeedback, "appVersion": .appVersion, "removeAds": .removeAds
        ]
        #expect(Set(names.values) == Set(SettingsFeature.SidebarItem.allCases))
        for (name, item) in names {
            #expect(Route("settings/\(name)") == .settings(item), "settings/\(name)")
        }
    }

    @Test("모르는 경로 · 빈 하위 이름 · 1 보다 작은 절 번호는 읽지 않는다")
    func rejectsUnknownRoutes() {
        let invalid = [
            "", "bogus", "/chart", "chart/1", "notebook", "notebooks/1", "settings/", "settings/unknown", "settings/removeAds/extra",
            "verse", "verse/0", "verse/-1", "verse/abc"
        ]
        for value in invalid {
            #expect(Route(value) == nil, "「\(value)」")
        }
    }

    @Test("실행 인자에서 경로를 읽는다 — 인자가 없거나, 값이 없거나, 모르는 경로면 nil")
    func parsesLaunchArguments() {
        let app = "/Applications/Carve.app/Carve"
        #expect(Route.parse(arguments: [app]) == nil)
        #expect(Route.parse(arguments: [app, LaunchArgument.uiTestRoute, "settings/removeAds"]) == .settings(.removeAds))
        #expect(Route.parse(arguments: [app, LaunchArgument.uiTestSkipFirstRunGuide, LaunchArgument.uiTestRoute, "chart", LaunchArgument.uiTestNoAds]) == .chart)
        #expect(Route.parse(arguments: [app, LaunchArgument.uiTestRoute]) == nil)
        // 값을 빠뜨리면 바로 뒤의 다른 인자를 경로로 읽지 않는다.
        #expect(Route.parse(arguments: [app, LaunchArgument.uiTestRoute, LaunchArgument.uiTestNoAds]) == nil)
        #expect(Route.parse(arguments: [app, LaunchArgument.uiTestRoute, "settings/unknown"]) == nil)
    }

    // MARK: 시작 화면이 끝난 뒤에 연다

    @Test("시작 화면에서는 열지 않는다 — 들어갈 수 없는 시작 화면(재실행 요구)이면 경로는 그대로 기다린다")
    func routeWaitsForLaunchToFinish() async {
        var launch = LaunchProgressFeature.State()
        launch.mode = .normal
        launch.syncState = .migrationCompleted
        let store = makeCoordinatorStore(CoordinatorFixture.launching(launch, launchRoute: .settings(.removeAds)))
        #expect(store.state.settings == nil)

        await store.send(Self.syncCompleted)

        #expect(store.state.rootScreen == .launchProgress)
        #expect(store.state.settings == nil)
        #expect(store.state.pendingLaunchRoute == .settings(.removeAds))
    }

    @Test("settings/<하위> — 필사 화면에 들어가며 설정을 그 화면으로 연다")
    func settingsSubrouteOpensSettingsAtPath() async {
        let store = makeCoordinatorStore(CoordinatorFixture.launching(launchRoute: .settings(.removeAds)))

        await store.send(Self.syncCompleted) {
            $0.pendingLaunchRoute = nil
            $0.settings = SettingsFeature.State.initialState(path: .removeAds(.initialState))
        }
        #expect(store.state.rootScreen == .carve)
        await store.finish()
    }

    @Test("settings/backup — 필사 화면에 들어가며 설정을 「필사 백업」 으로 연다")
    func settingsBackupRouteOpensBackup() async {
        let store = makeCoordinatorStore(CoordinatorFixture.launching(launchRoute: .settings(.backup)))

        await store.send(Self.syncCompleted) {
            $0.pendingLaunchRoute = nil
            $0.settings = SettingsFeature.State.initialState(path: .backup(.initialState))
        }
        #expect(store.state.settings?.selectedSidebarItem == .backup)
        await store.finish()
    }

    @Test("settings — 설정의 첫 화면(iCloud)을 연다")
    func settingsRouteOpensFirstScreen() async {
        let store = makeCoordinatorStore(CoordinatorFixture.launching(launchRoute: .settings(nil)))

        await store.send(Self.syncCompleted) {
            $0.pendingLaunchRoute = nil
            $0.settings = .initialState
        }
        #expect(store.state.settings?.path == .iCloud(.initialState))
        await store.finish()
    }

    @Test("chart · favorites — 필사 화면에 들어가며 그 화면을 위에 쌓는다")
    func chartAndFavoritesRoutesArePushed() async {
        let chart = makeCoordinatorStore(CoordinatorFixture.launching(launchRoute: .chart))
        await chart.send(Self.syncCompleted) {
            $0.pendingLaunchRoute = nil
        }
        #expect(chart.state.rootScreen == .carve)
        #expect(chart.state.pathScreens == [.chart])
        await chart.finish()

        let favorites = makeCoordinatorStore(CoordinatorFixture.launching(launchRoute: .favorites))
        await favorites.send(Self.syncCompleted) {
            $0.pendingLaunchRoute = nil
        }
        #expect(favorites.state.pathScreens == [.favorites])
        await favorites.finish()
    }

    @Test("notebooks — 필사 화면에 들어가며 책장을 위에 쌓는다")
    func notebooksRouteIsPushed() async {
        #expect(Route.parse(arguments: ["/Applications/Carve.app/Carve", LaunchArgument.uiTestRoute, "notebooks"]) == .notebooks)
        let store = makeCoordinatorStore(CoordinatorFixture.launching(launchRoute: .notebooks))

        await store.send(Self.syncCompleted) {
            $0.pendingLaunchRoute = nil
        }
        #expect(store.state.rootScreen == .carve)
        #expect(store.state.pathScreens == [.notebooks])
        await store.finish()
    }

    @Test("navigation — 성경 탐색의 열을 모두 열고 지금 장을 고른 목록으로 시작한다")
    func navigationRouteOpensNavigationColumns() async {
        let store = makeCoordinatorStore(CoordinatorFixture.launching(launchRoute: .navigation))

        await store.send(Self.syncCompleted) {
            $0.pendingLaunchRoute = nil
        }
        #expect(store.state.carve?.columnVisibility == .detailOnly)
        await store.receive(Self.isOpenNavigation)
        #expect(store.state.carve?.columnVisibility == .all)
        #expect(store.state.carve?.carveDetailState.headerState.isNavigationPresented == true)
        // 탐색을 열면 현재 성경의 필사 기록을 읽는다 — 이 시험 번들에서는 인메모리 시험 저장소를 읽기만 한다.
        await store.finish()
    }

    @Test("verse/<절> — 시작 장(-UITestChapter)의 그 절로 간다")
    func verseRouteMovesToVerseInStartChapter() async throws {
        let start = BibleChapter(title: .john, chapter: 3)
        let chapterJSON = try #require(String(bytes: try JSONEncoder().encode(start), encoding: .utf8))
        let store = makeCoordinatorStore({ () -> AppCoordinatorFeature.State in
            // 앱 진입점처럼 Store 를 만들기 전에 시작 장을 저장한다.
            UITestLaunchChapter.apply(arguments: [LaunchArgument.uiTestChapter, chapterJSON])
            return CoordinatorFixture.launching(launchRoute: .verse(16))
        }())

        await store.send(Self.syncCompleted) {
            $0.pendingLaunchRoute = nil
        }
        await store.receive(\.root.presented.carve.moveToVerse, BibleVerse(title: start, verse: 16, sentence: ""))
        await store.finish()
    }

    @Test("모르는 경로는 무시한다 — 경로 없이 필사 화면으로 들어가고 다른 화면은 닫혀 있다")
    func unknownRouteIsIgnored() async {
        let route = Route.parse(arguments: ["/Applications/Carve.app/Carve", LaunchArgument.uiTestRoute, "settings/unknown"])
        #expect(route == nil)
        let store = makeCoordinatorStore(CoordinatorFixture.launching(launchRoute: route))

        await store.send(Self.syncCompleted)

        #expect(store.state.rootScreen == .carve)
        #expect(store.state.settings == nil)
        #expect(store.state.pathScreens.isEmpty)
        #expect(store.state.carve?.columnVisibility == .detailOnly)
        await store.finish()
    }

    // MARK: 억제 스위치

    @Test("억제 스위치는 첫 안내를 본 것으로, 앞서 들어간 설치의 버전을 지금 버전으로 저장한다")
    func suppressionStoresFlags() throws {
        let suite = "AppCoordinatorLaunchRouteTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("2.0.0", forKey: "lastSeenAppVersion")

        withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            AppCoordinatorFeature.applyLaunchSuppression(
                arguments: [LaunchArgument.uiTestSkipFirstRunGuide, LaunchArgument.uiTestSkipPatchnote],
                appVersion: "2.0.1"
            )
        }

        #expect(defaults.bool(forKey: "hasSeenFirstRunGuide"))
        #expect(defaults.string(forKey: "lastSeenAppVersion") == "2.0.1")
    }

    @Test("패치노트 억제는 새 설치의 빈 버전을 채우지 않는다 — 시작 화면이 그 값으로 새 설치(「먼저 시작하기」)를 가린다")
    func skipPatchnoteKeepsFreshInstallEmpty() throws {
        let suite = "AppCoordinatorLaunchRouteTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            AppCoordinatorFeature.applyLaunchSuppression(arguments: [LaunchArgument.uiTestSkipPatchnote], appVersion: "2.0.1")
            // 억제 인자가 없으면 아무것도 쓰지 않는다.
            AppCoordinatorFeature.applyLaunchSuppression(arguments: [LaunchArgument.uiTestRoute, "settings"], appVersion: "2.0.1")
        }

        #expect(defaults.object(forKey: "lastSeenAppVersion") == nil)
        #expect(defaults.object(forKey: "hasSeenFirstRunGuide") == nil)
    }

    @Test("패치노트 억제 — 버전이 바뀐 설치도 필사 화면에 들어가며 패치노트를 띄우지 않는다")
    func skipPatchnoteSuppressesPatchnoteOnEntry() async {
        let store = makeCoordinatorStore({ () -> AppCoordinatorFeature.State in
            // 지난 실행이 남긴 버전(2.0.0) 위에서 앱 진입점이 억제를 저장한 뒤 Store 를 만든다.
            let state = CoordinatorFixture.launching(lastSeenAppVersion: "2.0.0")
            AppCoordinatorFeature.applyLaunchSuppression(arguments: [LaunchArgument.uiTestSkipPatchnote], appVersion: "2.0.1")
            return state
        }(), appVersion: "2.0.1")

        await store.send(Self.syncCompleted) {
            $0.patchnote = nil
        }
        #expect(store.state.rootScreen == .carve)
        #expect(store.state.lastSeenAppVersion == "2.0.1")
        await store.finish()
    }

    @Test("첫 안내 억제 — 필사 화면이 나타나도 첫 안내를 띄우지 않는다")
    func skipFirstRunGuideSuppressesGuide() async {
        // 필사 화면이 나타나면 보내는 액션(`CarveNavigationView.onAppear`).
        let appeared = AppCoordinatorFeature.Action.root(.presented(.carve(.view(.presentFirstRunGuide))))

        let plain = makeCoordinatorStore(CoordinatorFixture.launching())
        await plain.send(Self.syncCompleted)
        await plain.send(appeared)
        #expect(plain.state.carve?.firstRunGuide != nil)
        await plain.finish()

        let suppressed = makeCoordinatorStore({ () -> AppCoordinatorFeature.State in
            AppCoordinatorFeature.applyLaunchSuppression(arguments: [LaunchArgument.uiTestSkipFirstRunGuide], appVersion: CoordinatorFixture.appVersion)
            return CoordinatorFixture.launching()
        }())
        await suppressed.send(Self.syncCompleted)
        await suppressed.send(appeared)
        #expect(suppressed.state.carve?.firstRunGuide == nil)
        #expect(suppressed.state.carve?.hasPresentedFirstRunGuide == true)
        await suppressed.finish()
    }
}

// MARK: - 필사 백업 — 백업 전 flush 중계 (설계 backup-import-design §5-2)

/// 설정의 「백업 만들기」 가 보낸 flush 요청을 필사 화면으로 넘기고, 그 답을 설정으로 돌려준다.
/// Feature 끼리는 서로를 모르므로 코디네이터만이 이 둘을 잇는다 — 이 중계가 빠지면 「백업 만들기」 는 답을 받지 못해 10초 시한으로만 끝난다.
@Suite("코디네이터 — 필사 백업 flush 중계")
@MainActor
struct AppCoordinatorBackupFlushTesting {
    private nonisolated static let requestID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

    /// 그 id 의 flush 답을 기다리는 「백업 만들기」 를 연 설정.
    private static func settingsAwaitingFlush() -> SettingsFeature.State {
        var backup = BackupFeature.State()
        backup.export.step = .flushing(id: requestID)
        backup.export.password = "abcd1234"
        backup.export.passwordConfirmation = "abcd1234"
        return SettingsFeature.State.initialState(path: .backup(backup))
    }

    /// 설정의 「백업 만들기」 가 보낸 flush 요청.
    private static var flushRequested: AppCoordinatorFeature.Action {
        .settings(.presented(.path(.presented(.backup(.export(.delegate(.canvasFlushRequested(id: requestID))))))))
    }

    /// 필사 화면의 캔버스가 보낸 flush 답.
    private static func canvasAnswered(_ outcome: CanvasFlushOutcome) -> AppCoordinatorFeature.Action {
        .root(.presented(.carve(.scope(.carveDetailAction(.scope(.chapterCanvasAction(
            .delegate(.backupFlushFinished(id: requestID, outcome: outcome))
        )))))))
    }

    /// 코디네이터가 캔버스로 넘긴 요청인가.
    private static func isCanvasRequest(_ action: AppCoordinatorFeature.Action) -> Bool {
        guard case .root(.presented(.carve(.scope(.carveDetailAction(.scope(.chapterCanvasAction(.backupFlushRequested(let id)))))))) = action else {
            return false
        }
        return id == requestID
    }

    /// 코디네이터가 설정으로 돌려준 답인가.
    private static func isAnswerToSettings(_ outcome: CanvasFlushOutcome) -> (AppCoordinatorFeature.Action) -> Bool {
        { action in
            guard case .settings(.presented(.canvasFlushFinished(let id, let received))) = action else { return false }
            return id == requestID && received == outcome
        }
    }

    /// 설정의 「백업 만들기」 단계.
    private func exportStep(_ store: TestStoreOf<AppCoordinatorFeature>) -> BackupExportFeature.Step? {
        store.state.settings?.path?.backup?.export.step
    }

    /// 효과가 다 끝나기를 기다린 뒤 받은 액션을 모두 소비한다 — 비망라 TestStore 의 `store.state` 는 소비해야 반영된다(룰북 testing.md).
    private func settle(_ store: TestStoreOf<AppCoordinatorFeature>) async {
        await store.finish()
        await store.skipReceivedActions(strict: false)
    }

    /// durable 이면 「백업 만들기」 가 파일 만들기를 시작한다 — 기본 파일 이름의 날짜를 고정한다.
    private func fixDate(_ store: TestStoreOf<AppCoordinatorFeature>) {
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 1_791_288_000))
        store.dependencies.timeZone = .gmt
    }

    @Test("필사 화면이 있으면 요청을 캔버스로 넘기고, 캔버스의 답을 설정의 백업 만들기로 돌려준다")
    func relaysRequestToCanvasAndAnswerBack() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(settings: Self.settingsAwaitingFlush()))
        fixDate(store)

        await store.send(Self.flushRequested)
        await store.receive(Self.isCanvasRequest)
        // 지킬 편집이 없는 캔버스는 곧바로 durable 로 답한다.
        await store.receive(Self.isAnswerToSettings(.durable))
        await settle(store)
        // durable 이라 파일 만들기를 시작했다 — 이 시험 번들에는 내보내기가 주입되지 않아 그 사유로 끝난다.
        #expect(exportStep(store) == .exportFailed(.unavailable))
    }

    @Test("필사 화면이 없으면(시작 화면) 곧바로 durable 로 답한다")
    func answersDurableWithoutWritingScreen() async {
        let store = makeCoordinatorStore({ () -> AppCoordinatorFeature.State in
            var state = CoordinatorFixture.launching()
            state.settings = Self.settingsAwaitingFlush()
            return state
        }())
        fixDate(store)

        await store.send(Self.flushRequested)
        await store.receive(Self.isAnswerToSettings(.durable))
        await settle(store)
        #expect(store.state.rootScreen == .launchProgress)
        #expect(exportStep(store) == .exportFailed(.unavailable))
    }

    @Test("캔버스의 답이 durable 이 아니면 그대로 돌려준다 — 백업 만들기는 파일을 만들지 않고 막는다",
          arguments: [CanvasFlushOutcome.failed(retryCount: 2), .timedOut])
    func relaysNonDurableAnswerBack(outcome: CanvasFlushOutcome) async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing(settings: Self.settingsAwaitingFlush()))

        await store.send(Self.canvasAnswered(outcome))
        await store.receive(Self.isAnswerToSettings(outcome))
        await settle(store)
        #expect(exportStep(store) == .flushBlocked(outcome))
    }

    @Test("설정이 닫혀 있으면 캔버스의 늦은 답을 버린다")
    func dropsAnswerWhenSettingsClosed() async {
        let store = makeCoordinatorStore(CoordinatorFixture.writing())
        // 받은 액션이 하나라도 있으면 실패하게 전부 확인한다.
        store.exhaustivity = .on

        await store.send(Self.canvasAnswered(.durable))
        await store.finish()
        #expect(store.state.settings == nil)
    }
}
