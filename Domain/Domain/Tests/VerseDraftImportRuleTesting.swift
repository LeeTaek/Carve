//
//  VerseDraftImportRuleTesting.swift
//  DomainTest
//
//  「확인이 필요한 필기」 의 가져오기 판정 — 넣기 · 바꾸기 · 이미 반영됨 · 묻기, 연결 전 필기, 보관만 하는 예전 필기 (2026-09-29).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 지웠던 절이나 모든 필사 삭제 뒤의 필기를 **묻지 않고** 다시 넣는 것
/// - 좌표 정보가 없어 놓을 자리를 모르는 필기를 넣을 수 있다고 보이는 것
/// - 다른 계정을 참고하던 확인 전 필기를 지금 계정으로 가져오게 여는 것(P0-1)
/// - 가져온 뒤 그 절을 이어 고치면 가져온 초안이 다시 「확인이 필요한 필기」 로 오르는 것
/// - 저장을 마친 내 예전 수정본이 확인이 필요한 것으로 쌓이는 것(사용자 결정 2026-09-29 — 접어 둔다)
@Suite("가져오기 판정")
struct VerseDraftImportRuleTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let accountA = AccountScope(key: "acct-a")
    private let accountB = AccountScope(key: "acct-b")
    private static let metadata = DrawingLayoutMetadata(
        baseWritingWidth: 320, baseWritingHeight: 30, baseUnderlineAnchors: [0], layoutSignature: "cl1-import-rule"
    )
    private static let metadataBlob = try? metadata.encodedBlob()

    // MARK: - 표본

    private func confirmed(_ scope: AccountScope, knowledge: EraseEpochKnowledge? = EraseEpochKnowledge()) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope), serverWork: AccountServerWorkToken(scope: scope, generation: 3), knowledge: knowledge,
            storeOwnership: scope
        )
    }

    private func fingerprint(_ ink: String) -> String {
        VerseContentFingerprint.make(lineData: Data(ink.utf8), drawingVersion: 3, layoutMetadataBlob: Self.metadataBlob)
    }

    private func draft(
        verse: Int = 1,
        session: String = "old",
        ink: String? = "획",
        baseInk: String? = "옛",
        account: VerseEditAccountBasis? = nil,
        knownEpochs: Set<String>? = [],
        savedAt: TimeInterval = 1_000,
        storeState: VerseDraftStoreState? = nil,
        sent: [String]? = nil,
        imported: BibleDrawingRowID? = nil,
        withMetadata: Bool = true
    ) -> VerseDraft {
        let row = BibleDrawingRowID(raw: "row-\(verse)")
        return VerseDraft(
            key: VerseDraftKey(sessionID: session, chapter: chapter, verse: verse),
            revision: 1,
            rowID: row,
            lineData: ink.map { Data($0.utf8) },
            drawingVersion: ink == nil ? nil : 3,
            layoutMetadataData: ink != nil && withMetadata ? Self.metadataBlob : nil,
            base: baseInk.map { .legacy(rowID: row, contentFingerprint: fingerprint($0)) } ?? .empty,
            baseFingerprint: baseInk.map { fingerprint($0) },
            account: account ?? .confirmed(AccountServerWorkToken(scope: accountA, generation: 1)),
            knownEpochs: knownEpochs,
            storeOwnership: nil,
            eraseGeneration: 0,
            savedAt: Date(timeIntervalSince1970: savedAt),
            storeState: storeState,
            sentFingerprints: sent,
            imported: imported.map { VerseDraftImport(rowID: $0, contentFingerprint: nil, account: accountA, importedAt: Date(timeIntervalSince1970: 3_000)) }
        )
    }

    /// 저장소의 한 행. 필기가 있으면 초안과 같은 좌표 정보가 붙는다 — 지문이 같은 규칙으로 만들어진다.
    private func snapshot(
        verse: Int = 1, rowID: String? = nil, ink: String?, isPresent: Bool = true, updatedAt: TimeInterval = 500
    ) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: rowID ?? "row-\(verse)"), isPresent: isPresent,
            updateDate: Date(timeIntervalSince1970: updatedAt), lineData: ink.map { Data($0.utf8) }, drawingVersion: ink == nil ? nil : 3,
            metadata: ink == nil ? nil : Self.metadata
        )
    }

    private func plan(_ drafts: [VerseDraft], snapshots: [VerseDrawingSnapshot], environment: DrawingEditEnvironment? = nil) -> VerseDraftRecoveryPlan {
        let view = VerseDraftStoreView(snapshots: snapshots)
        return VerseDraftRecoveryRule.plan(
            drafts: drafts, storeContent: view.verseContent, environment: environment ?? confirmed(accountA), sessionID: nil,
            storeRows: view.rows, storeHistory: view.history
        )
    }

    // MARK: - 가져오면 무엇이 되는가

    @Test("그 절에 행이 없거나 비운 행이면 넣기, 다른 필기가 있으면 바꾸기, 같은 필기면 이미 반영됨이다")
    func actionFollowsTheCurrentVerse() {
        let mine = draft(ink: "가져올 것")
        let knowledge = EraseEpochKnowledge()

        let noRow = VerseDraftImportRule.check(draft: mine, current: nil, knowledge: knowledge)
        #expect(noRow == VerseDraftImportCheck(action: .insert, caution: nil, currentFingerprint: nil))

        let clearedBefore = VerseDraftImportRule.check(draft: mine, current: snapshot(ink: nil, updatedAt: 500), knowledge: knowledge)
        #expect(clearedBefore == VerseDraftImportCheck(action: .insert, caution: nil, currentFingerprint: nil))

        let other = VerseDraftImportRule.check(draft: mine, current: snapshot(ink: "지금 필기"), knowledge: knowledge)
        #expect(other == VerseDraftImportCheck(action: .replace, caution: nil, currentFingerprint: fingerprint("지금 필기")))

        let same = VerseDraftImportRule.check(draft: mine, current: snapshot(ink: "가져올 것"), knowledge: knowledge)
        #expect(same.action == .alreadyApplied)
        #expect(same.caution == nil)
    }

    @Test("좌표 정보가 없어 놓을 자리를 모르는 필기는 넣을 수 없다")
    func undisplayableDraftCannotBeImported() {
        let lost = draft(ink: "좌표 없음", withMetadata: false)
        let check = VerseDraftImportRule.check(draft: lost, current: snapshot(ink: "지금 필기"), knowledge: EraseEpochKnowledge())
        #expect(check.action == .unavailable)
    }

    @Test("이 필기를 쓴 뒤 그 절이 비워졌으면 넣기 전에 묻는다 — 비운 때가 앞서면 묻지 않는다")
    func verseClearedAfterTheDraftAsksFirst() {
        let mine = draft(ink: "가져올 것", savedAt: 1_000)
        let clearedAfter = VerseDraftImportRule.check(draft: mine, current: snapshot(ink: nil, updatedAt: 2_000), knowledge: EraseEpochKnowledge())
        #expect(clearedAfter == VerseDraftImportCheck(action: .insert, caution: .verseClearedAfterDraft, currentFingerprint: nil))

        let clearedBefore = VerseDraftImportRule.check(draft: mine, current: snapshot(ink: nil, updatedAt: 900), knowledge: EraseEpochKnowledge())
        #expect(clearedBefore.caution == nil)
    }

    @Test("삭제 기준점을 읽지 못했거나 이 필기가 모른 채 쓰였으면 묻고, 이 필기가 모르던 삭제를 지금 계정이 알면 그것을 알린다")
    func eraseHistoryAsksFirst() {
        let current = snapshot(ink: "지금 필기")
        let learned = EraseEpochKnowledge(received: ["epoch-1"])

        #expect(VerseDraftImportRule.check(draft: draft(), current: current, knowledge: nil).caution == .eraseHistoryUnknown)
        #expect(VerseDraftImportRule.check(draft: draft(knownEpochs: nil), current: current, knowledge: learned).caution == .eraseHistoryUnknown)
        #expect(VerseDraftImportRule.check(draft: draft(knownEpochs: []), current: current, knowledge: learned).caution == .eraseAfterDraft)
        #expect(VerseDraftImportRule.check(draft: draft(knownEpochs: ["epoch-1"]), current: current, knowledge: learned).caution == nil)
        // 기기가 아는 삭제가 없으면 K 를 모른 채 쓴 필기도 판단할 것이 없다.
        #expect(VerseDraftImportRule.check(draft: draft(knownEpochs: nil), current: current, knowledge: EraseEpochKnowledge()).caution == nil)
    }

    // MARK: - 연결 전 필기

    @Test("확인된 계정에서만 연결 전 필기를 가져오기로 연다 — 다른 계정을 참고하던 필기와 화면에 오르는 필기는 아니다")
    func beforeConnectionDraftsAreThoseWithoutAnAccount() {
        let environment = confirmed(accountA)
        #expect(VerseDraftRecoveryRule.awaitsImport(draft(account: .localOnly), environment: environment))
        #expect(VerseDraftRecoveryRule.awaitsImport(draft(account: .unverified(hint: nil)), environment: environment))
        // 힌트가 지금 계정이면 편집 화면이 이미 보인다 — 가져오기로 따로 열지 않는다.
        #expect(!VerseDraftRecoveryRule.awaitsImport(draft(account: .unverified(hint: accountA)), environment: environment))
        #expect(VerseDraftRecoveryRule.reachesScreen(draft(account: .unverified(hint: accountA)), environment: environment))
        // 다른 계정을 참고하던 필기 · 다른 계정의 필기는 그 계정으로 돌아왔을 때 연다(P0-1).
        #expect(!VerseDraftRecoveryRule.awaitsImport(draft(account: .unverified(hint: accountB)), environment: environment))
        #expect(!VerseDraftRecoveryRule.awaitsImport(
            draft(account: .confirmed(AccountServerWorkToken(scope: accountB, generation: 1))), environment: environment
        ))
        #expect(environment.beforeConnectionDraftScopes == [.localOnly, .unverified])

        // 계정이 확인되지 않았으면 가져올 곳이 없다.
        let signedOut = DrawingEditEnvironment(accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge())
        #expect(!VerseDraftRecoveryRule.awaitsImport(draft(account: .localOnly), environment: signedOut))
        #expect(signedOut.beforeConnectionDraftScopes.isEmpty)
        #expect(!VerseDraftRecoveryRule.awaitsImport(draft(account: .unverified(hint: nil)), environment: .unknown))
    }

    @Test("연결 전 필기를 지금 저장소와 견준다 — 같은 필기 · 가져온 것은 끝났고, 이전 필사 기록에 같은 내용이면 예전 필기, 좌표가 없으면 표시 실패")
    func importPlanSortsBeforeConnectionDrafts() {
        let view = VerseDraftStoreView(snapshots: [
            snapshot(verse: 1, ink: "지금"),
            snapshot(verse: 1, rowID: "row-1-old", ink: "옛", isPresent: false, updatedAt: 100),
            snapshot(verse: 3, ink: "지금3"),
            snapshot(verse: 4, rowID: "row-imported", ink: "가져온 뒤 고침")
        ])
        let same = draft(verse: 1, session: "same", ink: "지금", account: .localOnly)
        let awaiting = draft(verse: 2, session: "awaiting", ink: "새", account: .localOnly)
        let inHistory = draft(verse: 1, session: "history", ink: "옛", account: .unverified(hint: nil))
        let undisplayable = draft(verse: 3, session: "lost", ink: "좌표 없음", account: .localOnly, withMetadata: false)
        let imported = draft(verse: 4, session: "imported", ink: "가져온 것", account: .localOnly, imported: BibleDrawingRowID(raw: "row-imported"))
        let importedRowGone = draft(verse: 5, session: "gone", ink: "가져왔던 것", account: .localOnly, imported: BibleDrawingRowID(raw: "row-gone"))

        let result = VerseDraftRecoveryRule.importPlan(drafts: [same, awaiting, inHistory, undisplayable, imported, importedRowGone], view: view)

        #expect(result.settled == [same, imported])
        #expect(result.awaiting == [awaiting, importedRowGone])
        #expect(result.archived == [inHistory])
        #expect(result.undisplayable == [undisplayable])
        #expect(result.needsConfirmation == [awaiting, importedRowGone, undisplayable])
    }

    // MARK: - 보관만 하는 예전 필기

    @Test("저장을 마친 뒤 그 절을 이어 고친 예전 수정본은 남기되 확인이 필요한 것에 넣지 않는다")
    func savedEarlierRevisionIsArchived() {
        let earlier = draft(ink: "예전 수정본", storeState: .stored, sent: [fingerprint("예전 수정본")])
        let result = plan([earlier], snapshots: [snapshot(ink: "이어 고친 것")])
        #expect(result.shown.isEmpty)
        #expect(result.kept == [earlier])
        #expect(result.archived == [earlier])
        #expect(result.needsConfirmation.isEmpty)
    }

    @Test("같은 내용이 이전 필사 기록에 있으면 예전 필기다 — 되살릴 수 있는 초안은 그 내용이 저장소에 있을 때만 그렇다")
    func contentInHistoryIsArchived() {
        // 저장한 적 없는 초안인데 같은 내용이 보관 행에 있다(다른 기기가 넣은 뒤 지웠다 등).
        let moved = draft(ink: "보관된 것", baseInk: "더 옛")
        let archivedRow = snapshot(rowID: "row-archive", ink: "보관된 것", isPresent: false, updatedAt: 100)
        let withHistory = plan([moved], snapshots: [snapshot(ink: nil, updatedAt: 800), archivedRow])
        #expect(withHistory.archived == [moved])

        // 되살릴 수 있는 초안 — 그 행이 앞서 넣은 내용으로 돌아와 이 내용은 저장소에서 사라졌다. 저장했던 내용이어도 확인이 필요하다.
        let recoverable = draft(ink: "그 뒤 편집", storeState: .stored, sent: [fingerprint("그 뒤 편집"), fingerprint("앞서 넣은 것")])
        let resumed = plan([recoverable], snapshots: [snapshot(ink: "앞서 넣은 것")])
        #expect(resumed.recoverable == [recoverable])
        #expect(resumed.archived.isEmpty)
        #expect(resumed.needsConfirmation == [recoverable])

        // 같은 내용이 이전 필사 기록에 있으면 그것도 예전 필기다.
        let resumedWithHistory = plan([recoverable], snapshots: [
            snapshot(ink: "앞서 넣은 것"), snapshot(rowID: "row-archive", ink: "그 뒤 편집", isPresent: false, updatedAt: 100)
        ])
        #expect(resumedWithHistory.archived == [recoverable])
    }

    @Test("저장 완료가 불확실한 초안과 저장한 적 없는 초안은 예전 필기가 아니다 — 표시 실패도 그 까닭 그대로다")
    func uncertainAndUnsentDraftsNeedConfirmation() {
        let sending = draft(session: "sending", ink: "보내던 것", storeState: .sending, sent: [fingerprint("보내던 것")])
        let unsent = draft(verse: 2, session: "unsent", ink: "쓴 것", baseInk: "더 옛")
        let result = plan([sending, unsent], snapshots: [snapshot(ink: "남이 넣음"), snapshot(verse: 2, ink: "옛2")])
        #expect(result.uncertain == [sending])
        #expect(result.archived.isEmpty)
        #expect(result.needsConfirmation == [sending, unsent])

        // 이어 볼 후보였는데 좌표 정보가 없다 — 표시 실패로 남고, 같은 내용이 저장소에 있다고 볼 수 없다.
        let lost = draft(verse: 3, session: "lost", ink: "좌표 없음", baseInk: nil, withMetadata: false)
        let lostResult = plan([lost], snapshots: [])
        #expect(lostResult.undisplayable == [lost])
        #expect(lostResult.archived.isEmpty)
        #expect(lostResult.needsConfirmation == [lost])
    }

    @Test("가져온 초안은 그 행이 남아 있는 동안 역할이 끝났다 — 그 절을 이어 고쳐도 다시 오르지 않고, 행이 사라지면 다시 판정한다")
    func importedDraftIsSettledWhileItsRowRemains() {
        let imported = draft(ink: "가져온 것", baseInk: "옛", imported: BibleDrawingRowID(raw: "row-imported"))
        let edited = plan([imported], snapshots: [snapshot(rowID: "row-imported", ink: "가져온 뒤 고침", updatedAt: 4_000)])
        #expect(edited.settled == [imported])
        #expect(edited.kept.isEmpty)

        // 가져온 행이 사라졌다(전송 전 계정 전환 — F29). 기록을 믿지 않고 다시 판정한다 — 기준이 달라 확인이 필요하다.
        let gone = plan([imported], snapshots: [snapshot(ink: "남이 넣음")])
        #expect(gone.settled.isEmpty)
        #expect(gone.needsConfirmation == [imported])
    }
}
