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
/// - 보이지 않는 초안을 지우는 것(보존만 한다)
@Suite("초안 복구 판정")
struct VerseDraftRecoveryRuleTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let accountA = AccountScope(key: "acct-a")
    private let accountB = AccountScope(key: "acct-b")
    private let base = "vc1-base"

    private func confirmed(_ scope: AccountScope, knowledge: EraseEpochKnowledge? = EraseEpochKnowledge()) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope), serverWork: AccountServerWorkToken(scope: scope, generation: 3), knowledge: knowledge
        )
    }

    private func draft(
        verse: Int = 1,
        session: String = "old",
        ink: String? = "획",
        baseFingerprint: String? = "vc1-base",
        account: VerseEditAccountBasis? = nil,
        knownEpochs: Set<String>? = [],
        savedAt: TimeInterval = 1_000,
        revision: Int = 1
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
            storeOwnership: nil,
            eraseGeneration: 0,
            savedAt: Date(timeIntervalSince1970: savedAt)
        )
    }

    private func plan(_ drafts: [VerseDraft], store: [Int: String]? = nil, environment: DrawingEditEnvironment? = nil,
                      session: String? = "now") -> VerseDraftRecoveryPlan {
        VerseDraftRecoveryRule.plan(
            drafts: drafts, storeContent: store ?? [1: base, 2: base], environment: environment ?? confirmed(accountA), sessionID: session
        )
    }

    // MARK: - 지금 세션

    @Test("지금 세션의 초안은 기준이 달라져도 보인다 — 방금 쓴 필기다")
    func ownDraftIsAlwaysShown() {
        let own = draft(session: "now", baseFingerprint: "vc1-older")
        #expect(plan([own]).shown == [own])
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

    @Test("다른 세션의 초안은 근거가 유효하고 기준이 저장소와 같으면 보인다")
    func matchingOtherDraftIsShown() {
        let other = draft()
        #expect(plan([other]).shown == [other])
    }

    @Test("확인 전(보존만) 세션의 초안도 같은 확인 전 환경에서는 이어 보인다")
    func unverifiedDraftInUnverifiedEnvironment() {
        let other = draft(account: .unverified(hint: accountA))
        let environment = DrawingEditEnvironment(
            accountState: .unconfirmed(lastConfirmed: accountA), serverWork: nil, knowledge: EraseEpochKnowledge()
        )
        #expect(plan([other], environment: environment).shown == [other])
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

    @Test("내용이 이미 저장소에 있는 다른 세션의 초안은 정리 대상이다")
    func sameContentIsSettled() {
        let other = draft()
        let result = plan([other], store: [1: other.contentFingerprint ?? ""])
        #expect(result.settled == [other])
        #expect(result.shown.isEmpty)
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
