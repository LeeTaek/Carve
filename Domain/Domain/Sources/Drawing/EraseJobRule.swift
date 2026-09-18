//
//  EraseJobRule.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 전체 삭제 작업의 단계 (정책 §12-6 C11).
public enum EraseJobStage: Int, Comparable, Codable, CaseIterable, Sendable {
    /// ① 열린 장의 미저장분 처리.
    case openChapter = 1
    /// ② 미리 정한 ID 로 기준점 저장 + `K(기기)` 기록.
    case epoch = 2
    /// ③ 시작 시점 대상 · 무효 레코드 정리.
    case remote = 3
    /// ④ 이 기기의 로컬 데이터 삭제.
    case local = 4

    public static func < (lhs: EraseJobStage, rhs: EraseJobStage) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 비동기화 영역에 남기는 삭제 작업 기록. 단계 완료 표시는 **실제 작업을 끝낸 뒤에** 적는다.
public struct EraseJobRecord: Equatable, Sendable {
    public var jobID: String
    /// 시작할 때 미리 정한다 — 재시도해도 기준점이 늘지 않는다.
    public var epochID: String
    /// 이 작업이 속한 계정 범위. 다른 계정에서는 재개하지 않는다.
    public var accountScope: String
    /// 완료 표시가 된 마지막 단계. 표시 전에 종료되면 그 단계를 처음부터 다시 한다(멱등).
    public var completedStage: EraseJobStage?
    /// 시작 시점 대상 목록(논리 ID).
    public var targets: Set<String>

    public init(
        jobID: String,
        epochID: String,
        accountScope: String,
        completedStage: EraseJobStage? = nil,
        targets: Set<String> = []
    ) {
        self.jobID = jobID
        self.epochID = epochID
        self.accountScope = accountScope
        self.completedStage = completedStage
        self.targets = targets
    }

    public var isFinished: Bool { completedStage == .local }
}

/// 다시 시작했을 때의 처리.
public enum EraseJobResume: Equatable, Sendable {
    case resume(EraseJobStage)
    case finished
    /// 계정을 확인할 수 없다 — 서버 작업을 보류하고 기다린다.
    case waitForAccount
    /// 다른 계정 범위의 작업 — 그 계정으로 돌아왔을 때 잇는다.
    case otherAccount(String)
}

/// 단계 ② 기준점 저장의 결과.
public enum EraseEpochWriteOutcome: Equatable, Sendable {
    case stored
    /// 확실히 실패했다(저장이 일어나지 않았음을 확인).
    case failed
    /// 성공 여부가 불확실하다 — 저장은 됐는데 `K` 기록이 실패, 응답 없음, 확인 불가.
    case uncertain
}

public enum EraseEpochWriteDecision: Equatable, Sendable {
    case continueToCleanup
    /// 확실한 실패에서만 작업 기록을 지운다.
    case discardJob
    /// 같은 기준점 ID 로 조회해 있으면 `K` 에 넣고, 없으면 다시 저장한다.
    case verifyThenRetry
}

/// 단계 ④ 에서 다루는 로컬 자산.
public enum EraseLocalAsset: String, CaseIterable, Sendable {
    case draft
    case preservationRecord
    case rawCopy
    case matchIndex
    case recoveryCopy
    case quarantine
    case widget
    case jobRecord
    case epochKnowledge
    case accountScope
}

/// 전체 삭제 작업의 진행 · 재개 규칙 (정책 §12-6 C11). 저장소와 무관한 순수 규칙이다.
public enum EraseJobRule {
    /// 서버에 남아 있는 레코드 한 건.
    public struct RemoteRecord: Equatable, Sendable {
        public var id: String
        /// 그 레코드의 `K(x)`.
        public var known: Set<String>

        public init(id: String, known: Set<String>) {
            self.id = id
            self.known = known
        }
    }

    /// 앱을 다시 시작했을 때 이어서 할 단계.
    public static func resume(_ record: EraseJobRecord, currentAccount: String?) -> EraseJobResume {
        guard let account = currentAccount else { return .waitForAccount }
        guard account == record.accountScope else { return .otherAccount(record.accountScope) }
        guard let done = record.completedStage else { return .resume(.openChapter) }
        guard let next = EraseJobStage(rawValue: done.rawValue + 1) else { return .finished }
        return .resume(next)
    }

    /// 단계 ② 의 결과 처리. **부분 성공을 실패로 다루지 않는다** — 작업 기록을 지우면 이미 일어난
    /// 삭제를 재개할 근거가 사라진다.
    public static func decide(afterEpochWrite outcome: EraseEpochWriteOutcome) -> EraseEpochWriteDecision {
        switch outcome {
        case .stored: .continueToCleanup
        case .failed: .discardJob
        case .uncertain: .verifyThenRetry
        }
    }

    /// 단계 ③ 에서 서버에서 지울 대상. 시작 시점 대상과, 진행 중 도착했더라도 판정상 무효인 레코드만이다.
    /// **새 기준점을 알고 만든 레코드는 도착 시점과 상관없이 남긴다.** 대상 목록을 기준으로 하므로
    /// 여러 번 실행해도 결과가 같다(멱등).
    public static func remoteTargets(
        record: EraseJobRecord,
        present: [RemoteRecord],
        device: EraseEpochKnowledge
    ) -> Set<String> {
        var targets: Set<String> = []
        for candidate in present {
            guard !candidate.known.contains(record.epochID) else { continue }
            let isInvalid = !EraseEpochRule.isValid(recordKnown: candidate.known, device: device)
            if record.targets.contains(candidate.id) || isInvalid {
                targets.insert(candidate.id)
            }
        }
        return targets
    }

    /// 단계 ④ 에서 지우는 자산인가. 삭제 작업 기록 · `K(기기)` · 계정 범위 기록은 남긴다 —
    /// 완료를 적기 전에 종료돼도 재개할 근거가 있어야 한다.
    public static func isErasedInLocalStage(_ asset: EraseLocalAsset) -> Bool {
        switch asset {
        case .jobRecord, .epochKnowledge, .accountScope: false
        case .draft, .preservationRecord, .rawCopy, .matchIndex, .recoveryCopy, .quarantine, .widget: true
        }
    }

    /// 공유 blob 정리. 남는 복구 사본 · 격리본이 참조하는 내용 지문은 지우지 않는다.
    public static func removableBlobs(all: Set<String>, referencedByKept: Set<String>) -> Set<String> {
        all.subtracting(referencedByKept)
    }
}
