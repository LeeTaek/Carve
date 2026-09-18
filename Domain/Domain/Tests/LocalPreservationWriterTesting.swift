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
            let outcome = try await writer.saveDraft(next, superseding: [old.key, next.key])
            #expect(outcome == .written)

            let remaining = try await writer.drafts(in: account, chapter: chapter)
            #expect(remaining.map { "\($0.key.verse)/\($0.key.sessionID)" } == ["1/session-new", "2/session-old"])
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
            let outcome = try await writer.saveDraft(late, superseding: [old.key])
            #expect(outcome == .rejectedByErase(current: 1))
            let remaining = try await writer.drafts(in: account, chapter: chapter)
            #expect(remaining.isEmpty)
        }
    }
}
