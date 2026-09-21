//
//  VerseDraftRecoveryRuleTesting.swift
//  DomainTest
//
//  장을 불러올 때 남은 초안을 보일지 · 보존만 할지 · 정리할지 (정책 §12-6 구현 순서 ②).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 지금 세션에서 쓴 필기가 다시 읽기 뒤 화면에서 사라지는 것(초안 전용 세션은 저장소에 쓰지 않는다)
/// - 그 사이 들어온 내용이나 알게 된 삭제를 모른 채 쓴 옛 초안을 그 위에 겹쳐, 새 내용을 본 척 가리거나 지운 필기를 되살리는 것
/// - 다른 계정 근거의 초안을 지금 계정 화면에 섞는 것
/// - 보존만 · 확인 대기 초안을 이어 보인 절을 지금 세션으로 이어 써 귀속을 올리는 것(보이기만 한다)
/// - 이 세션이 저장소에 넣은 초안을 다시 겹쳐 그 뒤 저장소 내용을 가리는 것
/// - 보이지 않는 초안을 지우는 것(보존만 한다)
@Suite("초안 복구 판정")
struct VerseDraftRecoveryRuleTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let accountA = AccountScope(key: "acct-a")
    private let accountB = AccountScope(key: "acct-b")
    private let base = "vc1-base"

    private func confirmed(
        _ scope: AccountScope,
        knowledge: EraseEpochKnowledge? = EraseEpochKnowledge(),
        owned: Bool = false
    ) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope), serverWork: AccountServerWorkToken(scope: scope, generation: 3), knowledge: knowledge,
            storeOwnership: owned ? scope : nil
        )
    }

    private func draft(
        verse: Int = 1,
        session: String = "old",
        ink: String? = "획",
        baseFingerprint: String? = "vc1-base",
        account: VerseEditAccountBasis? = nil,
        knownEpochs: Set<String>? = [],
        storeOwnership: AccountScope? = nil,
        savedAt: TimeInterval = 1_000,
        revision: Int = 1,
        storeState: VerseDraftStoreState? = nil,
        ownershipInjected: Bool? = nil
    ) -> VerseDraft {
        VerseDraft(
            key: VerseDraftKey(sessionID: session, chapter: chapter, verse: verse),
            revision: revision,
            rowID: BibleDrawingRowID(raw: "row-\(verse)"),
            lineData: ink.map { Data($0.utf8) },
            drawingVersion: ink == nil ? nil : 3,
            layoutMetadataData: nil,
            base: baseFingerprint.map { .legacy(rowID: BibleDrawingRowID(raw: "row-\(verse)"), contentFingerprint: $0) } ?? .empty,
            baseFingerprint: baseFingerprint,
            account: account ?? .confirmed(AccountServerWorkToken(scope: accountA, generation: 1)),
            knownEpochs: knownEpochs,
            storeOwnership: storeOwnership,
            eraseGeneration: 0,
            savedAt: Date(timeIntervalSince1970: savedAt),
            storeState: storeState,
            ownershipInjected: ownershipInjected
        )
    }

    private func plan(_ drafts: [VerseDraft], store: [Int: String]? = nil, environment: DrawingEditEnvironment? = nil,
                      session: String? = "now", stored: [BibleDrawingRowID: Int] = [:],
                      rows: [BibleDrawingRowID: VerseDraftStoreRow] = [:]) -> VerseDraftRecoveryPlan {
        VerseDraftRecoveryRule.plan(
            drafts: drafts, storeContent: store ?? [1: base, 2: base], environment: environment ?? confirmed(accountA), sessionID: session,
            storedRevisions: stored, storeRows: rows
        )
    }

    // MARK: - 지금 세션

    @Test("지금 세션의 초안은 기준이 달라져도 보인다 — 방금 쓴 필기다")
    func ownDraftIsAlwaysShown() {
        let own = draft(session: "now", baseFingerprint: "vc1-older")
        #expect(plan([own]).shown == [own])
    }

    /// 저장소에 넣은 revision 은 역할이 끝났다. 겹치면 그 뒤 들어온 내용(원격 덮어쓰기 등)을 가린다. 지우지는 않는다(ACC-1 F29).
    @Test("지금 세션이 저장소에 넣은 revision 의 초안은 겹치지 않고 정리 대상으로 남긴다 — 더 새 revision 이면 보인다")
    func storedOwnDraftIsSettled() {
        let own = draft(session: "now", revision: 2)
        let settled = plan([own], store: [1: "vc1-remote"], stored: [own.rowID: 2])
        #expect(settled.shown.isEmpty)
        #expect(settled.settled == [own])
        #expect(plan([own], stored: [own.rowID: 1]).shown == [own])
    }

    @Test("지금 세션의 초안이 있으면 같은 절의 다른 세션 초안은 보이지 않고 남는다")
    func ownDraftWinsOverOthers() {
        let own = draft(session: "now", ink: "지금")
        let other = draft(session: "old", ink: "예전", savedAt: 9_999)
        let result = plan([own, other])
        #expect(result.shown == [own])
        #expect(result.kept == [other])
    }

    // MARK: - 다른 세션 — 이어 쓰기

    @Test("근거가 유효한 다른 세션의 초안은 소유 근거가 있는 지금 세션이 이어 쓴다")
    func validOtherDraftIsAdopted() {
        let other = draft(storeOwnership: accountA)
        let result = plan([other], environment: confirmed(accountA, owned: true))
        #expect(result.shown == [other])
        #expect(result.showOnly.isEmpty)
    }

    /// 한 획을 더한 것은 계정 간 가져오기 동의가 아니다 — 귀속할 근거 없는 초안을 지금 세션으로 올리지 않는다.
    @Test("보존만 초안은 소유가 확인된 세션에서도 보이기만 한다")
    func preserveOnlyDraftIsShowOnly() {
        let other = draft()
        let result = plan([other], environment: confirmed(accountA, owned: true))
        #expect(result.shown == [other])
        #expect(result.showOnly == [other.key])
    }

    /// 이어 쓴 초안은 지금 세션의 근거를 든다. 지금 세션에 소유 근거가 없으면 원 초안의 소유 근거를 잃는다.
    @Test("근거가 유효한 초안도 지금 세션에 소유 근거가 없으면 보이기만 한다")
    func validDraftInUnownedSessionIsShowOnly() {
        let other = draft(storeOwnership: accountA)
        let result = plan([other], environment: confirmed(accountA))
        #expect(result.shown == [other])
        #expect(result.showOnly == [other.key])
    }

    @Test("확인 전(보존만) 세션의 초안도 같은 확인 전 환경에서는 보이되, 보이기만 한다")
    func unverifiedDraftInUnverifiedEnvironment() {
        let other = draft(account: .unverified(hint: accountA))
        let environment = DrawingEditEnvironment(
            accountState: .unconfirmed(lastConfirmed: accountA), serverWork: nil, knowledge: EraseEpochKnowledge()
        )
        let result = plan([other], environment: environment)
        #expect(result.shown == [other])
        #expect(result.showOnly == [other.key])
    }

    @Test("로그인하지 않은 채 쓴 초안은 같은 이 기기 전용 환경에서 보이되, 보이기만 한다")
    func localOnlyDraftIsShowOnly() {
        let other = draft(account: .localOnly)
        let environment = DrawingEditEnvironment(accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge())
        let result = plan([other], environment: environment)
        #expect(result.shown == [other])
        #expect(result.showOnly == [other.key])
    }

    @Test("이어 쓸 수 있는 초안이 여럿이면 가장 늦게 쓴 것만 보이고 나머지는 남긴다")
    func latestCandidateIsShown() {
        let early = draft(session: "s1", ink: "먼저", savedAt: 1_000)
        let late = draft(session: "s2", ink: "나중", savedAt: 2_000)
        let result = plan([late, early])
        #expect(result.shown == [late])
        #expect(result.kept == [early])
    }

    // MARK: - 다른 세션 — 보존만

    @Test("기준이 지금 저장소 내용과 다르면 보이지 않고 남긴다 — 그 사이 들어온 내용을 가리지 않는다")
    func baseMismatchIsKept() {
        let other = draft(baseFingerprint: "vc1-before-remote")
        let result = plan([other])
        #expect(result.shown.isEmpty)
        #expect(result.kept == [other])
    }

    @Test("모르던 삭제 기준점을 이제 알면 그 전에 쓴 초안은 보이지 않는다")
    func learnedEraseIsKept() {
        var learned = EraseEpochKnowledge()
        learned.receive("E1")
        let other = draft(knownEpochs: [])
        let result = plan([other], environment: confirmed(accountA, knowledge: learned))
        #expect(result.shown.isEmpty)
        #expect(result.kept == [other])
    }

    @Test("지금 K 를 읽지 못하면 다른 세션의 초안을 보이지 않는다")
    func unreadableDeviceKnowledgeIsKept() {
        let result = plan([draft()], environment: confirmed(accountA, knowledge: nil))
        #expect(result.shown.isEmpty)
        #expect(result.kept.count == 1)
    }

    @Test("K 를 모른 채 쓴 초안은 기기가 기준점을 알면 보이지 않고, 기준점이 없으면 보인다")
    func draftWithUnknownKnowledge() {
        let other = draft(knownEpochs: nil)
        var learned = EraseEpochKnowledge()
        learned.receive("E1")
        #expect(plan([other], environment: confirmed(accountA, knowledge: learned)).shown.isEmpty)
        #expect(plan([other]).shown == [other])
    }

    @Test("다른 계정으로 확인된 환경에는 그 계정의 초안을 섞지 않는다")
    func otherAccountIsKept() {
        let result = plan([draft()], environment: confirmed(accountB))
        #expect(result.shown.isEmpty)
        #expect(result.kept.count == 1)
    }

    // MARK: - 정리

    @Test("내용이 이미 저장소에 있는 다른 세션의 초안은 겹치지 않는 정리 대상이다(지우지 않는다)")
    func sameContentIsSettled() {
        let other = draft()
        let result = plan([other], store: [1: other.contentFingerprint ?? ""])
        #expect(result.settled == [other])
        #expect(result.shown.isEmpty)
    }

    // MARK: - 저장소로 보낸 초안(storeState)

    private func row(_ fingerprint: String?) -> VerseDraftStoreRow { VerseDraftStoreRow(contentFingerprint: fingerprint) }

    /// 빈 절에 X 를 써서 저장소에 넣은 뒤 그 절을 지웠다(행은 남고 비었다). 기준(빈 절)이 다시 저장소와 같아도 되살리지 않는다.
    @Test("저장소에 넣은 새 절 초안은 그 행이 그 뒤로 바뀌었으면 기준이 같아져도 보이지 않는다(A → B → A)")
    func storedNewVerseDraftIsNotResurrected() {
        let stored = draft(ink: "X", baseFingerprint: nil, storeOwnership: accountA, storeState: .stored)
        let result = plan([stored], store: [:], environment: confirmed(accountA, owned: true), rows: [stored.rowID: row(nil)])
        #expect(result.shown.isEmpty)
        #expect(result.kept == [stored])
        #expect(result.uncertain.isEmpty)
    }

    @Test("보낸 행의 내용이 초안과 같으면 들어가 있다 — 보내는 중 표식이어도 정리 대상이다")
    func sentDraftMatchingRowIsSettled() {
        for state in [VerseDraftStoreState.sending, .stored] {
            let sent = draft(storeOwnership: accountA, storeState: state)
            let result = plan([sent], environment: confirmed(accountA, owned: true), rows: [sent.rowID: row(sent.contentFingerprint)])
            #expect(result.settled == [sent])
        }
    }

    /// 전송 전 계정 전환(F29) · 다른 기기의 삭제로 행이 사라졌다. 되살릴 수 있게 보이되, 다시 올릴지는 사용자가 정한다.
    @Test("보낸 행이 저장소에서 사라졌으면 보이되, 근거가 유효해도 보이기만 한다")
    func sentDraftWithMissingRowIsShowOnly() {
        let stored = draft(ink: "X", baseFingerprint: nil, storeOwnership: accountA, storeState: .stored)
        let result = plan([stored], store: [:], environment: confirmed(accountA, owned: true), rows: [:])
        #expect(result.shown == [stored])
        #expect(result.showOnly == [stored.key])
    }

    /// 기존 필기를 고쳤는데 그 행이 서버에 올라간 적이 없었다 — 계정 전환(F29)이 행을 지우고, 돌아와도 그 절은 비어 있다. 기준 행이 함께 사라져
    /// 기준 지문으로는 이어 볼 수 없다. 가릴 내용이 없으므로 보이기만 한다.
    @Test("기존 필기를 고친 초안의 행이 사라지고 그 절이 비었으면 기준이 없어도 보이기만 한다 — 보내는 중 표식이어도 같다")
    func sentExistingVerseDraftWithMissingRowIsShowOnly() {
        for state in [VerseDraftStoreState.sending, .stored] {
            let edited = draft(storeOwnership: accountA, storeState: state)
            let result = plan([edited], store: [:], environment: confirmed(accountA, owned: true), rows: [:])
            #expect(result.shown == [edited])
            #expect(result.showOnly == [edited.key])
        }
    }

    @Test("보낸 행이 사라진 초안도 그 절에 다른 내용이 들어와 있으면 가리지 않고, 근거(계정 · K)가 막히면 보이지 않는다")
    func missingRowDraftDoesNotCoverOtherContent() {
        let edited = draft(storeOwnership: accountA, storeState: .stored)
        let other = plan([edited], store: [1: "vc1-remote"], environment: confirmed(accountA, owned: true),
                         rows: [BibleDrawingRowID(raw: "remote"): row("vc1-remote")])
        #expect(other.shown.isEmpty)
        #expect(other.kept == [edited])

        let otherAccount = plan([edited], store: [:], environment: confirmed(accountB, owned: true), rows: [:])
        #expect(otherAccount.shown.isEmpty)
        var knowledge = EraseEpochKnowledge()
        knowledge.receive("E1")
        let learned = plan([edited], store: [:], environment: confirmed(accountA, knowledge: knowledge, owned: true), rows: [:])
        #expect(learned.shown.isEmpty)
        // 같은 내용이 다른 행으로 이미 있으면 역할이 끝났다.
        let copied = plan([edited], store: [1: edited.contentFingerprint ?? ""], environment: confirmed(accountA, owned: true), rows: [:])
        #expect(copied.settled == [edited])
    }

    /// 기존 필기를 고쳐 저장했는데 계정 전환으로 지워진 뒤 옛 내용으로 다시 들어왔다(F29) — 또는 보내기 전에 끝났다. 이 초안이 유일한 사본이다.
    @Test("보낸 행이 편집 전 내용 그대로면 보통 규칙으로 이어 쓴다 — 기존 필기를 고친 F29 복구")
    func sentDraftOverUnchangedRowIsContinued() {
        for state in [VerseDraftStoreState.sending, .stored] {
            let edited = draft(storeOwnership: accountA, storeState: state)
            let result = plan([edited], environment: confirmed(accountA, owned: true), rows: [edited.rowID: row(base)])
            #expect(result.shown == [edited])
            #expect(result.showOnly.isEmpty)
        }
    }

    /// 보내던 중 끝났고, 그 뒤 그 행이 바뀌었다(지우기 · 다른 기기). 들어갔는지 가릴 수 없다 — 확정된 사실로 되살리지 않는다.
    @Test("보내는 중 표식의 기존 필기 초안은 행이 바뀌었으면 저장 완료가 불확실한 초안으로 보존만 한다")
    func sendingDraftOverChangedRowIsUncertain() {
        let sending = draft(storeOwnership: accountA, storeState: .sending)
        let result = plan([sending], environment: confirmed(accountA, owned: true), rows: [sending.rowID: row("vc1-remote")])
        #expect(result.shown.isEmpty)
        #expect(result.kept == [sending])
        #expect(result.uncertain == [sending])
    }

    /// 전송 전에 계정이 바뀌어 그 행이 **내가 앞서 넣은 내용**으로 돌아왔다(ACC-1 2차 ⑪). 그 뒤 revision 은 이 초안에만 있다.
    @Test("행이 내가 넣었던 내용으로 돌아왔으면 기준이 달라도 이어 보고, 소유 근거가 없으면 보이기만 한다")
    func rowBackToSentContentIsResumed() {
        var sent = draft(ink: "고친 내용", storeOwnership: accountA, storeState: .stored)
        sent.sentFingerprints = ["vc1-sent-old", sent.contentFingerprint ?? ""]
        let rows = [sent.rowID: row("vc1-sent-old")]

        let owned = plan([sent], store: [1: "vc1-sent-old"], environment: confirmed(accountA, owned: true), rows: rows)
        #expect(owned.shown == [sent])
        #expect(owned.showOnly.isEmpty)

        let unowned = plan([sent], store: [1: "vc1-sent-old"], environment: confirmed(accountA), rows: rows)
        #expect(unowned.shown == [sent])
        #expect(unowned.showOnly == [sent.key])
    }

    @Test("내가 넣은 적 없는 내용으로 바뀐 행은 그대로 보존만 한다 — 넣은 지문 기록이 있어도 같다")
    func rowWithForeignContentIsStillKept() {
        var sent = draft(ink: "고친 내용", storeOwnership: accountA, storeState: .stored)
        sent.sentFingerprints = ["vc1-sent-old"]
        let result = plan([sent], store: [1: "vc1-remote"], environment: confirmed(accountA, owned: true),
                          rows: [sent.rowID: row("vc1-remote")])
        #expect(result.shown.isEmpty)
        #expect(result.kept == [sent])
    }

    // MARK: - 시험용 소유 주입

    @Test("시험용으로 주입한 소유 근거의 초안은 주입 없는 환경에서 보이기만 하고, 주입 환경에서는 이어 쓴다")
    func injectedOwnershipIsNotEvidenceWithoutInjection() {
        let injected = draft(storeOwnership: accountA, ownershipInjected: true)
        let plain = plan([injected], environment: confirmed(accountA, owned: true))
        #expect(plain.shown == [injected])
        #expect(plain.showOnly == [injected.key])

        var injectedEnvironment = confirmed(accountA, owned: true)
        injectedEnvironment.ownershipInjected = true
        let withInjection = plan([injected], environment: injectedEnvironment)
        #expect(withInjection.shown == [injected])
        #expect(withInjection.showOnly.isEmpty)
    }

    @Test("비운 초안과 빈 절은 같은 내용이다")
    func emptyDraftOnEmptyVerseIsSettled() {
        let cleared = draft(ink: nil, baseFingerprint: nil)
        let result = plan([cleared], store: [:])
        #expect(result.settled == [cleared])
    }

    @Test("절마다 따로 판정한다")
    func versesAreIndependent() {
        let first = draft(verse: 1)
        let second = draft(verse: 2, baseFingerprint: "vc1-changed")
        let result = plan([first, second])
        #expect(result.shown == [first])
        #expect(result.kept == [second])
    }
}
