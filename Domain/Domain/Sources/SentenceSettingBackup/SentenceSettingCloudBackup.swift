//
//  SentenceSettingCloudBackup.swift
//  Domain
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 본문 모양 백업을 두는 키-값 저장소. 앱은 `NSUbiquitousKeyValueStore.default`(iCloud)를, 테스트는 메모리 저장소를 쓴다.
///
/// 다른 기기의 변경이나 늦게 끝난 초기 동기화로 값이 바뀌면, 이 저장소를 `object` 로 `NSUbiquitousKeyValueStore.didChangeExternallyNotification` 을 보낸다.
public protocol SentenceSettingCloudStore: AnyObject {
    /// `key` 에 저장된 데이터.
    func data(forKey key: String) -> Data?
    /// `key` 에 데이터를 저장한다. iCloud 로 올리는 시점은 시스템이 정한다.
    func set(_ data: Data?, forKey key: String)
    /// iCloud 와 맞춰 보도록 알린다. 새로 받은 값은 외부 변경 알림으로 온다.
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SentenceSettingCloudStore {}

/// 본문 모양(글꼴 · 글자 크기 · 줄 간격 · 자간)을 iCloud 키-값 저장소에 백업하고, 앱을 지웠다 다시 깐 기기에서 되살린다.
///
/// - **올리기:** 사용자가 본문 설정에서 값을 바꿀 때만(`saveUserChoice`). 실행만으로는 올리지 않는다 — 새로 깐 기기의 기본값이 백업을 덮으면 안 된다.
/// - **되살리기:** 이 설치에서 아직 본문 모양을 바꾸지 않았을 때만. 재설치 직후에는 백업이 아직 내려오지 않았다가 나중에 도착하기도 해서,
///   외부 변경 알림을 받을 때도 같은 조건으로 적용한다. 한 번이라도 바꾼 설치는 자기 값을 지키고 iCloud 값으로 덮지 않는다.
/// - **이 기능 전부터 쓰던 설치**(저장된 본문 설정이 이미 있음)는 바꾼 설치로 본다. iCloud 에 백업이 없을 때만 지금 값을 한 번 올린다.
///
/// 되살린 값은 `@Shared(.appStorage(SentenceSetting.appStorageKey))` 가 읽는 `UserDefaults` 에 같은 JSON 형식으로 쓴다.
/// 이미 화면에 올라온 공유 상태는 `CodableAppStorageKey` 의 변경 알림 구독이 새 값으로 바꾼다.
///
/// ⚠️ 앱은 본문 설정을 읽는 Store 를 만들기 **전에** `start()` 를 부른다. `@Shared(.appStorage)` 는 처음 읽을 때 기본값을 저장해서,
/// 그 뒤에는 새 설치인지 이 기능 전부터 쓰던 설치인지 가릴 수 없다.
public final class SentenceSettingCloudBackup: SentenceSettingBackupClient, @unchecked Sendable {
    /// iCloud 키-값 저장소에서 백업을 두는 키.
    public static let cloudKey = "sentenceSettingBackup"
    /// 이 설치에서 사용자가 본문 모양을 정했는지 기록하는 `UserDefaults` 키. 값이 없으면 아직 설치를 판정하기 전이다.
    public static let userChoiceKey = "sentenceSettingUserChosen"

    private let defaults: UserDefaults
    private let cloud: any SentenceSettingCloudStore
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var observation: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - defaults: 본문 설정이 저장된 `UserDefaults`. 앱은 `@Shared(.appStorage)` 와 같은 `.standard` 를 넘긴다.
    ///   - cloud: 백업을 두는 저장소.
    ///   - notificationCenter: 저장소의 외부 변경 알림을 받는 곳.
    public init(
        defaults: UserDefaults = .standard,
        cloud: any SentenceSettingCloudStore = NSUbiquitousKeyValueStore.default,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let observation {
            notificationCenter.removeObserver(observation)
        }
    }

    /// 설치를 판정하고, 되살릴 백업이 있으면 적용한 뒤 늦게 도착하는 백업을 기다린다. 실행 때 한 번 부른다.
    public func start() {
        classifyInstallIfNeeded()
        lock.withLock {
            guard observation == nil else { return }
            observation = notificationCenter.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud,
                queue: nil
            ) { [weak self] notification in
                guard let self, Self.changesBackup(notification) else { return }
                self.restoreIfUnchanged()
            }
        }
        restoreIfUnchanged()
        // 실행 때 iCloud 와 맞춰 보게 한다. 새 값은 외부 변경 알림으로 온다.
        _ = cloud.synchronize()
    }

    /// 사용자가 본문 모양을 바꿨다 — 이 설치를 「바꾼 설치」로 기록하고 바뀐 값을 iCloud 에 올린다.
    public func saveUserChoice(_ setting: SentenceSetting) {
        defaults.set(true, forKey: Self.userChoiceKey)
        upload(SentenceSettingBackup(setting))
    }

    /// 이 설치를 처음 한 번 판정한다.
    private func classifyInstallIfNeeded() {
        guard defaults.object(forKey: Self.userChoiceKey) == nil else { return }
        guard defaults.object(forKey: SentenceSetting.appStorageKey) != nil else {
            // 새 설치(재설치 포함) — 사용자가 바꾸기 전까지 iCloud 값을 받는다.
            defaults.set(false, forKey: Self.userChoiceKey)
            return
        }
        // 이 기능 전부터 쓰던 설치 — 저장된 값이 이 기기의 설정이다. 다른 기기가 이미 올린 백업은 덮지 않는다.
        defaults.set(true, forKey: Self.userChoiceKey)
        guard cloud.data(forKey: Self.cloudKey) == nil, let stored = storedSetting() else { return }
        upload(SentenceSettingBackup(stored))
    }

    /// 아직 본문 모양을 바꾸지 않은 설치라면 iCloud 백업을 적용한다.
    private func restoreIfUnchanged() {
        guard defaults.object(forKey: Self.userChoiceKey) as? Bool == false,
              let data = cloud.data(forKey: Self.cloudKey),
              let backup = try? JSONDecoder().decode(SentenceSettingBackup.self, from: data)
        else { return }
        let current = storedSetting() ?? .initialState
        let restored = backup.applied(to: current)
        guard restored != current, let encoded = try? JSONEncoder().encode(restored) else { return }
        defaults.set(encoded, forKey: SentenceSetting.appStorageKey)
    }

    /// 외부 변경 알림이 백업 키를 바꿨는지. 바뀐 키 목록이 없으면(계정 변경 등) 다시 읽어 본다.
    private static func changesBackup(_ notification: Notification) -> Bool {
        guard let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else { return true }
        return keys.contains(cloudKey)
    }

    /// 기기에 저장된 본문 설정. `CodableAppStorageKey` 처럼 기본 `JSONDecoder` 로 읽는다. 없거나 읽지 못하면 nil.
    private func storedSetting() -> SentenceSetting? {
        guard let data = defaults.data(forKey: SentenceSetting.appStorageKey) else { return nil }
        return try? JSONDecoder().decode(SentenceSetting.self, from: data)
    }

    private func upload(_ backup: SentenceSettingBackup) {
        guard let data = try? JSONEncoder().encode(backup) else { return }
        cloud.set(data, forKey: Self.cloudKey)
    }
}
