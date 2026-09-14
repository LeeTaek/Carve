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

/// AppStorage(UserDefaults) 기반 Codable 타입을 @Shared로 사용하기 위한 Extension
extension SharedKey {
    public static func appStorage<Value: Codable>(_ key: String) -> Self
    where Self == CodableAppStorageKey<Value> {
        CodableAppStorageKey(key)
    }
}

/// Codable 타입을 AppStorage(UserDefaults)에 저장하고, shared 상태로 연동하기 위한 Key
/// UserDefaults에 저장할때 사용하는 키를 주입받고, 해당 키로 Encoding, Decoding하여 저장/반환
/// UserDefaults.didChangeNotification를 구독하여 값 변경시 새로운 값 전파
public struct CodableAppStorageKey<Value: Codable>: SharedKey {
    @Dependency(\.defaultAppStorage) var store
    private let key: String

    public var id: AnyHashable {
        AppStorageKeyID(key: key, store: store)
    }

    public init(_ key: String) {
        self.key = key
    }

    ///  UserDefaults에서 로드, 없거나 디코딩 실패시 초기값 저장/반환
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

    /// 전달된 값 JSON 으로 인코딩해서 UserDefaults에 저장
    public func save(_ value: Value,
                     context: SaveContext,
                     continuation: SaveContinuation) {
        do {
            let encodedValue = try JSONEncoder().encode(value)
            // 저장으로 생긴 변경 알림은 `set` 안에서 같은 스레드로 곧바로 온다. 구독이 그 알림을 다시 보내지 않게 표시한다.
            CodableAppStorageLocals.$isSaving.withValue(true) {
                self.store.set(encodedValue, forKey: self.key)
            }
            continuation.resume()
        } catch {
            // 에러 발생 시 continuation에 에러 전달
            continuation.resume(throwing: error)
        }
    }

    /// UserDefaults.didChangeNotification을 구독하여 이 키의 값이 바뀔 때만 메인 스레드에서 새 값을 전파
    ///
    /// - 이 알림은 **어느 키가 바뀌어도**, **값을 쓴 스레드에서** 온다. 광고 SDK · 광고 동의(UMP)처럼 백그라운드에서
    ///   UserDefaults 를 쓰는 코드가 있어, 받은 자리에서 그대로 전달하면 화면 상태가 메인이 아닌 스레드에서 바뀌어 크래시가 난다.
    ///   그래서 이 키의 저장 데이터가 실제로 달라졌을 때만, 메인 스레드로 넘겨 전달한다.
    /// - 자기 저장으로 생긴 알림은 무시한다 — 늦게 도착한 이전 값이 방금 바꾼 값을 덮지 않게 한다.
    /// - Sharing 의 `AppStorageKey` 가 알림 경로에서 하는 처리(이전 값 비교 · `isSetting` · `DispatchQueue.main.async`)와 같다.
    public func subscribe(context: LoadContext<Value>,
                          subscriber: SharedSubscriber<Value>) -> SharedSubscription {
        let initialData = store.data(forKey: key)
        if let initialData {
             do {
                 let decodedValue = try JSONDecoder().decode(Value.self, from: initialData)
                 subscriber.yield(decodedValue)
             } catch {
                 Log.debug("CodableAppStorageKey_subscribe_error \(self.key)", error)
             }
         } else if let initialValue = context.initialValue {
             // 저장된 데이터가 없는 경우 초기값 전달
             subscriber.yield(initialValue)
         }

        let lastData = LockIsolated(initialData)
        let key = self.key
        let userDefaultsDidChange = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: self.store,
            queue: nil
        ) { _ in
            let storedData = self.store.data(forKey: key)
            let isChanged = lastData.withValue { lastData in
                defer { lastData = storedData }
                return lastData != storedData
            }
            guard isChanged, !CodableAppStorageLocals.isSaving else { return }

            DispatchQueue.main.async {
                // 없거나 디코딩에 실패하면 nil — 초기값으로 되돌린다.
                subscriber.yield(with: .success(Self.decode(storedData, key: key)))
            }
        }

        return SharedSubscription {
            NotificationCenter.default.removeObserver(userDefaultsDidChange)
        }
    }

    /// 저장 데이터를 디코딩한다. 데이터가 없거나 디코딩에 실패하면 nil.
    private static func decode(_ data: Data?, key: String) -> Value? {
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            Log.debug("CodableAppStorageKey_subscribe_error \(key)", error)
            return nil
        }
    }

    /// 초기값이 존재할때 UserDefaults에 저장, continuation에서 처리
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

    /// SharedKey 식별을 위해 사용되는 ID
    private struct AppStorageKeyID: Hashable {
        let key: String
        let store: UserDefaults
    }
}

/// `CodableAppStorageKey` 가 저장하는 중인지. `save` 가 받는 자기 변경 알림을 구독에서 거르는 데 쓴다.
/// 제네릭 타입에는 static 저장 프로퍼티를 둘 수 없어 따로 둔다.
private enum CodableAppStorageLocals {
    @TaskLocal static var isSaving = false
}
