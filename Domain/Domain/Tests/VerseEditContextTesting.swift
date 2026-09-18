//
//  VerseEditContextTesting.swift
//  DomainTest
//
//  편집 문맥 — 계정 근거 · 기준 · K 를 편집을 시작할 때 고정한다 (정책 §12-6 구현 순서 ①).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 저장 시점의 "현재 끝" 을 부모로 삼아, 보지 않은 원격 편집을 반영한 척 충돌을 숨기는 것
/// - 장 전체의 전역 K 로, 삭제를 받은 뒤의 새 편집을 숨기거나 낡은 화면 내용을 되살리는 것
/// - 계정이 바뀐 뒤에도 이전 계정의 편집 문맥으로 확정하는 것
@Suite("편집 문맥")
struct VerseEditContextTesting {

    private let accountA = AccountScope(key: "acct-a")
    private let accountB = AccountScope(key: "acct-b")

    private func context(
        base: VerseEditBase = .version(versionID: "v0"),
        known: Set<String> = [],
        account: VerseEditAccountBasis
    ) -> VerseEditContext {
        VerseEditContext(verse: 1, base: base, knownEpochs: known, account: account)
    }

    private func token(_ scope: AccountScope, generation: UInt64 = 1) -> AccountServerWorkToken {
        AccountServerWorkToken(scope: scope, generation: generation)
    }

    // MARK: - 부모

    @Test("부모는 편집을 시작할 때 보던 기준이다")
    func parentIsTheBaseTheUserSaw() {
        #expect(context(base: .empty, account: .localOnly).parentIDs(legacyParentID: nil) == [])
        #expect(context(base: .version(versionID: "v0"), account: .localOnly).parentIDs(legacyParentID: nil) == ["v0"])
        let legacy = context(base: .legacy(rowID: BibleDrawingRowID(raw: "row-1"), contentFingerprint: "vc1-a"), account: .localOnly)
        #expect(legacy.parentIDs(legacyParentID: "legacy-abc") == ["legacy-abc"])
    }

    /// 화면은 V0 인데 원격 V1 이 들어온 뒤 로컬 편집을 확정해도, 부모는 V0 다 — V1 은 분기로 남는다.
    /// 부모 계산은 저장소의 "현재 끝" 을 받지 않는다. 받을 수 없게 해 두는 것이 이 규칙의 경계다.
    @Test("같은 기기의 연속 확정만 직전 로컬 확정을 잇고, 보지 않은 원격 끝은 부모가 아니다")
    func consecutiveLocalCommitsChain() {
        var edit = context(base: .version(versionID: "v0"), account: .localOnly)
        #expect(edit.parentIDs(legacyParentID: nil) == ["v0"])

        edit.recordLocalCommit("v2")
        #expect(edit.parentIDs(legacyParentID: nil) == ["v2"])

        edit.recordLocalCommit("v3")
        #expect(edit.parentIDs(legacyParentID: nil) == ["v3"])
    }

    // MARK: - 유효성

    @Test("확인된 계정에서 시작한 문맥은 표가 유효하고 모르는 삭제가 없을 때만 유효하다")
    func confirmedContextValidity() {
        let edit = context(account: .confirmed(token(accountA)))
        var learned = EraseEpochKnowledge()
        learned.receive("E1")

        #expect(VerseEditContextRule.validity(of: edit, accountState: .confirmed(accountA), isTokenCurrent: true,
                                              deviceKnowledge: EraseEpochKnowledge()) == .valid)
        // 계정 변경 알림 · 재확인으로 표가 무효가 됐다.
        #expect(VerseEditContextRule.validity(of: edit, accountState: .confirmed(accountA), isTokenCurrent: false,
                                              deviceKnowledge: EraseEpochKnowledge()) == .accountChanged)
        #expect(VerseEditContextRule.validity(of: edit, accountState: .unconfirmed(lastConfirmed: accountA), isTokenCurrent: false,
                                              deviceKnowledge: EraseEpochKnowledge()) == .accountChanged)
        // 편집 도중 삭제를 알게 됐다 — 편집 중이던 내용은 그 삭제를 모른 채 쓴 것이다.
        #expect(VerseEditContextRule.validity(of: edit, accountState: .confirmed(accountA), isTokenCurrent: true,
                                              deviceKnowledge: learned) == .eraseLearned)
        // 그 삭제를 알고 시작한 문맥은 유효하다.
        #expect(VerseEditContextRule.validity(of: context(known: ["E1"], account: .confirmed(token(accountA))),
                                              accountState: .confirmed(accountA), isTokenCurrent: true,
                                              deviceKnowledge: learned) == .valid)
    }

    @Test("확인 전에 시작한 문맥은 확인된 계정이 그때의 마지막 확인 계정과 같을 때만 잇는다")
    func unverifiedContextValidity() {
        let withHint = context(account: .unverified(hint: accountA))
        let withoutHint = context(account: .unverified(hint: nil))
        let empty = EraseEpochKnowledge()

        #expect(VerseEditContextRule.validity(of: withHint, accountState: .unconfirmed(lastConfirmed: accountA), isTokenCurrent: false,
                                              deviceKnowledge: empty) == .awaitingAccountConfirmation)
        #expect(VerseEditContextRule.validity(of: withHint, accountState: .confirmed(accountA), isTokenCurrent: true,
                                              deviceKnowledge: empty) == .valid)
        #expect(VerseEditContextRule.validity(of: withHint, accountState: .confirmed(accountB), isTokenCurrent: true,
                                              deviceKnowledge: empty) == .accountChanged)
        #expect(VerseEditContextRule.validity(of: withoutHint, accountState: .confirmed(accountA), isTokenCurrent: true,
                                              deviceKnowledge: empty) == .accountChanged)
        #expect(VerseEditContextRule.validity(of: withHint, accountState: .noAccount, isTokenCurrent: false,
                                              deviceKnowledge: empty) == .accountChanged)
    }

    @Test("확인을 기다리는 문맥도 모르는 삭제가 있으면 먼저 끝낸다")
    func unverifiedContextStillChecksErase() {
        var learned = EraseEpochKnowledge()
        learned.note(referenced: ["E1"])

        #expect(VerseEditContextRule.validity(of: context(account: .unverified(hint: accountA)),
                                              accountState: .unconfirmed(lastConfirmed: accountA), isTokenCurrent: false,
                                              deviceKnowledge: learned) == .eraseLearned)
    }

    /// 로그인 안 함 ↔ 계정 사이는 자동으로 잇지 않는다. 가져오기는 사용자가 명시적으로 하는 별도 작업이다.
    @Test("로그인하지 않은 채 시작한 문맥은 로그인하면 끝난다")
    func localOnlyContextValidity() {
        let edit = context(account: .localOnly)
        let empty = EraseEpochKnowledge()

        #expect(VerseEditContextRule.validity(of: edit, accountState: .noAccount, isTokenCurrent: false, deviceKnowledge: empty) == .valid)
        #expect(VerseEditContextRule.validity(of: edit, accountState: .confirmed(accountA), isTokenCurrent: true, deviceKnowledge: empty)
            == .accountChanged)
        #expect(VerseEditContextRule.validity(of: edit, accountState: .unconfirmed(lastConfirmed: nil), isTokenCurrent: false,
                                              deviceKnowledge: empty) == .accountChanged)
    }

    /// 초안(②)이 문맥을 파일로 남긴다.
    @Test("문맥은 저장했다 읽어도 그대로다")
    func contextRoundTrips() throws {
        var edit = context(base: .legacy(rowID: BibleDrawingRowID(raw: "row-1"), contentFingerprint: "vc1-a"),
                           known: ["E1"], account: .confirmed(token(accountA, generation: 7)))
        edit.recordLocalCommit("v9")

        let decoded = try JSONDecoder().decode(VerseEditContext.self, from: JSONEncoder().encode(edit))

        #expect(decoded == edit)
    }

    // MARK: - legacy 논리 ID

    @Test("legacy 논리 ID 는 종류 · 원본 · 내용 지문이 모두 같을 때만 같다")
    func legacyVersionIDs() {
        let global = LegacyVersionID.Source.global(rowUUID: "row-1")
        let base = LegacyVersionID.make(kind: .legacyImport, source: global, contentFingerprint: "vc1-a")

        #expect(base.hasPrefix("legacy-"))
        #expect(base == LegacyVersionID.make(kind: .legacyImport, source: global, contentFingerprint: "vc1-a"))
        // 같은 행의 내용이 바뀌면 다른 버전이다 — 불변 버전 규칙.
        #expect(base != LegacyVersionID.make(kind: .legacyImport, source: global, contentFingerprint: "vc1-b"))
        // 같은 원본의 수용과 삭제 관측은 다른 버전이다.
        #expect(base != LegacyVersionID.make(kind: .legacyDelete, source: global, contentFingerprint: "vc1-a"))
        // 전역 식별자가 없는 행은 기기 안의 식별로 만든다 — 전역 행과 섞이지 않는다.
        #expect(base != LegacyVersionID.make(kind: .legacyImport,
                                             source: .deviceScoped(installID: "row-1", preservationIdentity: ""),
                                             contentFingerprint: "vc1-a"))
    }

    @Test("구성요소 경계가 달라지면 다른 ID 다")
    func legacyVersionIDComponentBoundaries() {
        let first = LegacyVersionID.make(kind: .legacyImport,
                                         source: .deviceScoped(installID: "ab", preservationIdentity: "c"),
                                         contentFingerprint: "vc1-a")
        let second = LegacyVersionID.make(kind: .legacyImport,
                                          source: .deviceScoped(installID: "a", preservationIdentity: "bc"),
                                          contentFingerprint: "vc1-a")

        #expect(first != second)
    }
}
