//
//  AppCoordinatorLaunchTesting.swift
//  CarveAppTest
//
//  시작 화면 → 필사 화면. 시작 화면이 들어갈 수 있을 때만(`route == .enterWriting`) 바꾸고, 이번 버전을 남기며,
//  버전이 바뀌었으면 패치노트를 띄운다. 연결을 보류한 실행은 들어간 뒤 편집 환경을 지켜보다가 재실행을 안내한다.
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@Suite("코디네이터 — 시작 화면에서 필사 화면으로")
@MainActor
struct AppCoordinatorLaunchTesting {
    /// 시작 화면이 진입을 알린다.
    private static var syncCompleted: AppCoordinatorFeature.Action {
        .root(.presented(.launchProgress(.syncCompleted)))
    }

    /// 마이그레이션이 끝나 재실행을 요구하는 시작 화면 — 들어가지 않는다.
    private static func launchRequiringRestart() -> LaunchProgressFeature.State {
        var launch = LaunchProgressFeature.State()
        launch.mode = .normal
        launch.syncState = .migrationCompleted
        return launch
    }

    @Test("처음 들어가는 설치는 필사 화면으로 바꾸고 이번 버전을 남긴다 — 패치노트는 띄우지 않는다")
    func firstEntryRecordsVersionWithoutPatchnote() async {
        let store = makeCoordinatorStore(CoordinatorFixture.launching(lastSeenAppVersion: nil))

        await store.send(Self.syncCompleted) {
            $0.patchnote = nil
        }

        #expect(store.state.rootScreen == .carve)
        #expect(store.state.lastSeenAppVersion == CoordinatorFixture.appVersion)
        await store.finish()
    }

    @Test("마지막으로 본 버전과 지금 버전이 다르면 들어가면서 패치노트를 띄우고 지금 버전을 남긴다")
    func updatedVersionShowsPatchnote() async {
        let store = makeCoordinatorStore(CoordinatorFixture.launching(lastSeenAppVersion: "2.0.0"), appVersion: "2.0.1")

        await store.send(Self.syncCompleted) {
            $0.patchnote = .initialState
        }

        #expect(store.state.rootScreen == .carve)
        #expect(store.state.lastSeenAppVersion == "2.0.1")
        await store.finish()
    }

    @Test("같은 버전으로 다시 들어가면 패치노트를 띄우지 않는다")
    func sameVersionSkipsPatchnote() async {
        let store = makeCoordinatorStore(CoordinatorFixture.launching(lastSeenAppVersion: "2.0.1"), appVersion: "2.0.1")

        await store.send(Self.syncCompleted) {
            $0.patchnote = nil
        }

        #expect(store.state.rootScreen == .carve)
        #expect(store.state.lastSeenAppVersion == "2.0.1")
        await store.finish()
    }

    @Test("시작 화면이 들어갈 상태가 아니면(재실행 요구) 필사 화면으로 바꾸지 않고 버전도 남기지 않는다 (MIG-F1)")
    func launchThatCannotEnterStays() async {
        #expect(Self.launchRequiringRestart().route == .restartRequired)
        let store = makeCoordinatorStore(
            CoordinatorFixture.launching(Self.launchRequiringRestart(), lastSeenAppVersion: "2.0.0")
        )

        await store.send(Self.syncCompleted)

        #expect(store.state.rootScreen == .launchProgress)
        #expect(store.state.patchnote == nil)
        #expect(store.state.lastSeenAppVersion == "2.0.0")
    }

    @Test("연결을 보류한 실행은 들어간 뒤 편집 환경을 지켜보다가, 다시 열면 연결되는 환경이 오면 재실행을 안내한다")
    func heldLaunchShowsRelaunchGuidance() async {
        let store = makeCoordinatorStore(
            CoordinatorFixture.launching(),
            hold: LegacySeparationHold(reason: .ownershipUnverified),
            environment: CoordinatorFixture.relaunchable
        )

        await store.send(Self.syncCompleted)
        #expect(store.state.rootScreen == .carve)
        // 연결을 기다리는 로딩은 띄우지 않는다 — 환경을 읽어 안내만 한다.
        await store.receive(\.connectionEnvironmentChanged, CoordinatorFixture.relaunchable) {
            $0.showsRelaunchGuidance = true
            $0.didShowRelaunchGuidance = true
        }
        await store.finish()
    }

    @Test("앱 버전 의존성의 시험 기본값은 빈 문자열이다 — 버전을 보는 시험은 직접 정한다")
    func appVersionTestValueIsEmpty() {
        @Dependency(\.appVersion) var appVersion
        #expect(appVersion.isEmpty)
    }
}
