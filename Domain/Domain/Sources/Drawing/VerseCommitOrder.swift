//
//  VerseCommitOrder.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 확정 한 번의 결과 (정책 §12-5 C2 · §12-6 C11).
public enum VerseCommitOutcome: Equatable, Sendable {
    /// 복구 사본 · 동기화 저장소 · 초안 정리까지 끝났다.
    case committed
    /// **복구 사본을 저장하지 못했다.** 확정하지 않는다 — 동기화 저장소에 넣지 않았고 초안도 그대로다.
    case recoveryCopyFailed
    /// 복구 사본은 남았고 동기화 저장소 쓰기가 실패했다. 초안을 유지하고 같은 사본으로 다시 시도한다.
    case syncedStoreFailed
    /// 버전은 들어갔는데 초안 정리가 실패했다. 초안이 남아 다음 시작에서 정리한다 — 유실은 아니다.
    case draftCompletionFailed
}

public struct VerseCommitResult: Equatable, Sendable {
    public let outcome: VerseCommitOutcome
    /// 안내 · 로그용 설명. 원본 오류는 호출부에서 따로 다룬다.
    public let failureDescription: String?

    public init(outcome: VerseCommitOutcome, failureDescription: String? = nil) {
        self.outcome = outcome
        self.failureDescription = failureDescription
    }

    /// 초안을 그대로 두어야 하는가. 확정이 끝나지 않았으면 초안이 마지막 방어선이다.
    public var keepsDraft: Bool { outcome != .committed }
}

/// 확정 순서 (정책 §12-5 C2): **복구 사본 저장 → 동기화 저장소에 버전 추가 → 초안 revision 완료.**
///
/// 순서를 규칙으로 고정하는 이유는 리뷰가 지적한 반례 때문이다. 동기화 저장소에 먼저 넣으면,
/// 다른 기기가 만든 삭제 기준점이 그 사이에 도착했을 때 되살릴 사본 없이 무효가 될 수 있다.
/// 복구 사본이 **먼저** 있어야 그 필기를 격리 · 선택으로 되살린다(§12-6 C11 S3 · S10).
///
/// 재시도는 같은 `RecoveryCopyEntry` 로 부른다. 사본 저장은 지문 · `entryID` 기준이라 여러 번 불러도 하나다.
public enum VerseCommitOrder {
    public static func commit(
        entry: RecoveryCopyEntry,
        blob: Data,
        saveRecoveryCopy: (RecoveryCopyEntry, Data) throws -> Void,
        insertIntoSyncedStore: (RecoveryCopyEntry) throws -> Void,
        completeDraft: () throws -> Void
    ) -> VerseCommitResult {
        do {
            try saveRecoveryCopy(entry, blob)
        } catch {
            // 공간 부족도 여기로 온다. 기존 사본을 지워 자리를 만들지 않고 확정을 멈춘다.
            return VerseCommitResult(outcome: .recoveryCopyFailed, failureDescription: String(describing: error))
        }
        do {
            try insertIntoSyncedStore(entry)
        } catch {
            return VerseCommitResult(outcome: .syncedStoreFailed, failureDescription: String(describing: error))
        }
        do {
            try completeDraft()
        } catch {
            return VerseCommitResult(outcome: .draftCompletionFailed, failureDescription: String(describing: error))
        }
        return VerseCommitResult(outcome: .committed)
    }
}
