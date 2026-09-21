//
//  LocalPreservationWriterTesting.swift
//  DomainTest
//
//  초안 · 격리 쓰기와 전체 삭제의 직렬화 경계 — 삭제 뒤의 늦은 쓰기를 영속 세대로 거절한다 (정책 §12-6 구현 순서 ②).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 사용자가 전체 삭제를 끝낸 뒤 늦게 도착한 격리 · 초안 쓰기가 사본을 다시 남기는 것(effect 취소로는 진행 중인 파일 쓰기를 막지 못한다)
/// - 앱을 다시 켜면 삭제 세대를 잊어 오래된 쓰기 · 작업을 받아들이는 것
/// - 전체 삭제가 중간에 끊겨 보존 폴더가 반쯤 남는 것
/// - 이어받을 때 보지 않은 더 새 revision 을 지우는 것
/// - 저장소에 들어간 표식이 아직 저장소에 없는 더 새 revision 을 덮는 것
/// - 시작할 때 한 번 못 읽은 삭제 세대 때문에 이 실행 내내 초안을 읽지도 쓰지도 못하는 것
@Suite("로컬 보존 직렬화 경계")
struct LocalPreservationWriterTesting {

    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let account = AccountScope(key: "acct-a")

    private struct Areas {
        let preservation: PreservationArea
        let eraseState: EraseStateArea
    }

    private func withAreas(_ body: (Areas) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("writer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(Areas(
            preservation: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        ))
    }

    private func draft(
        verse: Int = 1,
        revision: Int = 1,
        generation: UInt64 = 0,
        session: String = "session-1",
        ink: String = "획",
        chapter: BibleChapter? = nil
    ) -> VerseDraft {
        VerseDraft(
            key: VerseDraftKey(sessionID: session, chapter: chapter ?? self.chapter, verse: verse),
            revision: revision,
            rowID: BibleDrawingRowID(raw: "row-\(verse)"),
            lineData: Data(ink.utf8),
            drawingVersion: 3,
            layoutMetadataData: nil,
            base: .empty,
            baseFingerprint: nil,
            account: .confirmed(AccountServerWorkToken(scope: account, generation: 1)),
            knownEpochs: [],
            storeOwnership: nil,
            eraseGeneration: generation,
            savedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func environment(eraseGeneration: UInt64) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(account), serverWork: AccountServerWorkToken(scope: account, generation: 1),
            knowledge: EraseEpochKnowledge(), eraseGeneration: eraseGeneration
        )
    }

    // MARK: - 초안

    @Test("초안을 저장하고, 더 새 revision 을 옛 쓰기로 덮지 않으며, 그 revision 일 때만 지운다")
    func draftsKeepTheLatestRevision() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)

            #expect(try await writer.saveDraft(draft(revision: 2, ink: "새")) == .written)
            // 늦게 도착한 옛 revision 은 덮지 않는다.
            #expect(try await writer.saveDraft(draft(revision: 1, ink: "옛")) == .written)
            #expect(try await writer.drafts(in: account).map(\.lineData) == [Data("새".utf8)])

            // 확정 · 격리를 마친 revision 이 아니면 지우지 않는다.
            try await writer.removeDraft(draft().key, scope: account, ifRevision: 1)
            #expect(try await writer.drafts(in: account).count == 1)
            try await writer.removeDraft(draft().key, scope: account, ifRevision: 2)
            #expect(try await writer.drafts(in: account).isEmpty)
        }
    }

    // MARK: - 전체 삭제와 늦은 쓰기

    @Test("전체 삭제는 세대를 올리고 보존 영역을 지우며, 삭제 전 세대에 기댄 늦은 초안 · 격리를 거절한다")
    func eraseRejectsLateWrites() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            #expect(try await writer.saveDraft(draft()) == .written)

            let next = try await writer.eraseAllLocal()

            #expect(next == 1)
            #expect(!FileManager.default.fileExists(atPath: areas.preservation.storeDirectory.path))
            #expect(try await writer.saveDraft(draft(revision: 2)) == .rejectedByErase(current: 1))
            let item = DrawingQuarantineItem(chapter: chapter, verse: 1, revision: 2, lineData: Data("획".utf8), drawingVersion: 3,
                                             layoutMetadataData: nil)
            #expect(try await writer.quarantine([item], environment: environment(eraseGeneration: 0), batchID: "b", deviceID: "d")
                == .rejectedByErase(current: 1))
            #expect(!FileManager.default.fileExists(atPath: areas.preservation.recoveryCopiesDirectory.path))
            // 새 세대에 기댄 쓰기는 받는다.
            #expect(try await writer.saveDraft(draft(revision: 3, generation: 1)) == .written)
        }
    }

    /// 재시작 뒤 메모리 값이 사라지면 오래된 쓰기 · 작업을 다시 받아들인다.
    @Test("삭제 세대는 다시 켜도 남는다")
    func generationSurvivesRelaunch() async throws {
        try await withAreas { areas in
            let first = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            try await first.eraseAllLocal()

            let relaunched = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)

            #expect(await relaunched.currentGeneration() == 1)
            #expect(try await relaunched.saveDraft(draft(generation: 0)) == .rejectedByErase(current: 1))
        }
    }

    @Test("격리를 직렬화 경계로 하면 세션이 기댄 세대 뒤의 전체 삭제를 실패로 알린다")
    func writerQuarantineClientReportsRejection() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let client = WriterDrawingQuarantine(writer: writer, deviceID: "device-1")
            let item = DrawingQuarantineItem(chapter: chapter, verse: 1, revision: 1, lineData: Data("획".utf8), drawingVersion: 3,
                                             layoutMetadataData: nil)

            try await client.quarantine([item], environment: environment(eraseGeneration: 0), batchID: "b")
            #expect(try FileRecoveryCopyStore(root: areas.preservation.recoveryCopiesDirectory).entries(accountScope: account.key).count == 1)

            try await writer.eraseAllLocal()
            await #expect(throws: WriterDrawingQuarantine.RejectedByErase.self) {
                try await client.quarantine([item], environment: environment(eraseGeneration: 0), batchID: "b")
            }
            #expect(!FileManager.default.fileExists(atPath: areas.preservation.recoveryCopiesDirectory.path))
        }
    }

    // MARK: - 중간에 끊긴 삭제

    /// 세대를 올린 뒤 폴더를 지우기 전에 끊겼다. 남은 폴더는 표식의 세대가 낮다.
    @Test("세대를 올린 뒤 끊긴 삭제의 잔여는 다음 실행에서 지운다")
    func leftoverFromInterruptedEraseIsRemoved() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            #expect(try await writer.saveDraft(draft()) == .written)
            // 삭제가 세대 파일만 올리고 끊겼다.
            let generationURL = areas.eraseState.root.appendingPathComponent("Carve.sqlite", isDirectory: true)
                .appendingPathComponent("local-erase-generation.json")
            try FileManager.default.createDirectory(at: generationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(UInt64(1)).write(to: generationURL)

            let relaunched = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)

            #expect(await relaunched.currentGeneration() == 1)
            #expect(!FileManager.default.fileExists(atPath: areas.preservation.draftsDirectory.path))
        }
    }

    /// 원시 사본은 앱 시작 때 직렬화 경계보다 먼저 만들어져 표식이 없다. 표식이 없다고 지우면 원본을 잃는다.
    @Test("표식 없는 보존 폴더(원시 사본만 있음)는 지우지 않고 지금 세대 표식을 붙인다")
    func unmarkedDirectoryIsKept() async throws {
        try await withAreas { areas in
            let raw = areas.preservation.rawSnapshotsDirectory.appendingPathComponent("snapshot", isDirectory: true)
            try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
            try Data("원본".utf8).write(to: raw.appendingPathComponent("Carve.sqlite"))

            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            #expect(try await writer.saveDraft(draft()) == .written)

            #expect(FileManager.default.fileExists(atPath: raw.appendingPathComponent("Carve.sqlite").path))
            let marker = areas.preservation.storeDirectory.appendingPathComponent("local-generation.json")
            #expect(try JSONDecoder().decode(UInt64.self, from: Data(contentsOf: marker)) == 0)
        }
    }

    // MARK: - 세대를 읽지 못함

    /// 첫 잠금 해제 전 파일 보호 · 일시적인 입출력 오류는 지나간다. 초안을 읽지 못한 장의 「다시 시도」가 성공할 수 있어야 한다.
    @Test("시작할 때 삭제 세대를 읽지 못했어도, 다시 읽을 수 있게 되면 그 세대로 쓰기를 잇는다")
    func unreadableGenerationIsReadAgain() async throws {
        try await withAreas { areas in
            let generationURL = areas.eraseState.root.appendingPathComponent("Carve.sqlite", isDirectory: true)
                .appendingPathComponent("local-erase-generation.json")
            try FileManager.default.createDirectory(at: generationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("깨진 값".utf8).write(to: generationURL)
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            #expect(await writer.currentGeneration() == nil)
            await #expect(throws: LocalPreservationWriter.WriterError.self) { try await writer.drafts(in: account, chapter: chapter) }

            try JSONEncoder().encode(UInt64(2)).write(to: generationURL)

            #expect(await writer.currentGeneration() == 2)
            #expect(try await writer.saveDraft(draft(generation: 2)) == .written)
            // 삭제 전 세대에 기댄 쓰기는 여전히 거절한다.
            #expect(try await writer.saveDraft(draft(revision: 2, generation: 0)) == .rejectedByErase(current: 2))
        }
    }

    @Test("삭제 세대를 읽지 못하면 쓰기를 멈춘다 — 늦은 쓰기를 가려낼 수 없다")
    func unreadableGenerationStopsWrites() async throws {
        try await withAreas { areas in
            let generationURL = areas.eraseState.root.appendingPathComponent("Carve.sqlite", isDirectory: true)
                .appendingPathComponent("local-erase-generation.json")
            try FileManager.default.createDirectory(at: generationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("깨진 값".utf8).write(to: generationURL)

            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)

            #expect(await writer.currentGeneration() == nil)
            await #expect(throws: LocalPreservationWriter.WriterError.self) { try await writer.saveDraft(draft()) }
            await #expect(throws: LocalPreservationWriter.WriterError.self) { try await writer.eraseAllLocal() }
        }
    }

    @Test("초안은 묶음(계정 범위)마다 따로 읽힌다")
    func draftsAreScopedByBucket() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            var unverified = draft(verse: 2)
            unverified.account = .unverified(hint: account)
            let savedConfirmed = try await writer.saveDraft(draft())
            let savedUnverified = try await writer.saveDraft(unverified)
            #expect(savedConfirmed == .written)
            #expect(savedUnverified == .written)

            let confirmedDrafts = try await writer.drafts(in: account)
            let unverifiedDrafts = try await writer.drafts(in: .unverified)
            #expect(confirmedDrafts.map(\.key.verse) == [1])
            #expect(unverifiedDrafts.map(\.key.verse) == [2])
        }
    }

    // MARK: - ②-2 장 단위 조회 · 이어받은 초안

    @Test("장 단위로 읽으면 그 장의 초안만 준다 — 다른 장 · 다른 권은 열지 않는다")
    func draftsFilteredByChapter() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let otherChapter = BibleChapter(title: .genesis, chapter: 11)
            let otherBook = BibleChapter(title: .exodus, chapter: 1)
            for item in [draft(verse: 2), draft(verse: 1, session: "session-2"), draft(verse: 1, chapter: otherChapter),
                         draft(verse: 1, chapter: otherBook)] {
                let outcome = try await writer.saveDraft(item)
                #expect(outcome == .written)
            }

            let found = try await writer.drafts(in: account, chapter: chapter)
            #expect(found.map { "\($0.key.verse)/\($0.key.sessionID)" } == ["1/session-2", "2/session-1"])
            let eleven = try await writer.drafts(in: account, chapter: otherChapter)
            #expect(eleven.map(\.key.chapter) == [11])
        }
    }

    @Test("이어받은 다른 세션의 초안은 새 초안을 쓴 뒤에 지우고, 같은 세션 키는 지우지 않는다")
    func supersededDraftsAreRemovedAfterWriting() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let old = draft(verse: 1, session: "session-old", ink: "옛")
            let untouched = draft(verse: 2, session: "session-old", ink: "다른 절")
            _ = try await writer.saveDraft(old)
            _ = try await writer.saveDraft(untouched)

            let next = draft(verse: 1, session: "session-new", ink: "이어 씀")
            let outcome = try await writer.saveDraft(next, superseding: [old.ref, next.ref])
            #expect(outcome == .written)

            let remaining = try await writer.drafts(in: account, chapter: chapter)
            #expect(remaining.map { "\($0.key.verse)/\($0.key.sessionID)" } == ["1/session-new", "2/session-old"])
        }
    }

    /// 닫은 세션의 늦은 편집이 같은 키를 더 새 revision 으로 덮은 뒤, 새 세션이 앞서 본 revision 을 이어받는 경우다.
    @Test("이어받을 때 본 revision 이 아니면 대신하지 않는다 — 그 사이 쓰인 더 새 revision 을 남긴다")
    func supersedingChecksRevision() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let shown = draft(verse: 1, revision: 1, session: "session-old", ink: "본 것")
            _ = try await writer.saveDraft(shown)
            _ = try await writer.saveDraft(draft(verse: 1, revision: 2, session: "session-old", ink: "늦은 편집"))

            let next = draft(verse: 1, revision: 3, session: "session-new", ink: "이어 씀")
            #expect(try await writer.saveDraft(next, superseding: [shown.ref]) == .written)

            let remaining = try await writer.drafts(in: account, chapter: chapter)
            #expect(remaining.map { "\($0.key.sessionID)/\($0.revision)" } == ["session-new/3", "session-old/2"])
        }
    }

    @Test("저장소에 들어간 표식은 그 revision 까지만 남기고, 더 새 revision 은 건드리지 않으며, 지우지 않는다")
    func markStoredKeepsNewerRevisions() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            _ = try await writer.saveDraft(draft(verse: 1, revision: 3))
            _ = try await writer.saveDraft(draft(verse: 2, revision: 5))

            try await writer.markDraftStored(draft(verse: 1).key, scope: account, throughRevision: 3)
            try await writer.markDraftStored(draft(verse: 2).key, scope: account, throughRevision: 4)

            let found = try await writer.drafts(in: account, chapter: chapter)
            #expect(found.map(\.storeState) == [.stored, nil])
            #expect(found.map(\.revision) == [3, 5])
            // 표식을 단 초안 위에 더 새 revision 이 오면 표식 없는 새 초안이 된다.
            _ = try await writer.saveDraft(draft(verse: 1, revision: 6))
            #expect(try await writer.drafts(in: account, chapter: chapter).first?.storeState == nil)
        }
    }

    /// 표식만으로는 "무엇을 넣었는지" 를 모른다 — 계정 전환으로 그 행이 앞서 넣은 내용으로 돌아왔을 때 가릴 수 있어야 한다(ACC-1 2차 ⑪).
    @Test("저장소에 넣은 내용의 지문을 초안에 남기고, 다음 revision 도 그 기록을 이어받는다")
    func markStoredRecordsSentFingerprints() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let first = draft(verse: 1, revision: 1, ink: "처음")
            _ = try await writer.saveDraft(first)
            try await writer.markDraftStored(first.key, scope: account, throughRevision: 1)
            let firstSent = try #require(first.contentFingerprint)
            #expect(try await writer.drafts(in: account, chapter: chapter).first?.sentFingerprints == [firstSent])

            // 다음 revision 은 그 기록을 이어받고(아직 넣기 전), 넣고 나면 자기 내용을 앞에 더한다.
            let second = draft(verse: 1, revision: 2, ink: "고침")
            let secondSent = try #require(second.contentFingerprint)
            _ = try await writer.saveDraft(second)
            #expect(try await writer.drafts(in: account, chapter: chapter).first?.sentFingerprints == [firstSent])
            try await writer.markDraftStored(second.key, scope: account, throughRevision: 2)
            let after = try #require(try await writer.drafts(in: account, chapter: chapter).first)
            #expect(after.sentFingerprints == [secondSent, firstSent])
            #expect(after.storeState == .stored)
        }
    }

    /// 저장이 끝나기 전에 다음 편집이 초안을 덮으면, 그 저장의 내용은 파일에 남지 않는다. 그래도 **무엇을 넣었는지**는 남아야 한다(11차 리뷰 P1).
    @Test("파일이 더 새 revision 이어도 넣은 내용의 지문은 남기고, 표식은 그 revision 까지만 단다")
    func sentFingerprintIsRecordedEvenWhenFileMovedOn() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let first = draft(verse: 1, revision: 1, ink: "처음")
            _ = try await writer.saveDraft(first)
            // 다음 편집이 먼저 초안을 덮었다.
            _ = try await writer.saveDraft(draft(verse: 1, revision: 2, ink: "다음"))

            let firstSent = try #require(first.contentFingerprint)
            try await writer.markDraftStored(first.key, scope: account, throughRevision: 1, contentFingerprint: firstSent)

            let kept = try #require(try await writer.drafts(in: account, chapter: chapter).first)
            #expect(kept.revision == 2)
            #expect(kept.sentFingerprints == [firstSent])
            // 파일의 내용(revision 2)은 아직 저장소에 없다 — 표식을 달지 않는다.
            #expect(kept.storeState == nil)
        }
    }

    /// 다른 세션이 초안을 이어받으면 그 파일은 지워진다. 넣었던 지문까지 사라지면 복구 후보 판정의 근거가 끊긴다(11차 리뷰 P1).
    @Test("이어받은 초안이 저장소에 넣었던 지문을 새 초안이 물려받는다")
    func supersedingCarriesSentFingerprints() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let old = draft(verse: 1, revision: 1, session: "session-old", ink: "앞선 세션")
            _ = try await writer.saveDraft(old)
            let oldSent = try #require(old.contentFingerprint)
            try await writer.markDraftStored(old.key, scope: account, throughRevision: 1, contentFingerprint: oldSent)

            let next = draft(verse: 1, revision: 2, session: "session-new", ink: "이어 씀")
            #expect(try await writer.saveDraft(next, superseding: [VerseDraftRef(key: old.key, revision: 1)]) == .written)

            let remaining = try await writer.drafts(in: account, chapter: chapter)
            #expect(remaining.map(\.key.sessionID) == ["session-new"])
            #expect(remaining.first?.sentFingerprints == [oldSent])
        }
    }

    @Test("전체 삭제 뒤의 늦은 초안은 이어받은 초안도 지우지 않는다")
    func rejectedDraftKeepsSupersededOne() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let old = draft(verse: 1, session: "session-old")
            _ = try await writer.saveDraft(old)
            // 세대 0 에 기댄 쓰기가 전체 삭제(세대 1) 뒤에 도착한다. 삭제가 이미 옛 초안까지 지웠으므로 남은 것이 없어야 한다.
            try await writer.eraseAllLocal()
            let late = draft(verse: 1, generation: 0, session: "session-new")
            let outcome = try await writer.saveDraft(late, superseding: [old.ref])
            #expect(outcome == .rejectedByErase(current: 1))
            let remaining = try await writer.drafts(in: account, chapter: chapter)
            #expect(remaining.isEmpty)
        }
    }
}

// MARK: - 재실행 복구 (2026-09-21 후속 리뷰 P1-6)

extension LocalPreservationWriterTesting {
    /// 2026-09-21 후속 리뷰 P1-6 — 예전 `.sending` 시험은 같은 writer 로 다시 읽을 뿐이라, 앱이 끝나고 **새 프로세스가 파일에서 다시 읽는**
    /// 경로를 보지 않았다. 제품에 중단 훅을 넣지 않고, "보내는 중" 초안을 남긴 writer 를 버린 뒤 같은 영역에 새 writer 를 연다
    /// (`generationSurvivesRelaunch` 와 같은 방식).
    @Test("보내는 중 표식을 남기고 끝난 초안은 재실행 뒤에도 그대로 한 벌 남고, 그 행이 바뀌었으면 저장 완료 불확실로 판정된다")
    func sendingDraftSurvivesRelaunchAsUncertain() async throws {
        try await withAreas { areas in
            let metadata = try DrawingLayoutMetadata(
                baseWritingWidth: 320, baseWritingHeight: 30, baseUnderlineAnchors: [0], layoutSignature: "cl1-relaunch"
            ).encodedBlob()
            var sending = draft(verse: 3, revision: 4, ink: "보내던 필기")
            sending.layoutMetadataData = metadata
            sending.base = .legacy(rowID: sending.rowID, contentFingerprint: "vc1-before")
            sending.baseFingerprint = "vc1-before"
            sending.storeState = .sending
            // 앞선 실행 — 초안을 "보내는 중" 으로 남긴 뒤, 저장소 저장 · 표식 전에 끝났다.
            do {
                let beforeCrash = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
                #expect(try await beforeCrash.saveDraft(sending) == .written)
            }

            let relaunched = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let recovered = try await relaunched.drafts(in: account, chapter: chapter)

            // 무손실 · 무중복 — 그 초안이 파일에서 한 벌만, 표식 · 내용 그대로 돌아온다.
            #expect(recovered == [sending])
            #expect(try await relaunched.draftSummary(in: account).draftCount == 1)

            // 그 사이 그 행이 다른 내용으로 바뀌었다(다른 기기 · 지우기) — 들어갔는지 가릴 수 없다.
            let movedRow = VerseDrawingSnapshot(
                verse: 3, rowID: sending.rowID, isPresent: true, updateDate: nil, lineData: Data("다른 기기".utf8), drawingVersion: 3, metadata: nil
            )
            let view = VerseDraftStoreView(snapshots: [movedRow])
            let plan = VerseDraftRecoveryRule.plan(
                drafts: recovered, storeContent: view.verseContent, environment: environment(eraseGeneration: 0), sessionID: "after-relaunch",
                storeRows: view.rows
            )
            #expect(plan.uncertain == [sending])
            #expect(plan.kept == [sending])
            #expect(plan.shown.isEmpty)
            #expect(plan.settled.isEmpty)

            // 그 행이 초안 내용 그대로면 들어간 것이다 — 겹치지 않고(중복 없음) 정리 대상으로만 남긴다. 지우지 않는다.
            let landedRow = VerseDrawingSnapshot(
                verse: 3, rowID: sending.rowID, isPresent: true, updateDate: nil, lineData: sending.lineData, drawingVersion: 3,
                metadata: DrawingLayoutMetadata.decode(blob: metadata)
            )
            let landed = VerseDraftStoreView(snapshots: [landedRow])
            let settled = VerseDraftRecoveryRule.plan(
                drafts: recovered, storeContent: landed.verseContent, environment: environment(eraseGeneration: 0), sessionID: "after-relaunch",
                storeRows: landed.rows
            )
            #expect(settled.settled == [sending])
            #expect(settled.shown.isEmpty)
            #expect(try await relaunched.drafts(in: account, chapter: chapter) == [sending])
        }
    }
}
