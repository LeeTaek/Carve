//
//  DrawingQuarantineTesting.swift
//  DomainTest
//
//  격리본과 설치 ID — 무효가 된 편집 세션의 미저장분을 만들 당시의 근거로 남긴다 (정책 §12-6 구현 순서 ①).
//

import Foundation
import Testing

@testable import Domain

@Suite("격리본 · 설치 ID")
struct DrawingQuarantineTesting {

    private let chapter = BibleChapter(title: .genesis, chapter: 1)

    private func withRoot(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quarantine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    private func environment(_ state: AccountScopeState, knowledge: Set<String> = []) -> DrawingEditEnvironment {
        var known = EraseEpochKnowledge()
        knowledge.forEach { known.receive($0) }
        let token: AccountServerWorkToken? = state.scopeForServerWork.map { AccountServerWorkToken(scope: $0, generation: 1) }
        return DrawingEditEnvironment(accountState: state, serverWork: token, knowledge: known, generation: 1)
    }

    @Test("격리본은 무효가 된 세션의 계정 범위 · K 를 들고, 내용을 그대로 되돌려 준다")
    func quarantineKeepsSessionBasis() async throws {
        try await withRoot { root in
            let store = FileRecoveryCopyStore(root: root)
            let quarantine = FileDrawingQuarantine(store: store, deviceID: "device-1")
            let account = AccountScope(key: "acct-a")
            let item = DrawingQuarantineItem(chapter: chapter, verse: 3, revision: 1, lineData: Data("획".utf8), drawingVersion: 3,
                                             layoutMetadataData: Data("meta".utf8))

            try await quarantine.quarantine([item], environment: environment(.confirmed(account), knowledge: ["E1"]), batchID: "session-1")

            let entries = try store.entries(accountScope: account.key)
            #expect(entries.count == 1)
            let entry = try #require(entries.first)
            #expect(entry.classification == .quarantined)
            #expect(entry.knownEpochs == ["E1"])
            #expect(entry.verseKey == "NKRV/\(chapter.title.rawValue)/1/3")
            #expect(entry.deviceID == "device-1")
            let content = try JSONDecoder().decode(QuarantinedVerseContent.self, from: store.blob(for: entry))
            #expect(content == QuarantinedVerseContent(lineData: Data("획".utf8), drawingVersion: 3, layoutMetadataData: Data("meta".utf8)))
        }
    }

    /// 계정을 확인하지 못한 세션의 미저장분을 어느 계정에 붙이면 다른 계정의 것으로 보일 수 있다.
    @Test("확인 전 · 로그인 안 함 세션의 격리본은 계정이 아니라 별도 묶음에 둔다")
    func unverifiedSessionsGoToSeparateBuckets() async throws {
        try await withRoot { root in
            let store = FileRecoveryCopyStore(root: root)
            let quarantine = FileDrawingQuarantine(store: store, deviceID: "device-1")
            let item = DrawingQuarantineItem(chapter: chapter, verse: 1, revision: 1, lineData: Data("a".utf8), drawingVersion: 3, layoutMetadataData: nil)

            try await quarantine.quarantine([item], environment: environment(.unconfirmed(lastConfirmed: AccountScope(key: "acct-a"))), batchID: "session-1")
            try await quarantine.quarantine([item], environment: environment(.noAccount), batchID: "session-2")

            #expect(try store.entries(accountScope: AccountScope.unverified.key).count == 1)
            #expect(try store.entries(accountScope: AccountScope.localOnly.key).count == 1)
            #expect(try store.entries(accountScope: "acct-a").isEmpty)
        }
    }

    @Test("절을 비운 편집도 격리하고, 같은 내용은 blob 을 공유한다")
    func clearedVerseAndSharedContent() async throws {
        try await withRoot { root in
            let store = FileRecoveryCopyStore(root: root)
            let quarantine = FileDrawingQuarantine(store: store, deviceID: "device-1")
            let account = AccountScope(key: "acct-a")
            let same = Data("같은 획".utf8)
            let items = [
                DrawingQuarantineItem(chapter: chapter, verse: 1, revision: 1, lineData: same, drawingVersion: 3, layoutMetadataData: nil),
                DrawingQuarantineItem(chapter: chapter, verse: 2, revision: 1, lineData: same, drawingVersion: 3, layoutMetadataData: nil),
                DrawingQuarantineItem(chapter: chapter, verse: 3, revision: 1, lineData: nil, drawingVersion: nil, layoutMetadataData: nil)
            ]

            try await quarantine.quarantine(items, environment: environment(.confirmed(account)), batchID: "session-1")

            let entries = try store.entries(accountScope: account.key)
            #expect(entries.count == 3)
            let usage = try store.usage(accountScope: account.key)
            #expect(usage.quarantinedEntries == 3)
            // 1 · 2절은 내용이 같아 blob 하나를 공유한다.
            #expect(Set(entries.map(\.contentFingerprint)).count == 2)
        }
    }

    /// 여러 절 중 일부만 저장하고 실패한 뒤 다시 하면, 매번 새 ID 로 사본이 늘었다(6차 리뷰).
    @Test("같은 세션 · 절 · revision 을 다시 격리해도 격리본이 늘지 않고, revision 이 다르면 따로 남는다")
    func quarantineIsIdempotent() async throws {
        try await withRoot { root in
            let store = FileRecoveryCopyStore(root: root)
            let quarantine = FileDrawingQuarantine(store: store, deviceID: "device-1")
            let account = AccountScope(key: "acct-a")
            let first = DrawingQuarantineItem(chapter: chapter, verse: 1, revision: 1, lineData: Data("a".utf8), drawingVersion: 3, layoutMetadataData: nil)
            let later = DrawingQuarantineItem(chapter: chapter, verse: 1, revision: 2, lineData: Data("b".utf8), drawingVersion: 3, layoutMetadataData: nil)

            try await quarantine.quarantine([first], environment: environment(.confirmed(account)), batchID: "session-1")
            try await quarantine.quarantine([first], environment: environment(.confirmed(account)), batchID: "session-1")
            #expect(try store.entries(accountScope: account.key).count == 1)

            try await quarantine.quarantine([later], environment: environment(.confirmed(account)), batchID: "session-1")
            #expect(try store.entries(accountScope: account.key).count == 2)
        }
    }

    @Test("주입하지 않은 격리는 실패로 알린다 — 호출부가 화면을 정리하지 않게")
    func unconfiguredQuarantineFails() async {
        await #expect(throws: UnavailableDrawingQuarantine.NotConfigured.self) {
            try await UnavailableDrawingQuarantine().quarantine([], environment: .unknown, batchID: "session-1")
        }
    }

    // MARK: - 설치 ID

    @Test("설치 ID 는 한 번 만들고 계속 같다")
    func installationIDIsStable() async throws {
        try await withRoot { root in
            let url = root.appendingPathComponent("installation-id")

            let first = try InstallationID.load(at: url)
            let second = try InstallationID.load(at: url)

            #expect(first == second)
            #expect(!first.isEmpty)
        }
    }

    /// 바뀌면 같은 원본의 논리 ID 가 달라진다 — 읽지 못한다고 새로 만들어 덮지 않는다.
    @Test("설치 ID 파일이 비어 있으면 새로 만들지 않고 던진다")
    func unreadableInstallationIDThrows() async throws {
        try await withRoot { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("installation-id")
            try Data().write(to: url)

            #expect(throws: (any Error).self) { try InstallationID.load(at: url) }
            #expect(try Data(contentsOf: url).isEmpty)
        }
    }
}
