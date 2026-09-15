//
//  SentenceSettingCloudBackupTesting.swift
//  DomainTest
//
//  본문 모양 iCloud 백업 — 사용자가 바꿀 때만 올리고, 아직 바꾸지 않은 설치에만 되살린다.
//

@testable import Domain
import Foundation
import Testing

/// 메모리에 두는 iCloud 키-값 저장소. `receiveFromCloud` 로 다른 기기의 변경 · 늦게 끝난 초기 동기화를 흉내 낸다.
private final class InMemoryCloudStore: SentenceSettingCloudStore {
    let notificationCenter = NotificationCenter()
    private var values: [String: Data] = [:]
    /// 앱이 쓴 키. iCloud 에서 내려온 값은 넣지 않는다.
    private(set) var writtenKeys: [String] = []

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ data: Data?, forKey key: String) {
        values[key] = data
        writtenKeys.append(key)
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
        notifyChange(keys: [SentenceSettingCloudBackup.cloudKey])
    }

    /// 외부 변경 알림을 보낸다.
    func notifyChange(keys: [String]) {
        notificationCenter.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: keys]
        )
    }
}

/// 테스트 하나가 쓰는 기기 저장소와 iCloud 저장소.
private struct Fixture {
    let suite: String
    let defaults: UserDefaults
    let cloud = InMemoryCloudStore()

    init() throws {
        let suite = "SentenceSettingCloudBackupTesting.\(UUID().uuidString)"
        self.suite = suite
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    func makeBackup() -> SentenceSettingCloudBackup {
        SentenceSettingCloudBackup(defaults: defaults, cloud: cloud, notificationCenter: cloud.notificationCenter)
    }

    /// 기기에 저장된 본문 설정.
    func storedSetting() throws -> SentenceSetting? {
        try defaults.data(forKey: SentenceSetting.appStorageKey).map { try JSONDecoder().decode(SentenceSetting.self, from: $0) }
    }

    /// `@Shared(.appStorage)` 처럼 기기에 본문 설정을 저장한다.
    func storeSetting(_ setting: SentenceSetting) throws {
        defaults.set(try JSONEncoder().encode(setting), forKey: SentenceSetting.appStorageKey)
    }

    /// iCloud 에 있는 백업.
    func cloudBackup() throws -> SentenceSettingBackup? {
        try cloud.data(forKey: SentenceSettingCloudBackup.cloudKey).map { try JSONDecoder().decode(SentenceSettingBackup.self, from: $0) }
    }

    func removeDefaults() {
        defaults.removePersistentDomain(forName: suite)
    }
}

/// `setting` 의 네 항목을 담은 백업 데이터.
private func backupData(_ setting: SentenceSetting) throws -> Data {
    try JSONEncoder().encode(SentenceSettingBackup(setting))
}

@Suite("본문 모양 iCloud 백업 — 설치 판정 · 되살리기 · 올리기")
struct SentenceSettingCloudBackupTesting {
    /// 다른 기기에서 고른 본문 모양. 사용자가 고르지 않는 값(줄 수 · 기준 줄 높이)도 기본값과 다르게 둬서 덮지 않는지 본다.
    private static let chosenElsewhere = SentenceSetting(
        lineSpace: 45,
        fontSize: 28,
        traking: 3,
        baseLineHeight: 99,
        textHeight: 12,
        fontFamily: .flower,
        lineCount: 9
    )
    /// 1.x 에서 설정을 건드리지 않은 사용자에게 저장된 값 — 그때 기본 글꼴은 나눔바른고딕(`gothic`)이었다.
    private static let legacyDefault = SentenceSetting(
        lineSpace: 30,
        fontSize: 20,
        traking: 1,
        baseLineHeight: 20,
        textHeight: .zero,
        fontFamily: .gothic,
        lineCount: 3
    )
    /// 새 설치의 기본값에 다른 기기의 네 항목을 덮은 값.
    private static let restoredOnFreshInstall = SentenceSettingBackup(chosenElsewhere).applied(to: .initialState)

    @Test("새 설치 — iCloud 에 백업이 있으면 시작할 때 네 항목만 되살리고, 다른 값은 기본값을 둔다")
    func freshInstallRestoresBackupOnStart() throws {
        let fixture = try Fixture()
        defer { fixture.removeDefaults() }
        fixture.cloud.preload(try backupData(Self.chosenElsewhere))

        fixture.makeBackup().start()

        let restored = try #require(try fixture.storedSetting())
        #expect(restored == Self.restoredOnFreshInstall)
        #expect(restored.lineCount == SentenceSetting.initialState.lineCount)
        #expect(restored.baseLineHeight == SentenceSetting.initialState.baseLineHeight)
        // 되살리기만으로는 올리지 않는다.
        #expect(fixture.cloud.writtenKeys.isEmpty)
    }

    @Test("새 설치 — 백업이 없으면 기기에도 iCloud 에도 쓰지 않는다")
    func freshInstallWithoutBackupWritesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.removeDefaults() }

        fixture.makeBackup().start()

        #expect(fixture.defaults.data(forKey: SentenceSetting.appStorageKey) == nil)
        #expect(fixture.cloud.writtenKeys.isEmpty)
        #expect(fixture.defaults.object(forKey: SentenceSettingCloudBackup.userChoiceKey) as? Bool == false)
    }

    @Test("새 설치 — 화면이 뜬 뒤 늦게 도착한 백업도 아직 바꾸지 않았으면 적용한다")
    func freshInstallRestoresLateBackup() throws {
        let fixture = try Fixture()
        defer { fixture.removeDefaults() }
        let backup = fixture.makeBackup()
        backup.start()
        // 화면이 먼저 떠서 `@Shared(.appStorage)` 가 기본값을 저장했다.
        try fixture.storeSetting(.initialState)

        let data = try backupData(Self.chosenElsewhere)
        withExtendedLifetime(backup) {
            fixture.cloud.receiveFromCloud(data)
        }

        #expect(try fixture.storedSetting() == Self.restoredOnFreshInstall)
    }

    @Test("다시 실행해도 새 설치 판정은 그대로다 — 바꾸기 전이면 다음 실행에도 되살린다")
    func secondLaunchKeepsFreshInstallDecision() throws {
        let fixture = try Fixture()
        defer { fixture.removeDefaults() }
        fixture.makeBackup().start()
        // 첫 실행에서 화면이 기본값을 저장했고, 백업은 앱이 꺼진 사이에 내려왔다.
        try fixture.storeSetting(.initialState)
        fixture.cloud.preload(try backupData(Self.chosenElsewhere))

        fixture.makeBackup().start()

        #expect(try fixture.storedSetting() == Self.restoredOnFreshInstall)
    }

    @Test("본문 모양을 바꾼 설치는 바꾼 값을 올리고, 그 뒤에 온 iCloud 값으로 덮지 않는다")
    func userChoiceIsUploadedAndNeverOverwritten() throws {
        let fixture = try Fixture()
        defer { fixture.removeDefaults() }
        let backup = fixture.makeBackup()
        backup.start()
        var mine = SentenceSetting.initialState
        mine.fontSize = 32
        try fixture.storeSetting(mine)

        backup.saveUserChoice(mine)
        #expect(try fixture.cloudBackup() == SentenceSettingBackup(mine))

        let data = try backupData(Self.chosenElsewhere)
        withExtendedLifetime(backup) {
            fixture.cloud.receiveFromCloud(data)
        }
        fixture.makeBackup().start()

        #expect(try fixture.storedSetting() == mine)
    }

    @Test("이 기능 전부터 쓰던 설치는 바꾼 설치로 보고, iCloud 가 비었으면 지금 값을 한 번 올린다")
    func existingInstallSeedsBackupOnce() throws {
        let fixture = try Fixture()
        defer { fixture.removeDefaults() }
        try fixture.storeSetting(Self.legacyDefault)
        let backup = fixture.makeBackup()

        backup.start()
        #expect(try fixture.cloudBackup() == SentenceSettingBackup(Self.legacyDefault))
        #expect(fixture.cloud.writtenKeys == [SentenceSettingCloudBackup.cloudKey])

        // 다른 기기가 올린 값은 이 기기 설정을 덮지 않고, 다음 실행에도 다시 올리지 않는다.
        let data = try backupData(Self.chosenElsewhere)
        withExtendedLifetime(backup) {
            fixture.cloud.receiveFromCloud(data)
        }
        fixture.makeBackup().start()

        #expect(try fixture.storedSetting() == Self.legacyDefault)
        #expect(fixture.cloud.writtenKeys == [SentenceSettingCloudBackup.cloudKey])
    }

    @Test("이 기능 전부터 쓰던 설치라도 iCloud 에 백업이 이미 있으면 올리지 않는다 — 다른 기기의 선택을 덮지 않는다")
    func existingInstallKeepsOtherDeviceBackup() throws {
        let fixture = try Fixture()
        defer { fixture.removeDefaults() }
        try fixture.storeSetting(Self.legacyDefault)
        fixture.cloud.preload(try backupData(Self.chosenElsewhere))

        fixture.makeBackup().start()

        #expect(fixture.cloud.writtenKeys.isEmpty)
        #expect(try fixture.storedSetting() == Self.legacyDefault)
    }

    @Test("읽을 수 없는 백업은 무시한다 — 이 빌드가 모르는 글꼴")
    func unreadableBackupIsIgnored() throws {
        let fixture = try Fixture()
        defer { fixture.removeDefaults() }
        fixture.cloud.preload(Data(#"{"fontFamily":"UnknownFont","fontSize":28,"lineSpace":45,"traking":3}"#.utf8))

        fixture.makeBackup().start()

        #expect(fixture.defaults.data(forKey: SentenceSetting.appStorageKey) == nil)
    }

    @Test("다른 키만 바뀐 알림으로는 백업을 다시 읽지 않는다")
    func ignoresChangesOfOtherKeys() throws {
        let fixture = try Fixture()
        defer { fixture.removeDefaults() }
        let backup = fixture.makeBackup()
        backup.start()
        fixture.cloud.preload(try backupData(Self.chosenElsewhere))

        withExtendedLifetime(backup) {
            fixture.cloud.notifyChange(keys: ["anotherKey"])
        }

        #expect(fixture.defaults.data(forKey: SentenceSetting.appStorageKey) == nil)
    }
}
