//
//  CodableAppStorageKey.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/16/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

extension PersistenceReaderKey {
    public static func appStorage<Value: Codable>(_ key: String) -> Self
    where Self == CodableAppStorageKey<Value, AppStorageKey<Data?>> {
        CodableAppStorageKey(key)
    }
    
    public static func appStorage<Value: Codable>(
        _ keyPath: ReferenceWritableKeyPath<UserDefaults, Data?>
    ) -> Self where Self == CodableAppStorageKey<Value, AppStorageKeyPathKey<Data?>> {
        CodableAppStorageKey(keyPath)
    }
}

public struct CodableAppStorageKey<Value: Codable, UnderlyingKey: PersistenceKey>: PersistenceKey
where UnderlyingKey.Value == Data? {
    private let appStorageKey: UnderlyingKey
    
    public var id: UnderlyingKey.ID {
        appStorageKey.id
    }
    
    public init(_ key: String)
    where UnderlyingKey == AppStorageKey<Data?> {
        self.appStorageKey = AppStorageKey(key)
    }
    
    public init(_ keyPath: ReferenceWritableKeyPath<UserDefaults, UnderlyingKey.Value>)
    where UnderlyingKey == AppStorageKeyPathKey<Data?> {
        self.appStorageKey = AppStorageKeyPathKey(keyPath)
    }
    
    public func load(initialValue: Value?) -> Value? {
        let initialValue = initialValue.flatMap { try? JSONEncoder().encode($0) }
        let value = self.appStorageKey.load(initialValue: initialValue)
        return value?.flatMap { try? JSONDecoder().decode(Value.self, from: $0) }

    }
    
    public func save(_ value: Value) {
        let value = try? JSONEncoder().encode(value)
        self.appStorageKey.save(value)
    }
    
    public func subscribe(
        initialValue: Value?,
        didSet: @Sendable @escaping (_ newValue: Value?) -> Void
    ) -> Shared<Value>.Subscription {
        let initialValue = initialValue.flatMap { try? JSONEncoder().encode($0) }
        let subscription = self.appStorageKey.subscribe(initialValue: initialValue) { newValue in
            let newValue = newValue?.flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
            didSet(newValue)
        }
        return Shared.Subscription(subscription.cancel)
    }
}
