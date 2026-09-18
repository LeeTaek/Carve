//
//  EraseJobRuleTesting.swift
//  DomainTest
//
//  전체 삭제 작업의 재개 — 중간에 끝나도 이미 일어난 삭제를 미완으로 남기지 않는다 (정책 §12-6 C11).
//

import Foundation
import Testing

@testable import Domain

/// 여기서 막는 회귀는 세 가지다.
/// 1) 부분 성공(기준점은 저장됐는데 `K` 기록 실패)을 실패로 보고 작업 기록을 지우는 것.
/// 2) 다른 계정으로 전환한 뒤 이전 계정의 삭제를 새 저장소에서 이어 하는 것.
/// 3) 단계 ③ 이 대상과 무관하게 전체를 지워, 새 기준점을 알고 만든 필기까지 잃는 것.
@Suite("전체 삭제 작업 재개")
struct EraseJobRuleTesting {

    private func record(
        stage: EraseJobStage? = nil,
        account: String = "A",
        targets: Set<String> = []
    ) -> EraseJobRecord {
        EraseJobRecord(
            jobID: "job-1",
            epochID: "E1",
            accountScope: account,
            completedStage: stage,
            targets: targets
        )
    }

    @Test("완료 표시가 없으면 첫 단계부터 한다")
    func resumesFromTheFirstStage() {
        #expect(EraseJobRule.resume(record(), currentAccount: "A") == .resume(.openChapter))
    }

    /// S6 — 완료 표시는 실제 작업을 끝낸 뒤에 적으므로, 표시가 없는 단계는 처음부터 다시 한다(멱등).
    @Test("완료한 단계 다음부터 잇고, 마지막까지 끝나면 완료다")
    func resumesAfterTheLastCompletedStage() {
        #expect(EraseJobRule.resume(record(stage: .openChapter), currentAccount: "A") == .resume(.epoch))
        #expect(EraseJobRule.resume(record(stage: .epoch), currentAccount: "A") == .resume(.remote))
        #expect(EraseJobRule.resume(record(stage: .remote), currentAccount: "A") == .resume(.local))
        #expect(EraseJobRule.resume(record(stage: .local), currentAccount: "A") == .finished)
        #expect(record(stage: .local).isFinished)
    }

    /// S13 — 계정 범위가 다르면 재개하지 않는다. 확인할 수 없으면 서버 작업을 보류하고 기다린다.
    @Test("다른 계정에서는 재개하지 않고, 계정을 확인할 수 없으면 기다린다")
    func doesNotResumeAcrossAccounts() {
        #expect(EraseJobRule.resume(record(account: "A"), currentAccount: "B") == .otherAccount("A"))
        #expect(EraseJobRule.resume(record(account: "A"), currentAccount: nil) == .waitForAccount)
        #expect(EraseJobRule.resume(record(account: "A"), currentAccount: "A") == .resume(.openChapter))
    }

    /// S12 — 저장은 됐는데 `K` 기록 전에 끝난 경우까지 실패로 보고 작업 기록을 지우면,
    /// 이미 일어난 삭제를 재개할 근거가 사라진다.
    @Test("기준점 저장이 불확실하면 작업 기록을 지우지 않고 확인 · 재시도한다")
    func uncertainEpochWriteKeepsTheJob() {
        #expect(EraseJobRule.decide(afterEpochWrite: .uncertain) == .verifyThenRetry)
        #expect(EraseJobRule.decide(afterEpochWrite: .failed) == .discardJob)
        #expect(EraseJobRule.decide(afterEpochWrite: .stored) == .continueToCleanup)
    }

    /// S11 — 진행 중 도착한 레코드라도 새 기준점을 알고 만든 것이면 지우지 않는다.
    @Test("단계 ③ 은 시작 시점 대상과 무효 레코드만 지운다")
    func remoteStageKeepsRecordsThatKnowTheNewEpoch() {
        var device = EraseEpochKnowledge()
        device.receive("E1")
        let job = record(stage: .epoch, targets: ["old-1", "old-2"])
        let present = [
            EraseJobRule.RemoteRecord(id: "old-1", known: []),          // 시작 시점 대상
            EraseJobRule.RemoteRecord(id: "late-invalid", known: []),   // 진행 중 도착 · 삭제를 모름
            EraseJobRule.RemoteRecord(id: "late-valid", known: ["E1"])  // 진행 중 도착 · 삭제를 알고 만듦
        ]

        let targets = EraseJobRule.remoteTargets(record: job, present: present, device: device)

        #expect(targets == ["old-1", "late-invalid"])
        // old-2 는 이미 사라졌다 — 없는 대상을 다시 만들지 않는다.
        #expect(!targets.contains("old-2"))
    }

    @Test("단계 ③ 을 다시 실행해도 결과가 같다")
    func remoteStageIsIdempotent() {
        var device = EraseEpochKnowledge()
        device.receive("E1")
        let job = record(stage: .epoch, targets: ["old-1"])
        let afterFirstRun = [EraseJobRule.RemoteRecord(id: "late-valid", known: ["E1"])]

        #expect(EraseJobRule.remoteTargets(record: job, present: afterFirstRun, device: device).isEmpty)
    }

    /// S6 — 단계 ④ 뒤에도 재개할 근거가 남아야 한다.
    @Test("단계 ④ 는 작업 기록 · K(기기) · 계정 범위를 남긴다")
    func localStageKeepsResumeEvidence() {
        let kept = EraseLocalAsset.allCases.filter { !EraseJobRule.isErasedInLocalStage($0) }

        #expect(Set(kept) == [.jobRecord, .epochKnowledge, .accountScope])
        #expect(EraseJobRule.isErasedInLocalStage(.recoveryCopy))
        #expect(EraseJobRule.isErasedInLocalStage(.quarantine))
    }

    @Test("남는 복구 사본 · 격리본이 참조하는 공유 blob 은 지우지 않는다")
    func keepsSharedBlobsThatAreStillReferenced() {
        let removable = EraseJobRule.removableBlobs(
            all: ["sha-a", "sha-b", "sha-c"],
            referencedByKept: ["sha-b"]
        )

        #expect(removable == ["sha-a", "sha-c"])
    }
}
