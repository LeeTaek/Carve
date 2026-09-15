//
//  SentenceSettingsBackupTesting.swift
//  CarveFeatureTest
//
//  본문 모양 iCloud 백업 — 본문 설정이 사용자의 선택을 넘기는지, 되살린 값을 필사 화면의 공유 상태가 그대로 읽는지.
//  `SentenceSettingsFeature.State` 는 Equatable 이 아니라 TestStore 대신 실제 Store 로 본다.
//

@testable import CarveFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

/// 본문 설정이 넘긴 선택을 기록한다.
private final class SentenceSettingBackupSpy: SentenceSettingBackupClient {
    let saved = LockIsolated<[SentenceSetting]>([])

    func saveUserChoice(_ setting: SentenceSetting) {
        saved.withValue { $0.append(setting) }
    }
}

/// 메모리에 두는 iCloud 키-값 저장소.
private final class InMemoryCloudStore: SentenceSettingCloudStore {
    let notificationCenter = NotificationCenter()
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ data: Data?, forKey key: String) {
        values[key] = data
    }

    func synchronize() -> Bool {
        true
    }

    /// 알림 없이 값을 둔다 — 실행 전에 이미 내려와 있던 백업.
    func preload(_ data: Data?) {
        values[SentenceSettingCloudBackup.cloudKey] = data
    }

    /// iCloud 에서 값이 내려온 것처럼 저장하고 외부 변경 알림을 보낸다.
    func receiveFromCloud(_ data: Data?) {
        preload(data)
        notificationCenter.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [SentenceSettingCloudBackup.cloudKey]]
        )
    }
}

@Suite("본문 모양 iCloud 백업 — 본문 설정 · 공유 상태 배선")
@MainActor
struct SentenceSettingsBackupTesting {
    /// 다른 기기에서 고른 본문 모양.
    private static let chosenElsewhere = SentenceSetting(
        lineSpace: 45,
        fontSize: 28,
        traking: 3,
        baseLineHeight: 20,
        textHeight: .zero,
        fontFamily: .flower,
        lineCount: 3
    )

    private func makeStore(defaults: UserDefaults, spy: SentenceSettingBackupSpy) -> StoreOf<SentenceSettingsFeature> {
        Store(initialState: SentenceSettingsFeature.State()) {
            SentenceSettingsFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
            $0.sentenceSettingBackup = spy
        }
    }

    @Test("글꼴 · 글자 크기 · 줄 간격 · 자간을 바꾸면 바뀐 값을 백업에 넘긴다")
    func settingChangesAreBackedUp() async throws {
        let suite = "SentenceSettingsBackupTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SentenceSettingBackupSpy()
        let store = makeStore(defaults: defaults, spy: spy)

        await store.send(.setFontFamily(.gothic)).finish()
        await store.send(.setFontSize(28)).finish()
        await store.send(.setLineSpace(45)).finish()
        await store.send(.setTraking(3)).finish()

        var afterFont = SentenceSetting.initialState
        afterFont.fontFamily = .gothic
        var afterFontSize = afterFont
        afterFontSize.fontSize = 28
        var afterLineSpace = afterFontSize
        afterLineSpace.lineSpace = 45
        var afterTraking = afterLineSpace
        afterTraking.traking = 3
        #expect(spy.saved.value == [afterFont, afterFontSize, afterLineSpace, afterTraking])
    }

    @Test("값이 그대로면 넘기지 않는다 — 슬라이더를 건드리기만 한 것은 이 설치의 선택으로 치지 않는다")
    func unchangedValuesAreNotBackedUp() async throws {
        let suite = "SentenceSettingsBackupTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SentenceSettingBackupSpy()
        let store = makeStore(defaults: defaults, spy: spy)

        await store.send(.setFontSize(SentenceSetting.initialState.fontSize)).finish()
        await store.send(.setFontFamily(SentenceSetting.initialState.fontFamily)).finish()
        await store.send(.resetSetting).finish()

        #expect(spy.saved.value.isEmpty)
    }

    @Test("왼손 모드 · 손가락 필사는 백업하지 않는다")
    func handednessAndFingerDrawingAreNotBackedUp() async throws {
        let suite = "SentenceSettingsBackupTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SentenceSettingBackupSpy()
        let store = makeStore(defaults: defaults, spy: spy)

        await store.send(.setLeftHanded(true)).finish()
        await store.send(.setAllowFingerDrawing(true)).finish()

        #expect(spy.saved.value.isEmpty)
    }

    @Test("초기화로 값이 달라지면 기본값을 넘긴다")
    func resetIsBackedUpWhenValuesChange() async throws {
        let suite = "SentenceSettingsBackupTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SentenceSettingBackupSpy()
        let store = makeStore(defaults: defaults, spy: spy)

        await store.send(.setFontSize(32)).finish()
        await store.send(.resetSetting).finish()

        #expect(spy.saved.value.count == 2)
        #expect(spy.saved.value.last == .initialState)
    }

    @Test("실행 때 되살린 값을 필사 화면의 공유 상태가 그대로 읽는다 — CodableAppStorageKey 와 같은 저장 형식")
    func restoredSettingLoadsThroughSharedAppStorage() throws {
        let suite = "SentenceSettingsBackupTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = InMemoryCloudStore()
        cloud.preload(try JSONEncoder().encode(SentenceSettingBackup(Self.chosenElsewhere)))

        SentenceSettingCloudBackup(defaults: defaults, cloud: cloud, notificationCenter: cloud.notificationCenter).start()
        let shared = withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            Shared(wrappedValue: SentenceSetting.initialState, .appStorage(SentenceSetting.appStorageKey))
        }

        #expect(shared.wrappedValue == Self.chosenElsewhere)
    }

    @Test("화면이 뜬 뒤에 도착한 백업도 이미 올라온 공유 상태를 바꾼다")
    func lateBackupUpdatesLoadedSharedState() async throws {
        let suite = "SentenceSettingsBackupTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = InMemoryCloudStore()
        let backup = SentenceSettingCloudBackup(defaults: defaults, cloud: cloud, notificationCenter: cloud.notificationCenter)
        backup.start()
        // 화면이 먼저 떠서 기본값을 읽었다 — 처음 읽을 때 기본값을 저장한다.
        let shared = withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            Shared(wrappedValue: SentenceSetting.initialState, .appStorage(SentenceSetting.appStorageKey))
        }
        #expect(shared.wrappedValue == .initialState)

        let data = try JSONEncoder().encode(SentenceSettingBackup(Self.chosenElsewhere))
        withExtendedLifetime(backup) {
            cloud.receiveFromCloud(data)
        }
        await drainMainQueue()

        #expect(shared.wrappedValue == Self.chosenElsewhere)
    }

    /// 메인 큐에 먼저 들어간 작업(공유 상태 구독의 전달)이 끝나기를 기다린다.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
