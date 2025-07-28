//
//  CodableAppStorageKey.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/16/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import UIKit

import ComposableArchitecture

extension SharedKey {
    public static func appStorage<Value: Codable>(_ key: String) -> Self
    where Self == CodableAppStorageKey<Value> {
        CodableAppStorageKey(key)
    }
}

public struct CodableAppStorageKey<Value: Codable>: SharedKey {
    @Dependency(\.defaultAppStorage) var store
    private let key: String

    public var id: AnyHashable {
        AppStorageKeyID(key: key, store: store)
    }
    
    public init(_ key: String) {
        self.key = key
    }
    
    public func load(context: LoadContext<Value>,
                     continuation: LoadContinuation<Value>) {
        var hasResumed = false // 중복 호출 방지 플래그

        if let storedData = store.data(forKey: key) {
            do {
                let decodedValue = try JSONDecoder().decode(Value.self, from: storedData)
                continuation.resume(returning: decodedValue)
                hasResumed = true
            } catch {
                Log.debug("CodableAppStorageKey_load_error \(key)", error )
                handleInitialValue(context.initialValue,
                                   saveContext: .didSet,
                                   continuation: continuation,
                                   hasResumed: &hasResumed)
            }
        } else {
            Log.debug("CodableAppStorageKey_load_error ", key )
            handleInitialValue(context.initialValue,
                               saveContext: .didSet,
                               continuation: continuation,
                               hasResumed: &hasResumed)
            if !hasResumed {
                continuation.resume(returning: context.initialValue!)
                hasResumed = true
            }
        }
    }
    
    
    public func save(_ value: Value,
                     context: SaveContext,
                     continuation: SaveContinuation) {
        do {
            let encodedValue = try JSONEncoder().encode(value)
            self.store.set(encodedValue, forKey: self.key)
            continuation.resume()
        } catch {
            // 에러 발생 시 continuation에 에러 전달
            continuation.resume(throwing: error)
        }
    }
    
    public func subscribe(context: LoadContext<Value>,
                          subscriber: SharedSubscriber<Value>) -> SharedSubscription {
        if let storedData = store.data(forKey: key) {
             do {
                 let decodedValue = try JSONDecoder().decode(Value.self, from: storedData)
                 subscriber.yield(decodedValue)
             } catch {
                 Log.debug("CodableAppStorageKey_subscribe_error \(self.key)", error)
             }
         } else if let initialValue = context.initialValue {
             // 저장된 데이터가 없는 경우 초기값 전달
             subscriber.yield(initialValue)
         }

         let userDefaultsDidChange = NotificationCenter.default.addObserver(
             forName: UserDefaults.didChangeNotification,
             object: self.store,
             queue: nil
         ) { _ in
             guard let storedData = self.store.data(forKey: self.key) else {
                 subscriber.yield(context.initialValue!)
                 return
             }
             do {
                 let decodedValue = try JSONDecoder().decode(Value.self, from: storedData)
                 subscriber.yield(decodedValue)
             } catch {
                 Log.debug("CodableAppStorageKey_subscribe_error \(self.key)", error)
                 subscriber.yield(context.initialValue!)
             }
         }

        return SharedSubscription {
            NotificationCenter.default.removeObserver(userDefaultsDidChange)
        }
    }
    
    private func handleInitialValue(
        _ initialValue: Value?,
        saveContext: SaveContext,
        continuation: LoadContinuation<Value>,
        hasResumed: inout Bool
    ) {
        guard let initialValue = initialValue else {
            // 값이 없는 경우
            continuation.resumeReturningInitialValue()
            return
        }
        do {
            // 초기값을 저장
            let encodedValue = try JSONEncoder().encode(initialValue)
            store.set(encodedValue, forKey: self.key)
            if !hasResumed {
                continuation.resume(returning: initialValue)
                hasResumed = true
            }
        } catch {
            if !hasResumed {
                continuation.resume(throwing: error)
                hasResumed = true
            }
        }
    }
    
    private struct AppStorageKeyID: Hashable {
        let key: String
        let store: UserDefaults
    }
}
