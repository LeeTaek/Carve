//
//  CodableAppStorageKey.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/16/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import UIKit

import ComposableArchitecture

extension SharedKey {
    public static func appStorage<Value: Codable>(_ key: String) -> Self
    where Self == CodableAppStorageKey<Value> {
        CodableAppStorageKey(key)
    }
}

public struct CodableAppStorageKey<Value: Codable>: SharedKey {
    private let key: String
    private let store: UserDefaults
    
    public var id: AnyHashable {
        AppStorageKeyID(key: key, store: store)
    }
    
    public init(_ key: String) {
        @Dependency(\.defaultAppStorage) var store
        self.key = key
        self.store = store
    }
    
    public func load(initialValue: Value?) -> Value? {
        guard let storedValue = self.store.object(forKey: self.key) as? Data else {
            handleInitialValue(initialValue)
            return initialValue
        }
        do {
            return try JSONDecoder().decode(Value.self, from: storedValue)
        } catch {
            print("Failed to decode value for key \(self.key): \(error)")
            return initialValue
        }
    }
    
    public func save(_ value: Value, immediately: Bool) {
        guard let encodedValue = try? JSONEncoder().encode(value) else {
            print("Failed to encode value for key \(self.key)")
            return
        }
        if immediately {
            // 즉시 저장
            self.store.setValue(encodedValue, forKey: self.key)
        } else {
            // 지연 저장 처리: 디바운싱 또는 스로틀링 로직
            DispatchQueue.main.async {
                SharedAppStorageLocals.$isSetting.withValue(true) {
                    self.store.setValue(encodedValue, forKey: self.key)
                }
            }
        }
    }
    
    public func subscribe(
        initialValue: Value?,
        didSet: @Sendable @escaping (_ newValue: Value?) -> Void
    ) -> SharedSubscription {
        let previousValue = LockIsolated(initialValue)
        let userDefaultsDidChange = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: self.store,
            queue: nil
        ) { _ in
            let newValue = load(initialValue: initialValue)
            defer { previousValue.withValue { $0 = newValue } }
            guard
                !(isEqual(newValue as Any, previousValue.value as Any) ?? false)
                    || (isEqual(newValue as Any, initialValue as Any) ?? true)
            else {
                return
            }
            guard !SharedAppStorageLocals.isSetting else { return }
            didSet(newValue)
        }
        let willEnterForeground: (any NSObjectProtocol)?
        willEnterForeground = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            didSet(load(initialValue: initialValue))
        }
        return SharedSubscription {
            NotificationCenter.default.removeObserver(userDefaultsDidChange)
            if let willEnterForeground {
                NotificationCenter.default.removeObserver(willEnterForeground)
            }
        }
    }
    
    private func handleInitialValue(_ initialValue: Value?) {
        guard !SharedAppStorageLocals.isSetting else { return }
        SharedAppStorageLocals.$isSetting.withValue(true) {
            guard let initialValue else { return }
            self.save(initialValue, immediately: true)
        }
    }
    
    private func isEqual(_ lhs: Any, _ rhs: Any) -> Bool? {
        (lhs as? any Equatable)?.isEqual(other: rhs)
    }
    
    private struct AppStorageKeyID: Hashable {
        let key: String
        let store: UserDefaults
    }
}

extension Equatable {
  fileprivate func isEqual(other: Any) -> Bool {
    self == other as? Self
  }
}

private enum SharedAppStorageLocals {
  @TaskLocal static var isSetting = false
}
