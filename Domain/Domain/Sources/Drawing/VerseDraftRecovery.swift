//
//  VerseDraftRecovery.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 장을 불러올 때 이 기기에 남은 초안을 어떻게 다룰지 (정책 §12-6 구현 순서 ②).
public struct VerseDraftRecoveryPlan: Equatable, Sendable {
    /// 화면에 겹칠 초안 — 절마다 많아야 하나.
    public var shown: [VerseDraft] = []
    /// 내용이 이미 저장소에 있다(같은 내용 지문) — 지워도 잃는 것이 없다.
    public var settled: [VerseDraft] = []
    /// 보존만 하고 보이지 않는다 — 다른 근거(계정이 바뀜 · 모르던 삭제 · K 를 모름)이거나, 기준이 지금 저장소 내용과 달라졌다.
    /// 지우지 않는다. 사용자가 명시적으로 복구할 때까지 남긴다(④).
    public var kept: [VerseDraft] = []

    public init(shown: [VerseDraft] = [], settled: [VerseDraft] = [], kept: [VerseDraft] = []) {
        self.shown = shown
        self.settled = settled
        self.kept = kept
    }
}

/// 초안 복구 판정 — 순수 함수라 표로 시험한다.
///
/// - **지금 세션의 초안은 늘 보인다.** 사용자가 이 세션에서 방금 쓴 내용이다. 다시 읽기(레이아웃 변경 · 복원)로 저장소 내용을 새로
///   읽어도 그 위에 다시 겹친다 — 초안 전용 세션에서는 저장소에 없는 필기가 초안에만 있다.
/// - **다른 세션의 초안은 이어 써도 되는 것만 보인다.** 근거(계정 · K)가 지금 환경에서도 유효하고, 그 초안의 기준이 지금 저장소 내용과
///   같을 때다. 기준이 달라졌으면 그 사이 다른 내용이 들어온 것이다 — 겹치면 그 내용을 본 척 가린다. 보존만 하고 보이지 않는다.
/// - **보이는 것도 자동으로 저장소에 쓰지 않는다.** 겹쳐 보일 뿐이고, 사용자가 그 절을 다시 편집해야 그 세션의 초안 · 저장이 된다.
public enum VerseDraftRecoveryRule {
    /// - Parameters:
    ///   - drafts: 지금 계정 근거 묶음에 있는 이 장의 초안.
    ///   - storeContent: 절마다 저장소의 지금 대표 내용 지문. 없는 절은 빈 절이다(행 없음 · 비움).
    ///   - environment: 지금 편집 환경.
    ///   - sessionID: 지금 편집 세션. 없으면 모든 초안이 다른 세션의 것이다.
    public static func plan(
        drafts: [VerseDraft],
        storeContent: [Int: String],
        environment: DrawingEditEnvironment,
        sessionID: String?
    ) -> VerseDraftRecoveryPlan {
        var plan = VerseDraftRecoveryPlan()
        let byVerse = Dictionary(grouping: drafts, by: \.key.verse)
        for verse in byVerse.keys.sorted() {
            let list = byVerse[verse] ?? []
            let own = list.filter { $0.key.sessionID == sessionID }.max { $0.revision < $1.revision }
            var candidates: [VerseDraft] = []
            for draft in list where draft.key.sessionID != sessionID {
                if draft.contentFingerprint == storeContent[verse] {
                    plan.settled.append(draft)
                } else if canContinue(draft, storeFingerprint: storeContent[verse], environment: environment) {
                    candidates.append(draft)
                } else {
                    plan.kept.append(draft)
                }
            }
            // 이어 쓸 수 있는 것이 여럿이면 가장 늦게 쓴 것을 보인다. 나머지는 지우지 않고 남긴다 — 사용자가 보지 않은 것은 이어받지 않는다.
            let latest = candidates.max { ($0.savedAt, $0.revision, $0.key.sessionID) < ($1.savedAt, $1.revision, $1.key.sessionID) }
            if let own {
                plan.shown.append(own)
                plan.kept.append(contentsOf: candidates)
            } else if let latest {
                plan.shown.append(latest)
                plan.kept.append(contentsOf: candidates.filter { $0 != latest })
            }
        }
        return plan
    }

    /// 다른 세션의 초안을 지금 환경에서 이어 써도 되는가.
    static func canContinue(_ draft: VerseDraft, storeFingerprint: String?, environment: DrawingEditEnvironment) -> Bool {
        // 기준이 지금 저장소 내용과 같아야 한다 — 달라졌으면 그 사이 들어온 내용을 가린다.
        guard draft.baseFingerprint == storeFingerprint else { return false }
        // K 를 읽지 못했으면 그 초안이 알려진 삭제 전에 쓴 것인지 알 수 없다.
        guard let device = environment.knowledge else { return false }
        if draft.knownEpochs == nil, !device.all.isEmpty { return false }
        let context = VerseEditContext(
            contextID: draft.key.sessionID, verse: draft.key.verse, base: draft.base, knownEpochs: draft.knownEpochs, account: draft.account
        )
        switch VerseEditContextRule.validity(
            of: context, accountState: environment.accountState, deviceKnowledge: device, loadedDataOwner: draft.storeOwnership
        ) {
        case .accountChanged, .eraseLearned:
            return false
        case .valid, .awaitingAccountConfirmation, .preserveOnly:
            return true
        }
    }
}
