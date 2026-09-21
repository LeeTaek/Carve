//
//  CodableAppStorageKeyTesting.swift
//  FeatureCarveTest
//
//  Created by Claude on 9/14/26.
//

@testable import CarveFeature
import ComposableArchitecture
import Foundation
import Testing

private let sampleKey = "codableAppStorageKeyTesting"

private struct SampleSetting: Codable, Equatable, Sendable {
    var size: Int
}

/// 구독이 받은 값과 그 값을 받은 스레드
private struct Delivery: Equatable, Sendable {
    let value: SampleSetting?
    let isMainThread: Bool
}

/// `CodableAppStorageKey` 의 변경 알림 구독.
/// `UserDefaults.didChangeNotification` 은 어느 키가 바뀌어도, 값을 쓴 스레드에서 온다 — 광고 SDK · 광고 동의(UMP)가 백그라운드에서 쓴다.
@MainActor
struct CodableAppStorageKeyTesting {
    @Test("다른 키가 바뀐 알림으로는 값을 보내지 않는다")
    func ignoresOtherKeyChanges() async throws {
        let suite = "CodableAppStorageKeyTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let received = LockIsolated<[Delivery]>([])
        let subscription = subscribe(in: defaults, received: received)
        defer { subscription.cancel() }
        // 구독을 시작할 때 보내는 초기값은 이 테스트의 관심이 아니다.
        received.setValue([])

        await writeOnBackground(to: defaults) { $0.set(true, forKey: "anotherKey") }
        await drainMainQueue()

        #expect(received.value.isEmpty)
    }

    @Test("이 키가 백그라운드 스레드에서 바뀌면 새 값을 메인 스레드에서 보낸다")
    func deliversExternalChangeOnMainThread() async throws {
        let suite = "CodableAppStorageKeyTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let received = LockIsolated<[Delivery]>([])
        let subscription = subscribe(in: defaults, received: received)
        defer { subscription.cancel() }
        received.setValue([])

        let data = try JSONEncoder().encode(SampleSetting(size: 3))
        await writeOnBackground(to: defaults) { $0.set(data, forKey: sampleKey) }
        await drainMainQueue()

        #expect(received.value == [Delivery(value: SampleSetting(size: 3), isMainThread: true)])
    }

    @Test("이 키가 지워지면 메인 스레드에서 초기값으로 되돌린다")
    func removalRevertsToInitialValueOnMainThread() async throws {
        let suite = "CodableAppStorageKeyTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(SampleSetting(size: 3)), forKey: sampleKey)
        let received = LockIsolated<[Delivery]>([])
        let subscription = subscribe(in: defaults, received: received)
        defer { subscription.cancel() }
        received.setValue([])

        await writeOnBackground(to: defaults) { $0.removeObject(forKey: sampleKey) }
        await drainMainQueue()

        // nil 은 「초기값으로 되돌려라」는 뜻이다(`yieldReturningInitialValue`).
        #expect(received.value == [Delivery(value: nil, isMainThread: true)])
    }

    @Test("자기 저장으로 생긴 알림은 다시 보내지 않는다 — 늦게 온 이전 값이 방금 바꾼 값을 덮지 않게")
    func ignoresOwnSave() async throws {
        let suite = "CodableAppStorageKeyTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // 공유 값을 먼저 만든다 — 처음 불러올 때 초기값을 저장하므로 구독보다 앞서 끝내 둔다.
        let shared = withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            Shared(wrappedValue: SampleSetting(size: 1), .appStorage(sampleKey))
        }
        let received = LockIsolated<[Delivery]>([])
        let subscription = subscribe(in: defaults, received: received)
        defer { subscription.cancel() }
        received.setValue([])

        shared.withLock { $0.size = 2 }
        await drainMainQueue()

        #expect(received.value.isEmpty)
        #expect(defaults.data(forKey: sampleKey) == (try JSONEncoder().encode(SampleSetting(size: 2))))
    }

    private func subscribe(in defaults: UserDefaults, received: LockIsolated<[Delivery]>) -> SharedSubscription {
        let key = withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            CodableAppStorageKey<SampleSetting>(sampleKey)
        }
        return key.subscribe(
            context: .initialValue(SampleSetting(size: 1)),
            subscriber: SharedSubscriber { result in
                let value = try? result.get()
                received.withValue { $0.append(Delivery(value: value ?? nil, isMainThread: Thread.isMainThread)) }
            }
        )
    }

    /// 값을 백그라운드 스레드에서 쓴다 — 변경 알림도 그 스레드에서 온다.
    /// 구독은 특정 `UserDefaults` 인스턴스의 알림만 받으므로 같은 인스턴스를 넘긴다.
    private func writeOnBackground(to defaults: UserDefaults, _ write: @escaping @Sendable (UserDefaults) -> Void) async {
        let defaults = UncheckedSendable(defaults)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                write(defaults.value)
                continuation.resume()
            }
        }
    }

    /// 메인 큐에 먼저 들어간 작업(구독의 전달)이 끝나기를 기다린다.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
