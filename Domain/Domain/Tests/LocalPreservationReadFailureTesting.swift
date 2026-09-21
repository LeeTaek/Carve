//
//  LocalPreservationReadFailureTesting.swift
//  DomainTest
//
//  초안을 읽지 못하는 **실제** 상황 — 깨진 파일 · 권한 · 폴더 오류 (정책 §12-6 구현 순서 ②, 10차 리뷰 1).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 깨진 초안 파일 · 읽지 못하는 폴더를 "초안 없음" 으로 넘겨, 보이지 않는 초안 위에 같은 키 · 더 새 revision 의 초안을 덮는 것
///   (초안 전용 세션에서는 그것이 유일한 사본이다)
/// - 묶음 폴더가 **없는 것**(아직 초안을 쓴 적 없음)과 **보지 못하는 것**(권한 · 입출력 오류)을 같이 다루는 것
/// - 다른 장의 깨진 초안 때문에 멀쩡한 장까지 막는 것
/// - 같은 키의 읽지 못하는 초안을 새 초안으로 덮어 없애는 것
///
/// 모의로 던지는 대역이 아니라 **실제 파일**을 깨뜨리고 권한을 내려 본다 — 삼키는 자리는 대역으로는 드러나지 않는다.
@Suite("로컬 보존 — 초안을 읽지 못함")
struct LocalPreservationReadFailureTesting {

    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let account = AccountScope(key: "acct-a")

    private struct Areas {
        let preservation: PreservationArea
        let eraseState: EraseStateArea
    }

    private func withAreas(_ body: (Areas) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("writer-read-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(Areas(
            preservation: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        ))
    }

    private func draft(verse: Int = 1, revision: Int = 1, session: String = "session-1", chapter: BibleChapter? = nil) -> VerseDraft {
        VerseDraft(
            key: VerseDraftKey(sessionID: session, chapter: chapter ?? self.chapter, verse: verse),
            revision: revision,
            rowID: BibleDrawingRowID(raw: "row-\(verse)"),
            lineData: Data("획-\(verse)".utf8),
            drawingVersion: 3,
            layoutMetadataData: nil,
            base: .empty,
            baseFingerprint: nil,
            account: .confirmed(AccountServerWorkToken(scope: account, generation: 1)),
            knownEpochs: [],
            storeOwnership: nil,
            eraseGeneration: 0,
            savedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    /// 그 초안이 놓이는 파일 자리 — 저장소가 쓰는 규칙(묶음 / 세션 / 파일)과 같다.
    private func fileURL(_ areas: Areas, _ draft: VerseDraft) -> URL {
        areas.preservation.draftsDirectory
            .appendingPathComponent(account.key, isDirectory: true)
            .appendingPathComponent(draft.key.sessionID, isDirectory: true)
            .appendingPathComponent(draft.key.fileName)
    }

    private func permissions(_ url: URL, _ value: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: value], ofItemAtPath: url.path)
    }

    // MARK: - 깨진 파일

    @Test("그 장의 초안 파일이 깨졌으면 빈 목록이 아니라 던진다 — 잘린 JSON · 빈 파일 · 다른 모양 · 쓰레기 바이트")
    func corruptDraftFileThrows() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            _ = try await writer.saveDraft(draft(verse: 1))
            let second = draft(verse: 2)
            _ = try await writer.saveDraft(second)
            let url = fileURL(areas, second)
            let original = try Data(contentsOf: url)

            let broken: [String: Data] = [
                "잘린 JSON": original.prefix(original.count / 2),
                "빈 파일": Data(),
                "다른 모양": Data("{}".utf8),
                "쓰레기 바이트": Data([0xFF, 0x00, 0x13, 0x37])
            ]
            for (name, bytes) in broken {
                try bytes.write(to: url)
                await #expect(throws: (any Error).self, "\(name) 을 읽고도 넘어갔다") {
                    try await writer.drafts(in: account, chapter: chapter)
                }
                await #expect(throws: (any Error).self, "\(name) — 묶음 전체 읽기") {
                    try await writer.drafts(in: account)
                }
            }

            // 되돌리면 다시 읽힌다 — 막는 것은 "읽지 못하는 동안" 뿐이다.
            try original.write(to: url)
            #expect(try await writer.drafts(in: account, chapter: chapter).map(\.key.verse) == [1, 2])
        }
    }

    @Test("파일 자리에 폴더가 있거나 파일을 열 수 없어도 던진다")
    func unreadableDraftEntryThrows() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            _ = try await writer.saveDraft(draft(verse: 1))
            // 파일 이름 자리에 폴더가 있다(쓰다 끊긴 자리 · 잘못된 복원).
            let asDirectory = fileURL(areas, draft(verse: 2))
            try FileManager.default.createDirectory(at: asDirectory, withIntermediateDirectories: true)
            await #expect(throws: (any Error).self) { try await writer.drafts(in: account, chapter: chapter) }
            try FileManager.default.removeItem(at: asDirectory)

            // 파일을 열 권한이 없다.
            let locked = fileURL(areas, draft(verse: 1))
            try permissions(locked, 0o000)
            defer { try? permissions(locked, 0o644) }
            await #expect(throws: (any Error).self) { try await writer.drafts(in: account, chapter: chapter) }
        }
    }

    // MARK: - 폴더

    @Test("세션 폴더 · 묶음 폴더를 읽지 못하면 던진다 — 폴더가 없을 때만 빈 목록이다")
    func unreadableDirectoryThrows() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            _ = try await writer.saveDraft(draft(verse: 1))
            let bucket = areas.preservation.draftsDirectory.appendingPathComponent(account.key, isDirectory: true)
            let session = bucket.appendingPathComponent("session-1", isDirectory: true)

            try permissions(session, 0o000)
            await #expect(throws: LocalPreservationWriter.WriterError.draftsUnreadable(account.key)) {
                try await writer.drafts(in: account, chapter: chapter)
            }
            try permissions(session, 0o755)

            try permissions(bucket, 0o000)
            await #expect(throws: LocalPreservationWriter.WriterError.draftsUnreadable(account.key)) {
                try await writer.drafts(in: account, chapter: chapter)
            }
            try permissions(bucket, 0o755)

            // 묶음 폴더의 부모를 보지 못해도 "없음" 이 아니다.
            try permissions(areas.preservation.draftsDirectory, 0o000)
            await #expect(throws: LocalPreservationWriter.WriterError.draftsUnreadable(account.key)) {
                try await writer.drafts(in: account, chapter: chapter)
            }
            try permissions(areas.preservation.draftsDirectory, 0o755)

            #expect(try await writer.drafts(in: account, chapter: chapter).count == 1)
        }
    }

    @Test("묶음 폴더가 아직 없으면 빈 목록이고, 그 자리에 파일이 있으면 던진다")
    func missingBucketIsEmptyButFileIsUnreadable() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            #expect(try await writer.drafts(in: account, chapter: chapter).isEmpty)

            let bucket = areas.preservation.draftsDirectory.appendingPathComponent(account.key, isDirectory: true)
            try FileManager.default.createDirectory(at: areas.preservation.draftsDirectory, withIntermediateDirectories: true)
            try Data("파일이 폴더 자리에 있다".utf8).write(to: bucket)
            await #expect(throws: LocalPreservationWriter.WriterError.draftsUnreadable(account.key)) {
                try await writer.drafts(in: account, chapter: chapter)
            }
        }
    }

    @Test("다른 장의 깨진 초안은 이 장을 막지 않는다 — 파일 이름으로 거르고 열지 않는다")
    func otherChapterCorruptionDoesNotBlockThisChapter() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let other = BibleChapter(title: .genesis, chapter: 11)
            _ = try await writer.saveDraft(draft(verse: 1))
            let otherDraft = draft(verse: 1, chapter: other)
            _ = try await writer.saveDraft(otherDraft)
            try Data("깨짐".utf8).write(to: fileURL(areas, otherDraft))

            #expect(try await writer.drafts(in: account, chapter: chapter).map(\.key.verse) == [1])
            await #expect(throws: (any Error).self) { try await writer.drafts(in: account, chapter: other) }
        }
    }

    // MARK: - 덮지 않기

    @Test("같은 키의 읽지 못하는 초안은 덮지 않고 옆으로 옮겨 남긴다 — 새 초안은 그대로 읽힌다")
    func unreadableSameKeyDraftIsSetAside() async throws {
        try await withAreas { areas in
            let writer = LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState)
            let first = draft(verse: 1, revision: 1)
            _ = try await writer.saveDraft(first)
            let url = fileURL(areas, first)
            let brokenBytes = Data("깨진 초안 — ④ 에서 복구한다".utf8)
            try brokenBytes.write(to: url)

            #expect(try await writer.saveDraft(draft(verse: 1, revision: 2)) == .written)

            let remaining = try await writer.drafts(in: account, chapter: chapter)
            #expect(remaining.map(\.revision) == [2])
            let sessionDirectory = url.deletingLastPathComponent()
            let files = try FileManager.default.contentsOfDirectory(at: sessionDirectory, includingPropertiesForKeys: nil)
            let asideURL = try #require(files.first { $0.lastPathComponent.contains("unreadable-") })
            // 깨진 바이트가 그대로 남아 있다 — 지우지도, 덮지도 않았다.
            #expect(try Data(contentsOf: asideURL) == brokenBytes)
        }
    }
}
