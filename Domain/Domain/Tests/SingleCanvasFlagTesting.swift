//
//  SingleCanvasFlagTesting.swift
//  DomainTest
//
//  단일 Canvas 기본값(on)을 기존 사용자에게도 적용하는 설치당 1회 초기화.
//

@testable import Domain
import Foundation
import Testing

@Suite("단일 Canvas flag — 기존 저장값 1회 초기화")
struct SingleCanvasFlagTesting {
    @Test("기존 사용자가 끈 값은 한 번 지워 기본값을 따르고, 그 뒤에 다시 끈 값은 유지한다")
    func storedOffIsResetOnlyOnce() throws {
        let suite = "SingleCanvasFlagTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: SingleCanvasFlag.appStorageKey)

        SingleCanvasFlag.resetStoredValueOnce(in: defaults)

        #expect(defaults.object(forKey: SingleCanvasFlag.appStorageKey) == nil)
        #expect(defaults.bool(forKey: SingleCanvasFlag.storedValueResetKey))

        // 초기화 뒤 사용자가 다시 끄면 다음 실행에서도 꺼진 채로 둔다 — 롤백 수단이 남는다.
        defaults.set(false, forKey: SingleCanvasFlag.appStorageKey)
        SingleCanvasFlag.resetStoredValueOnce(in: defaults)

        #expect(defaults.object(forKey: SingleCanvasFlag.appStorageKey) as? Bool == false)
    }

    @Test("처음 설치한 사용자는 지울 값이 없고 초기화 기록만 남는다")
    func freshInstallOnlyRecordsReset() throws {
        let suite = "SingleCanvasFlagTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        SingleCanvasFlag.resetStoredValueOnce(in: defaults)

        #expect(defaults.object(forKey: SingleCanvasFlag.appStorageKey) == nil)
        #expect(defaults.bool(forKey: SingleCanvasFlag.storedValueResetKey))
    }
}
