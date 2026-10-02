//
//  AppCoordinatorCanvasRemovalNoticeTesting.swift
//  CarveAppTest
//
//  N-Canvas 제거 안내(2.1 결정 6) — 2.0.x 에서 「필사 캔버스」 를 끈 사용자(`singleCanvasEnabled` 가 Bool false)에게만
//  필사 화면에 처음 들어갈 때 막지 않는 안내를 한 번 띄운다. 어느 버튼이든 두 키를 지워 다시 띄우지 않고, 값이 없거나 true 면 안내 없이 키만 지운다.
//
//  ⚠️ 필사 화면 상태에 `singleCanvasEnabled` 를 기본값(true)과 함께 읽는 `@Shared(.appStorage)` 가 남아 있으면, 그 값은 지운 직후 기본값으로
//     다시 쓰인다(Sharing 이 없는 키에 기본값을 쓴다). 그래서 필사 화면에 들어간 뒤의 시험은 「false 가 남지 않았다」 만 보고,
//     두 키를 정확히 지우는지는 필사 화면이 없는 상태에서 버튼 액션을 보내는 시험(`buttonsRemoveBothKeys`)이 본다.
//

import Foundation
import SettingsFeature
import Testing

import ComposableArchitecture

@Suite("코디네이터 — N-Canvas 제거 안내")
@MainActor
struct AppCoordinatorCanvasRemovalNoticeTesting {
    private typealias Keys = AppCoordinatorFeature.CanvasRemovalNotice

    /// 시작 화면이 진입을 알린다.
    private static var syncCompleted: AppCoordinatorFeature.Action {
        .root(.presented(.launchProgress(.syncCompleted)))
    }

    /// 시험마다 따로 쓰는 UserDefaults 와 그 이름. 끝나면 `removePersistentDomain` 으로 지운다.
    private static func makeDefaults() throws -> (defaults: UserDefaults, suite: String) {
        let suite = "AppCoordinatorCanvasRemovalNoticeTesting.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// 2.0.x 에서 「필사 캔버스」 를 끈 설치 — 2.0.x 가 남긴 초기화 기록도 있다.
    private static func storeTurnedOffSetting(in defaults: UserDefaults) {
        defaults.set(false, forKey: Keys.singleCanvasEnabledKey)
        defaults.set(true, forKey: Keys.storedValueResetKey)
    }

    @Test("「필사 캔버스」 를 끈 사용자는 필사 화면에 들어갈 때 안내를 보고, 「확인」 으로 닫으면 다음 실행에서는 띄우지 않는다")
    func turnedOffUserSeesNoticeOnce() async throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        Self.storeTurnedOffSetting(in: defaults)

        // when: 필사 화면에 들어간다.
        let store = makeCoordinatorStore(CoordinatorFixture.launching(), appStorage: defaults)
        await store.send(Self.syncCompleted) {
            $0.showsCanvasRemovalNotice = true
        }
        #expect(store.state.rootScreen == .carve)
        // 버튼을 누르기 전에는 키를 지우지 않는다 — 앱을 그냥 닫으면 다음 실행에서 다시 알린다.
        #expect(defaults.object(forKey: Keys.singleCanvasEnabledKey) as? Bool == false)
        #expect(defaults.object(forKey: Keys.storedValueResetKey) != nil)

        // then: 「확인」 은 안내를 내리고 키를 지운다. 설정은 열지 않는다.
        await store.send(.canvasRemovalNoticeDismissed) {
            $0.showsCanvasRemovalNotice = false
        }
        #expect(store.state.settings == nil)
        #expect(defaults.object(forKey: Keys.singleCanvasEnabledKey) as? Bool != false)
        #expect(defaults.object(forKey: Keys.storedValueResetKey) == nil)
        await store.finish()

        // 다음 실행 — 같은 저장소로 다시 들어가도 안내는 없다.
        let relaunched = makeCoordinatorStore(CoordinatorFixture.launching(), appStorage: defaults)
        await relaunched.send(Self.syncCompleted)
        #expect(relaunched.state.rootScreen == .carve)
        #expect(!relaunched.state.showsCanvasRemovalNotice)
        await relaunched.finish()
    }

    @Test("안내의 「의견 보내기」 는 안내를 내리고 키를 지운 뒤 설정의 「의견 보내기」 를 연다")
    func feedbackButtonOpensSendFeedback() async throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        Self.storeTurnedOffSetting(in: defaults)

        let store = makeCoordinatorStore(CoordinatorFixture.launching(), appStorage: defaults)
        await store.send(Self.syncCompleted) {
            $0.showsCanvasRemovalNotice = true
        }

        await store.send(.canvasRemovalNoticeFeedbackTapped) {
            $0.showsCanvasRemovalNotice = false
            $0.settings = SettingsFeature.State.initialState(path: .sendFeedback(.initialState))
        }
        #expect(store.state.settings?.selectedSidebarItem == .sendFeedback)
        #expect(defaults.object(forKey: Keys.singleCanvasEnabledKey) as? Bool != false)
        #expect(defaults.object(forKey: Keys.storedValueResetKey) == nil)
        await store.finish()
    }

    @Test("안내의 두 버튼은 어느 것이든 두 키를 지운다")
    func buttonsRemoveBothKeys() async throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions: [AppCoordinatorFeature.Action] = [.canvasRemovalNoticeDismissed, .canvasRemovalNoticeFeedbackTapped]

        for action in actions {
            // given: 키가 남은 설치. 시작 화면 상태라 이 키를 읽는 다른 화면이 없다.
            Self.storeTurnedOffSetting(in: defaults)
            let store = makeCoordinatorStore({ () -> AppCoordinatorFeature.State in
                var state = CoordinatorFixture.launching()
                state.showsCanvasRemovalNotice = true
                return state
            }(), appStorage: defaults)

            // when
            await store.send(action) {
                $0.showsCanvasRemovalNotice = false
            }

            // then
            #expect(defaults.object(forKey: Keys.singleCanvasEnabledKey) == nil)
            #expect(defaults.object(forKey: Keys.storedValueResetKey) == nil)
            await store.finish()
        }
    }

    @Test("「필사 캔버스」 가 켜져 있던(true) 사용자는 안내 없이 들어가고, 남은 키를 지운다")
    func turnedOnUserSkipsNotice() async throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: Keys.singleCanvasEnabledKey)
        defaults.set(true, forKey: Keys.storedValueResetKey)

        let store = makeCoordinatorStore(CoordinatorFixture.launching(), appStorage: defaults)
        await store.send(Self.syncCompleted)

        #expect(store.state.rootScreen == .carve)
        #expect(!store.state.showsCanvasRemovalNotice)
        #expect(defaults.object(forKey: Keys.storedValueResetKey) == nil)
        await store.finish()
    }

    @Test("토글 값이 없는 설치(새 설치 · 만진 적 없음)는 안내 없이 들어가고, 남은 초기화 기록을 지운다")
    func missingValueSkipsNotice() async throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        // 2.0.x 가 값을 한 번 지우고 기록만 남긴 설치.
        defaults.set(true, forKey: Keys.storedValueResetKey)

        let store = makeCoordinatorStore(CoordinatorFixture.launching(), appStorage: defaults)
        await store.send(Self.syncCompleted)

        #expect(store.state.rootScreen == .carve)
        #expect(!store.state.showsCanvasRemovalNotice)
        #expect(defaults.object(forKey: Keys.singleCanvasEnabledKey) as? Bool != false)
        #expect(defaults.object(forKey: Keys.storedValueResetKey) == nil)
        await store.finish()
    }

    @Test("들어갈 수 없는 시작 화면(재실행 요구)에서는 키를 읽지도 지우지도 않는다")
    func blockedLaunchKeepsKeys() async throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        Self.storeTurnedOffSetting(in: defaults)
        var launch = LaunchProgressFeature.State()
        launch.mode = .normal
        launch.syncState = .migrationCompleted

        let store = makeCoordinatorStore(CoordinatorFixture.launching(launch), appStorage: defaults)
        await store.send(Self.syncCompleted)

        #expect(store.state.rootScreen == .launchProgress)
        #expect(!store.state.showsCanvasRemovalNotice)
        // 필사 화면에 들어가는 다음 실행에서 알릴 수 있게 그대로 둔다.
        #expect(defaults.object(forKey: Keys.singleCanvasEnabledKey) as? Bool == false)
        #expect(defaults.object(forKey: Keys.storedValueResetKey) != nil)
    }
}
