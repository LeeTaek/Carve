//
//  EraseStateStoreTesting.swift
//  DomainTest
//
//  K(기기) 와 삭제 작업 기록의 영속화 — 추가만 하고, 계정마다 따로 두고, 전체 삭제에도 남는다 (정책 §12-6 C11).
//

import Foundation
import Testing

@testable import Domain

@Suite("삭제 판정 상태 저장소")
struct EraseStateStoreTesting {

    private let accountA = AccountScope(key: "acct-a")
    private let accountB = AccountScope(key: "acct-b")

    private func withArea(_ body: (EraseStateArea, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("erase-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite"), root)
    }

    @Test("받은 기준점과 참조로만 본 기준점을 나눠 남기고, 다시 열어도 그대로다")
    func persistsReceivedAndReferencedEpochs() throws {
        try withArea { area, _ in
            let store = FileEraseStateStore(area: area)
            #expect(try store.knowledge(for: accountA) == EraseEpochKnowledge())

            try store.recordReceived("E2", knownAtCreation: ["E1"], for: accountA)
            let returned = try store.recordReferenced(["E3"], for: accountA)

            let reopened = try FileEraseStateStore(area: area).knowledge(for: accountA)
            #expect(reopened == returned)
            #expect(reopened.received == ["E2"])
            #expect(reopened.referencedOnly == ["E1", "E3"])
        }
    }

    /// 오래된 값을 들고 있던 쪽이 나중에 써도 이미 안 기준점을 잃지 않는다.
    @Test("K(기기) 는 추가만 한다 — 다른 인스턴스가 쓴 기준점을 덮어 지우지 않는다")
    func knowledgeOnlyGrows() throws {
        try withArea { area, _ in
            let first = FileEraseStateStore(area: area)
            let second = FileEraseStateStore(area: area)

            try first.recordReceived("E1", knownAtCreation: [], for: accountA)
            let merged = try second.recordReceived("E2", knownAtCreation: [], for: accountA)

            #expect(merged.received == ["E1", "E2"])
            #expect(try first.knowledge(for: accountA).received == ["E1", "E2"])
        }
    }

    /// 기준점 레코드를 뒤늦게 받으면 참조로만 알던 것이 "받은 것" 으로 올라간다 — 강등은 없다.
    @Test("참조로만 알던 기준점을 받으면 받은 것으로 바뀌고, 다시 참조로 보여도 내려가지 않는다")
    func referencedEpochIsPromotedOnReceipt() throws {
        try withArea { area, _ in
            let store = FileEraseStateStore(area: area)
            try store.recordReferenced(["E1"], for: accountA)
            try store.recordReceived("E1", knownAtCreation: [], for: accountA)
            let after = try store.recordReferenced(["E1"], for: accountA)

            #expect(after.received == ["E1"])
            #expect(after.referencedOnly.isEmpty)
        }
    }

    @Test("계정 범위마다 따로 두고 섞지 않는다")
    func keepsAccountsApart() throws {
        try withArea { area, _ in
            let store = FileEraseStateStore(area: area)
            try store.recordReceived("E1", knownAtCreation: [], for: accountA)
            try store.save(EraseJobRecord(jobID: "job-a", epochID: "E1", accountScope: accountA.key, targets: ["v-1"]))

            #expect(try store.knowledge(for: accountB) == EraseEpochKnowledge())
            #expect(try store.job(for: accountB) == nil)
        }
    }

    @Test("작업 기록을 다시 읽어도 같고, 끝나지 않은 작업만 재개 대상으로 찾는다")
    func findsUnfinishedJobsAcrossAccounts() throws {
        try withArea { area, _ in
            let store = FileEraseStateStore(area: area)
            let running = EraseJobRecord(jobID: "job-a", epochID: "E1", accountScope: accountA.key, completedStage: .epoch, targets: ["v-1"])
            let finished = EraseJobRecord(jobID: "job-b", epochID: "E2", accountScope: accountB.key, completedStage: .local)
            try store.save(running)
            try store.save(finished)

            #expect(try FileEraseStateStore(area: area).job(for: accountA) == running)
            #expect(try store.unfinishedJobs() == [running])
            // 재개 여부는 현재 계정이 정한다 — B 로 전환한 상태면 A 의 작업을 잇지 않는다(S13).
            #expect(EraseJobRule.resume(running, currentAccount: accountB.key) == .otherAccount(accountA.key))
        }
    }

    @Test("확실히 실패한 작업만 기록을 지운다")
    func discardsOnlyWhenAsked() throws {
        try withArea { area, _ in
            let store = FileEraseStateStore(area: area)
            try store.save(EraseJobRecord(jobID: "job-a", epochID: "E1", accountScope: accountA.key))

            try store.discardJob(for: accountA)

            #expect(try store.job(for: accountA) == nil)
            #expect(try store.unfinishedJobs().isEmpty)
        }
    }

    /// 단계 ④ 는 보존 영역을 지우지만 작업 기록 · K 는 남아야 재개할 수 있다.
    @Test("전체 삭제가 보존 영역을 지워도 K · 작업 기록은 남는다")
    func survivesPreservationRemoval() throws {
        try withArea { area, root in
            let store = FileEraseStateStore(area: area)
            try store.recordReceived("E1", knownAtCreation: [], for: accountA)
            try store.save(EraseJobRecord(jobID: "job-a", epochID: "E1", accountScope: accountA.key, completedStage: .remote))
            let preservation = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
            try FileManager.default.createDirectory(at: preservation.rawSnapshotsDirectory, withIntermediateDirectories: true)

            try preservation.removeAll()

            #expect(try store.knowledge(for: accountA).received == ["E1"])
            #expect(try store.job(for: accountA)?.completedStage == .remote)
        }
    }

    @Test("계정 범위 키에는 계정 식별 값이 그대로 남지 않고, 같은 값이면 같은 키다")
    func accountScopeIsHashed() {
        let identity = "_2f9c0e1d4b7a8c6e5f3a1b2c3d4e5f60"
        let scope = AccountScope.make(fromAccountIdentity: identity)

        #expect(scope == AccountScope.make(fromAccountIdentity: identity))
        #expect(scope != AccountScope.make(fromAccountIdentity: identity + "x"))
        #expect(!scope.key.contains(identity))
        #expect(scope.key.hasPrefix("acct-"))
    }
}
