//
//  VerseDraftRecovery.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 장을 불러올 때 이 기기에 남은 초안을 어떻게 다룰지 (정책 §12-6 구현 순서 ②).
///
/// **어느 칸도 초안을 지우라는 뜻이 아니다.** ② 는 초안을 지우지 않는다 — 로컬 저장(`BibleDrawing`)은 보존이 아니다(ACC-1 F29).
/// 정리는 ③ 의 확정(복구 사본 → 버전 로컬 커밋 → 그 revision 정리)만 한다.
public struct VerseDraftRecoveryPlan: Equatable, Sendable {
    /// 화면에 겹칠 초안 — 절마다 많아야 하나.
    public var shown: [VerseDraft] = []
    /// `shown` 가운데 **보이기만** 하는 다른 세션의 초안 — 근거가 지금 환경에서 유효하지 않거나(보존만 · 확인 대기), 지금 세션에 소유 근거가
    /// 없거나, 저장소로 보낸 행이 사라졌다. 지금 세션으로 이어 쓰지 않는다: 그 절의 이후 편집은 이 초안의 출처(`VerseDraftProvenance`)를
    /// 잇고 저장소에 쓰지 않는다.
    public var showOnly: Set<VerseDraftKey> = []
    /// 역할이 끝났다 — 내용이 이미 저장소에 있다(그 절의 대표 내용이나, 보낸 행의 지금 내용과 같다), 또는 지금 세션이 그 revision 을 저장소에
    /// 넣었다. 겹치지 않는다. 지우지 않는다 — 전송 전에 계정이 바뀌면 이것이 유일한 사본이다.
    public var settled: [VerseDraft] = []
    /// 보존만 하고 보이지 않는다 — 다른 근거(계정이 바뀜 · 모르던 삭제 · K 를 모름)이거나, 기준이 지금 저장소 내용과 달라졌거나, 보낸 행이
    /// 그 뒤로 바뀌었다(지우기 · 복원 · 다른 기기). 사용자가 명시적으로 복구할 때까지 남긴다(④).
    public var kept: [VerseDraft] = []
    /// `kept` 가운데 **저장 완료가 불확실한** 초안 — 저장소로 보내던 중(`sending`)에 앱이 끝났는데 그 행이 그 뒤로 바뀌어, 들어갔는지 가릴 수
    /// 없다. 확정된 사실로 되살리지 않고 보존하며, 복구 화면(④)에서 따로 알린다.
    public var uncertain: [VerseDraft] = []
    /// `kept` 가운데 **그 행이 내가 앞서 넣은 내용으로 돌아온** 초안 — 그 뒤 편집이 저장소에 닿지 않았다(전송 전 계정 전환 · 종료, F29).
    ///
    /// **자동으로 겹치지 않는다**(사용자 결정 2026-09-21, 11차 리뷰 P0-1). 같은 입력이 "다른 기기가 일부러 옛 내용으로 되돌렸다" 와
    /// 구분되지 않기 때문이다. ④ 의 복구 화면이 **지금 필기와 나란히 보여 주고**, 사용자가 고르면 새 버전으로 남긴다 — 지금 필기도 지우지 않는다.
    public var recoverable: [VerseDraft] = []

    public init(
        shown: [VerseDraft] = [], showOnly: Set<VerseDraftKey> = [], settled: [VerseDraft] = [], kept: [VerseDraft] = [],
        uncertain: [VerseDraft] = [], recoverable: [VerseDraft] = []
    ) {
        self.shown = shown
        self.showOnly = showOnly
        self.settled = settled
        self.kept = kept
        self.uncertain = uncertain
        self.recoverable = recoverable
    }
}

/// 저장소의 한 행 — 초안이 그 행으로 보낸 내용이 아직 있는지 가린다.
public struct VerseDraftStoreRow: Equatable, Sendable {
    /// 그 행의 내용 지문. 비운 행이면 nil.
    public var contentFingerprint: String?

    public init(contentFingerprint: String?) {
        self.contentFingerprint = contentFingerprint
    }
}

/// 한 장의 저장소 내용 — 초안 판정(`VerseDraftRecoveryRule.plan`)이 쓰는 입력을 한 번에 만든다.
///
/// 편집 화면과 복구 화면(④)이 **같은 규칙**으로 대표 행을 고르고 같은 지문을 견주게 하는 자리다. 따로 만들면 한쪽이 보이는 초안을
/// 다른 쪽이 "보이지 않게 남은 것" 으로 알린다.
public struct VerseDraftStoreView: Equatable, Sendable {
    /// 절마다의 대표 행(§8-7).
    public let representatives: [Int: VerseDrawingSnapshot]
    /// 절마다의 지금 대표 내용 지문. 비운 절은 들어 있지 않다 — 행이 없는 절과 같다.
    public let verseContent: [Int: String]
    /// 행마다의 지금 내용. 대표가 아닌 행(보관 · 비운 행)도 든다 — 초안이 보낸 행을 그대로 찾는다.
    public let rows: [BibleDrawingRowID: VerseDraftStoreRow]

    public init(snapshots: [VerseDrawingSnapshot]) {
        let representatives = snapshots.representativesByVerse()
        self.representatives = representatives
        self.verseContent = representatives.compactMapValues(\.contentFingerprint)
        self.rows = Dictionary(
            snapshots.map { ($0.rowID, VerseDraftStoreRow(contentFingerprint: $0.contentFingerprint)) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// 다른 세션의 초안을 지금 세션에서 어떻게 잇는가.
enum VerseDraftContinuation: Equatable, Sendable {
    /// 초안의 근거가 지금 환경에서 유효하고 지금 세션도 소유 근거가 있다 — 지금 세션으로 이어 쓴다. 이어 쓴 초안이 원 초안을 대신한다.
    case adopt
    /// 그 밖(보존만 · 확인 대기, 또는 지금 세션에 소유 근거가 없음) — 보이기만 한다. 이후 편집은 원 초안의 출처를 잇는다.
    case inherit
}

/// 초안 복구 판정 — 순수 함수라 표로 시험한다.
///
/// - **지금 세션의 초안은 보인다.** 사용자가 이 세션에서 방금 쓴 내용이다. 다시 읽기(레이아웃 변경 · 복원)로 저장소 내용을 새로
///   읽어도 그 위에 다시 겹친다 — 초안 전용 세션에서는 저장소에 없는 필기가 초안에만 있다. 다만 **이 세션이 저장소에 넣은 revision**
///   이면 역할이 끝났다 — 겹치면 그 뒤 들어온 내용을 가린다.
/// - **다른 세션의 초안은 이어 써도 되는 것만 보인다.** 근거(계정 · K)가 지금 환경에서 막히지 않고, 그 초안의 기준이 지금 저장소 내용과
///   같을 때다. 기준이 달라졌으면 그 사이 다른 내용이 들어온 것이다 — 겹치면 그 내용을 본 척 가린다. 보존만 하고 보이지 않는다.
/// - **귀속은 올리지 않는다.** 보존만 · 확인 대기 세션의 초안은 보이기만 하고(`showOnly`) 지금 세션으로 이어 쓰지 않는다. 지금 세션이
///   소유가 확인된 유효 세션이어도 그 절은 원 초안의 출처로 남고 저장소에 쓰지 않는다 — 한 획을 더한 것은 가져오기 동의가 아니다(④).
/// - **저장소로 보낸 초안은 그 행의 지금 내용과 견준다**(`VerseDraft.storeState`). 기준 지문만 보면 "빈 절에 X 를 써서 저장 → 그 절을 지움"
///   을 "빈 절 기준의 X 초안" 과 가리지 못해 지운 필기를 되살린다(A → B → A).
///   - 행의 내용이 초안과 같다 → 들어가 있다(정리 대상).
///   - 행이 없다 → 전송 전 계정 전환(F29) · 다른 기기의 삭제 · 보내기 전 종료. 되살릴 수 있게 보이되 **보이기만** 한다. 기준 행이 함께
///     사라졌을 수 있어(기존 필기를 고친 F29 — 올라간 적 없는 행) 기준 대신 **그 절이 비었는지**를 본다. 다른 내용이 들어와 있으면 가리지 않는다.
///   - 행이 편집 전 내용(기준) 그대로다 → 저장이 일어나지 않았거나, 계정 전환으로 지워진 뒤 옛 내용으로 다시 들어왔다(F29). 이 초안이
///     유일한 사본이다 — 보통 규칙으로 잇는다.
///   - 행이 **내가 앞서 넣은 내용**(`sentFingerprints`) 그대로다 → 그 뒤 revision 은 저장소에 닿지 않았다(전송 전 전환으로 서버 내용이
///     돌아온 경우 — ACC-1 2차 ⑪). **겹치지 않고 복구 후보로만 남긴다**(`recoverable`) — 같은 입력이 "다른 기기가 일부러 그 내용으로
///     되돌렸다" 와 구분되지 않는다. 화면 복구는 ④ 에서 사용자가 지금 필기와 견주어 고른다(사용자 결정 2026-09-21).
///   - 행이 그 뒤로 바뀌었다(지우기 · 복원 · 다른 기기) → 보이지 않고 남긴다. 보내던 중이었고 들어갔는지 가릴 수 없으면 **저장 완료가
///     불확실한 초안**으로 따로 센다.
/// - **보이는 것도 자동으로 저장소에 쓰지 않는다.** 겹쳐 보일 뿐이고, 사용자가 그 절을 다시 편집해야 그 세션의 초안 · 저장이 된다.
public enum VerseDraftRecoveryRule {
    /// - Parameters:
    ///   - drafts: 지금 계정 근거 묶음에 있는 이 장의 초안.
    ///   - storeContent: 절마다 저장소의 지금 대표 내용 지문. 없는 절은 빈 절이다(행 없음 · 비움).
    ///   - environment: 지금 편집 환경.
    ///   - sessionID: 지금 편집 세션. 없으면 모든 초안이 다른 세션의 것이다.
    ///   - storedRevisions: 행마다 지금 세션이 저장소 저장까지 마친 가장 새 revision.
    ///   - storeRows: 이 장의 저장소에 있는 행(대표 · 보관 · 빈 행 모두)과 그 내용.
    public static func plan(
        drafts: [VerseDraft],
        storeContent: [Int: String],
        environment: DrawingEditEnvironment,
        sessionID: String?,
        storedRevisions: [BibleDrawingRowID: Int] = [:],
        storeRows: [BibleDrawingRowID: VerseDraftStoreRow] = [:]
    ) -> VerseDraftRecoveryPlan {
        var plan = VerseDraftRecoveryPlan()
        let byVerse = Dictionary(grouping: drafts, by: \.key.verse)
        for verse in byVerse.keys.sorted() {
            let list = byVerse[verse] ?? []
            let own = list.filter { $0.key.sessionID == sessionID }.max { $0.revision < $1.revision }
            var candidates: [(draft: VerseDraft, continuation: VerseDraftContinuation)] = []
            for draft in list where draft.key.sessionID != sessionID {
                switch standing(of: draft, verseContent: storeContent[verse], rows: storeRows) {
                case .settled:
                    plan.settled.append(draft)
                case .kept(let uncertain):
                    plan.kept.append(draft)
                    if uncertain { plan.uncertain.append(draft) }
                case .candidate:
                    if let continuation = continuation(of: draft, storeFingerprint: storeContent[verse], environment: environment) {
                        candidates.append((draft, continuation))
                    } else {
                        plan.kept.append(draft)
                    }
                case .resumable:
                    // 그 행이 내가 넣었던 내용으로 돌아왔다 — 그 뒤 편집은 이 초안에만 있다. 자동으로 겹치지 않고 복구 후보로 남긴다.
                    plan.kept.append(draft)
                    plan.recoverable.append(draft)
                case .orphaned:
                    // 보낸 행이 사라졌다. 그 절이 비었거나 기준 그대로면 가릴 내용이 없다 — 근거(계정 · K)만 보고 보이기만 한다.
                    let verseContent = storeContent[verse]
                    if verseContent == nil || verseContent == draft.baseFingerprint, continuation(of: draft, environment: environment) != nil {
                        candidates.append((draft, .inherit))
                    } else {
                        plan.kept.append(draft)
                    }
                }
            }
            if let own {
                let stored = (storedRevisions[own.rowID] ?? 0) >= own.revision
                    || (own.storeState == .stored && storeRows[own.rowID]?.contentFingerprint == own.contentFingerprint)
                if stored {
                    plan.settled.append(own)
                } else {
                    plan.shown.append(own)
                }
                plan.kept.append(contentsOf: candidates.map(\.draft))
                continue
            }
            // 이어 쓸 수 있는 것이 여럿이면 가장 늦게 쓴 것을 보인다. 나머지는 지우지 않고 남긴다 — 사용자가 보지 않은 것은 이어받지 않는다.
            guard let latest = candidates.max(by: { lhs, rhs in
                (lhs.draft.savedAt, lhs.draft.revision, lhs.draft.key.sessionID) < (rhs.draft.savedAt, rhs.draft.revision, rhs.draft.key.sessionID)
            }) else { continue }
            plan.shown.append(latest.draft)
            if latest.continuation == .inherit { plan.showOnly.insert(latest.draft.key) }
            plan.kept.append(contentsOf: candidates.map(\.draft).filter { $0 != latest.draft })
        }
        return plan
    }

    /// 이 초안이 지금 환경의 화면에 오를 수 있는 묶음의 것인가.
    ///
    /// **확인 전 묶음의 초안은 그때 참고하던 계정(힌트)이 지금 참고하는 계정과 같을 때만**이다(사용자 결정 2026-09-21, 11차 리뷰 P1).
    /// 다른 힌트의 초안은 다른 계정의 필기일 수 있다. **보이기만** 가리는 규칙이고 파일 · 출처 · 묶음은 그대로 남는다 — 보이지 않는
    /// 초안은 복구 화면(④)이 알린다.
    public static func reachesScreen(_ draft: VerseDraft, environment: DrawingEditEnvironment) -> Bool {
        guard case .unverified(let hint) = draft.account else { return true }
        return hint == environment.accountBasis.referencedAccount
    }

    /// 다른 세션의 초안이 지금 저장소와 어떤 관계인가.
    enum Standing: Equatable {
        /// 내용이 이미 저장소에 있다.
        case settled
        /// 이어 볼 후보다(근거 · 기준 판정은 `continuation`).
        case candidate
        /// 그 행이 내가 앞서 넣은 내용으로 돌아왔다 — 기준 대신 그 사실로 잇는다(근거만 본다).
        case resumable
        /// 저장소로 보낸 행이 사라졌다 — 되살릴 수 있게 보이되 근거가 유효해도 보이기만 한다.
        case orphaned
        /// 보이지 않고 남긴다. `uncertain` 이면 저장 완료가 불확실하다.
        case kept(uncertain: Bool)
    }

    static func standing(of draft: VerseDraft, verseContent: String?, rows: [BibleDrawingRowID: VerseDraftStoreRow]) -> Standing {
        guard let state = draft.storeState else {
            // 저장소로 보낸 적 없다 — 내용이 이미 그 절의 대표 내용이면 역할이 끝났다.
            return draft.contentFingerprint == verseContent ? .settled : .candidate
        }
        guard let row = rows[draft.rowID] else {
            // 보낸 행이 저장소에 없다 — 전송 전 계정 전환(F29) · 다른 기기의 삭제 · 보내기 전 종료. 같은 내용이 다른 행으로 이미 있으면 역할이 끝났고,
            // 아니면 되살릴 수 있게 보이되, 다시 올릴지는 사용자가 정한다.
            return draft.contentFingerprint == verseContent ? .settled : .orphaned
        }
        if row.contentFingerprint == draft.contentFingerprint { return .settled }
        if let sent = draft.sentFingerprints, let now = row.contentFingerprint, sent.contains(now) {
            // 내가 넣었던 내용 그대로다 — 그 뒤 revision 은 저장소에 닿지 못했다(전송 전 계정 전환 · 종료).
            return .resumable
        }
        if case .legacy(let baseRow, let baseFingerprint) = draft.base, baseRow == draft.rowID, row.contentFingerprint == baseFingerprint {
            // 그 행이 편집 전 내용 그대로다 — 저장이 일어나지 않았거나(보내기 전 종료), 계정 전환으로 지워진 뒤 옛 내용으로 다시 들어왔다(F29).
            // 이 초안이 유일한 사본이다.
            return .candidate
        }
        // 그 행이 그 뒤로 바뀌었다(지우기 · 복원 · 다른 기기). 들어갔던 것이 확실하면(저장 확인 · 새 절의 행은 이 저장으로만 생긴다) 보존만 하고,
        // 보내던 중이라 들어갔는지 모르면 저장 완료가 불확실한 초안으로 센다.
        let reached = state == .stored || draft.base == .empty
        return .kept(uncertain: !reached)
    }

    /// 다른 세션의 초안을 지금 환경에서 어떻게 잇는가. 보이지 않아야 하면 nil.
    static func continuation(
        of draft: VerseDraft,
        storeFingerprint: String?,
        environment: DrawingEditEnvironment
    ) -> VerseDraftContinuation? {
        // 기준이 지금 저장소 내용과 같아야 한다 — 달라졌으면 그 사이 들어온 내용을 가린다.
        guard draft.baseFingerprint == storeFingerprint else { return nil }
        return continuation(of: draft, environment: environment)
    }

    /// 근거(계정 · K · 소유)만 본 이어 쓰기. 보이지 않아야 하면 nil.
    static func continuation(of draft: VerseDraft, environment: DrawingEditEnvironment) -> VerseDraftContinuation? {
        // K 를 읽지 못했으면 그 초안이 알려진 삭제 전에 쓴 것인지 알 수 없다.
        guard let device = environment.knowledge else { return nil }
        if draft.knownEpochs == nil, !device.all.isEmpty { return nil }
        let context = VerseEditContext(
            contextID: draft.key.sessionID, verse: draft.key.verse, base: draft.base, knownEpochs: draft.knownEpochs, account: draft.account
        )
        // 시험용으로 주입한 소유 근거는 주입 없는 실행에서 근거가 아니다 — 표시도 이어 쓰기도 그 계정에 귀속하지 않는다.
        let owner = draft.ownershipInjected == true && !environment.ownershipInjected ? nil : draft.storeOwnership
        switch VerseEditContextRule.validity(
            of: context, accountState: environment.accountState, deviceKnowledge: device, loadedDataOwner: owner
        ) {
        case .accountChanged, .eraseLearned:
            return nil
        case .valid:
            // 지금 세션도 저장소 소유 근거가 있어야 이어 쓴다 — 없으면(보존만 · 로그인하지 않음) 이어 쓴 초안이 원 초안의 근거를 잃는다.
            return environment.storeOwnership == nil ? .inherit : .adopt
        case .awaitingAccountConfirmation, .preserveOnly:
            return .inherit
        }
    }
}
