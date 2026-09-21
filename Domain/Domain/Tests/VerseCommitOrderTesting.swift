//
//  VerseCommitOrderTesting.swift
//  DomainTest
//
//  확정 순서 — 복구 사본을 먼저 남기고, 저장하지 못하면 확정하지 않는다 (정책 §12-5 C2 · §12-6 C11).
//

import Foundation
import Testing

@testable import Domain

/// 동기화 저장소에 먼저 넣으면, 그 사이 도착한 삭제 기준점 때문에 되살릴 사본 없이 무효가 될 수 있다(S3 · S10).
/// 이 순서를 뒤집는 회귀를 여기서 막는다.
@Suite("절 확정 순서")
struct VerseCommitOrderTesting {

    private struct SaveFailure: Error {}
    private struct SyncedFailure: Error {}
    private struct DraftFailure: Error {}

    private func entry() -> RecoveryCopyEntry {
        RecoveryCopyEntry(
            kind: .version,
            accountScope: "account-A",
            verseKey: "NKRV/1-01Genesis.txt/1/1",
            contentFingerprint: "vc1-aaa",
            drawingVersion: 3,
            knownEpochs: ["E1"],
            deviceID: "device-1"
        )
    }

    @Test("복구 사본 → 동기화 저장소 → 초안 정리 순서로 진행한다")
    func followsTheCommitOrder() {
        var steps: [String] = []

        let result = VerseCommitOrder.commit(
            entry: entry(),
            blob: Data("획".utf8),
            saveRecoveryCopy: { _, _ in steps.append("recovery") },
            insertIntoSyncedStore: { _ in steps.append("synced") },
            completeDraft: { steps.append("draft") }
        )

        #expect(steps == ["recovery", "synced", "draft"])
        #expect(result == VerseCommitResult(outcome: .committed))
        #expect(!result.keepsDraft)
    }

    /// 공간 부족도 이 경로다 — 기존 사본을 지워 자리를 만들지 않고 저장 실패로 둔다.
    @Test("복구 사본을 저장하지 못하면 동기화 저장소에 넣지 않고 초안을 남긴다")
    func doesNotCommitWhenTheRecoveryCopyFails() {
        var steps: [String] = []

        let result = VerseCommitOrder.commit(
            entry: entry(),
            blob: Data("획".utf8),
            saveRecoveryCopy: { _, _ in throw SaveFailure() },
            insertIntoSyncedStore: { _ in steps.append("synced") },
            completeDraft: { steps.append("draft") }
        )

        #expect(steps.isEmpty)
        #expect(result.outcome == .recoveryCopyFailed)
        #expect(result.keepsDraft)
        #expect(result.failureDescription != nil)
    }

    @Test("동기화 저장소 쓰기가 실패해도 복구 사본과 초안은 남는다")
    func keepsRecoveryCopyWhenTheSyncedStoreFails() {
        var saved: [RecoveryCopyEntry] = []
        var draftCompleted = false

        let result = VerseCommitOrder.commit(
            entry: entry(),
            blob: Data("획".utf8),
            saveRecoveryCopy: { entry, _ in saved.append(entry) },
            insertIntoSyncedStore: { _ in throw SyncedFailure() },
            completeDraft: { draftCompleted = true }
        )

        #expect(saved.count == 1)
        #expect(!draftCompleted)
        #expect(result.outcome == .syncedStoreFailed)
        #expect(result.keepsDraft)
    }

    @Test("초안 정리가 실패해도 버전은 남는다")
    func draftCleanupFailureIsNotDataLoss() {
        let result = VerseCommitOrder.commit(
            entry: entry(),
            blob: Data("획".utf8),
            saveRecoveryCopy: { _, _ in },
            insertIntoSyncedStore: { _ in },
            completeDraft: { throw DraftFailure() }
        )

        #expect(result.outcome == .draftCompletionFailed)
        #expect(result.keepsDraft)
    }

    /// 같은 초안을 다시 확정해도 사본이 쌓이지 않아야 한다 — 재시도는 같은 항목으로 부른다.
    @Test("같은 항목으로 재시도하면 복구 사본은 하나다")
    func retryingWithTheSameEntryKeepsOneCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("commit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecoveryCopyStore(root: root)
        let request = entry()
        var failNextInsert = true

        let first = VerseCommitOrder.commit(
            entry: request,
            blob: Data("획".utf8),
            saveRecoveryCopy: store.save,
            insertIntoSyncedStore: { _ in
                if failNextInsert {
                    failNextInsert = false
                    throw SyncedFailure()
                }
            },
            completeDraft: { }
        )
        let second = VerseCommitOrder.commit(
            entry: request,
            blob: Data("획".utf8),
            saveRecoveryCopy: store.save,
            insertIntoSyncedStore: { _ in },
            completeDraft: { }
        )

        #expect(first.outcome == .syncedStoreFailed)
        #expect(second.outcome == .committed)
        #expect(try store.entries(accountScope: "account-A").count == 1)
    }
}
