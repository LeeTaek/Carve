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

extension PersistenceReaderKey {
    public static func appStorage<Value: Codable>(_ key: String) -> Self
    where Self == CodableAppStorageKey<Value> {
        CodableAppStorageKey(key)
    }
}

public struct CodableAppStorageKey<Value: Codable>: PersistenceKey {
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
            guard !SharedAppStorageLocals.isSetting else {
                return initialValue
            }
            SharedAppStorageLocals.$isSetting.withValue(true) {
                guard let initialValue else { return }
                self.save(initialValue)
            }
            return initialValue
        }
        let value = try? JSONDecoder().decode(Value.self, from: storedValue)
        return value
    }
    
    public func save(_ value: Value) {
        guard let newValue = try? JSONEncoder().encode(value) else { return }
        SharedAppStorageLocals.$isSetting.withValue(true) {
            self.store.setValue(newValue, forKey: self.key)
        }
    }
    
    public func subscribe(
        initialValue: Value?,
        didSet: @Sendable @escaping (_ newValue: Value?) -> Void
    ) -> Shared<Value>.Subscription {
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
        return Shared.Subscription {
            NotificationCenter.default.removeObserver(userDefaultsDidChange)
            if let willEnterForeground {
                NotificationCenter.default.removeObserver(willEnterForeground)
            }
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
