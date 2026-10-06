//
//  BackupRestoreTransactionTesting.swift
//  DomainTest
//
//  불러오기 복원 쓰기 — 장 하나의 트랜잭션: 세대 확인 · 쓰기 직전 재판정 · 대표 고정 · 쓰기 전 확인 (설계 §4-3 · §5-1, 오케스트레이터 결정 2026-10-06).
//

import Foundation
import Testing

@testable import Domain

/// 이 파일이 막는 것:
/// - 적용을 시작한 뒤 「모든 필사 삭제」 가 있었는데 옛 판정으로 써 지운 필사를 되살리는 것
/// - 판정한 뒤 같은 절에 들어온 필기를 모르고 백업 필기를 현재로 넣어 화면의 필사를 바꾸는 것
/// - 1.3.0 legacy 절(isPresent 가 모두 false)에 더 늦은 보관 행을 넣어 화면의 대표가 바뀌는 것, 행 없는 절에 빈 자리 행을 만드는 것
/// - 넣을 바이트가 빠졌는데 일부만 쓰는 것(비운 행으로 잘못 넣기 · 고정만 하기)
@Suite("불러오기 — 복원 쓰기")
struct BackupRestoreTransactionTesting {
    private typealias Sample = BackupRestoreSample

    /// 1.3.0 의 절 — 대표 L(9/10, isPresent false)과 그보다 이른 M(9/05, isPresent nil). 좌표 형식 1 · 메타데이터 없음.
    private let legacyL = BackupExportRowSeed(
        verse: 1, rowUUID: nil, businessID: "1-01Genesis.txt.1.1.1700000100", isPresent: false,
        creationDate: BackupRestoreSample.sep(10), updateDate: BackupRestoreSample.sep(10), drawingVersion: 1,
        lineData: BackupRestoreSample.ink("legacy-L"), layoutMetadataData: nil
    )
    private let legacyM = BackupExportRowSeed(
        verse: 1, rowUUID: nil, businessID: "1-01Genesis.txt.1.1.1700000050", isPresent: nil,
        creationDate: BackupRestoreSample.sep(5), updateDate: BackupRestoreSample.sep(5), drawingVersion: 1,
        lineData: BackupRestoreSample.ink("legacy-M"), layoutMetadataData: nil
    )

    @Test("적용을 시작한 뒤 세대가 바뀌었으면 아무것도 쓰지 않고 staleStoreGeneration 을 던진다")
    func staleGenerationWritesNothing() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let entry = BackupRestoreEntry(verse: 1, sourceKey: "ROW-1", ink: Sample.ink("1"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2))
        let command = BackupChapterRestoreCommand(entries: [entry])
        let started = await harness.generation()

        // When: 그 사이 모든 필사를 지웠다.
        try await harness.database.eraseAllDrawingRows()

        // Then
        await #expect(throws: DrawingRepositoryError.staleStoreGeneration) {
            _ = try await harness.restorer.restore(command, chapter: Sample.genesis1, generation: started)
        }
        #expect(try await harness.rows().isEmpty)
        // 지금 세대로는 쓴다.
        let outcome = try await harness.restorer.restore(command, chapter: Sample.genesis1, generation: await harness.generation())
        #expect(outcome.insertedCount == 1)
        #expect(try await harness.rows().count == 1)
    }

    @Test("쓰기 직전에 다시 판정한다 — 같은 절에 다른 필기가 들어와 있으면 지금 필사는 그대로 두고 보관으로만 넣는다")
    func rejudgesAgainstTheStoreAtWriteTime() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        // Given: 명령을 만든 뒤(판정 전) 그 절에 지금 필사 X 가 들어왔다.
        let backup = BackupRestoreEntry(verse: 1, sourceKey: "ROW-Y", ink: Sample.ink("Y"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(20))
        let command = BackupChapterRestoreCommand(entries: [backup])
        let present = BackupExportRowSeed(
            verse: 1, rowUUID: "ROW-X", creationDate: Sample.sep(2), updateDate: Sample.sep(28),
            lineData: Sample.ink("X"), layoutMetadataData: Sample.metadata
        )
        try harness.seed([present])

        // When
        let outcome = try await harness.restorer.restore(command, chapter: Sample.genesis1, generation: await harness.generation())

        // Then: 보관으로만 넣었고, X 는 내용 · 시각 · isPresent 가 그대로이며 대표다.
        #expect(outcome.decisions.map(\.decision) == [.insertArchived])
        #expect(outcome.pins.isEmpty)
        let rows = try await harness.rows()
        #expect(rows.count == 2)
        #expect(rows.first { $0.rowKey == "ROW-X" } == present.record)
        #expect(rows.first { $0.lineData == Sample.ink("Y") }?.isPresent == false)
        #expect(try await harness.representative(verse: 1)?.rowKey == "ROW-X")
    }

    @Test("「비운 현재 + 잉크 보관」 세 경우 — 빈 절은 비운 행이 대표, 잉크 있는 대표 · 비운 대표가 있으면 그대로다")
    func clearedCurrentAgainstThreeStores() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        // Given: 1절은 행 없음, 2절은 잉크 있는 대표 X(9/28), 3절은 10/01 에 지운 비운 대표.
        try harness.seed([
            BackupExportRowSeed(
                verse: 2, rowUUID: "X-2", creationDate: Sample.sep(1), updateDate: Sample.sep(28),
                lineData: Sample.ink("X-2"), layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                verse: 3, rowUUID: "CLEARED-3", creationDate: Sample.sep(1), updateDate: Sample.oct(1),
                lineData: nil, layoutMetadataData: Sample.metadata
            )
        ])
        // 백업: 절마다 (a) 9/30 의 비운 현재 행, (b) 9/25 의 잉크 있는 보관 행.
        var entries: [BackupRestoreEntry] = []
        for verse in 1...3 {
            entries.append(BackupRestoreEntry(verse: verse, sourceKey: "A-\(verse)", ink: nil, isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(30)))
            entries.append(BackupRestoreEntry(
                verse: verse, sourceKey: "B-\(verse)", ink: Sample.ink("erased-\(verse)"), isCurrent: false,
                createdAt: Sample.sep(30), updatedAt: Sample.sep(25)
            ))
        }

        // When
        let outcome = try await harness.restorer.restore(
            BackupChapterRestoreCommand(entries: entries), chapter: Sample.genesis1, generation: await harness.generation()
        )

        // Then: 1절 — (a) 현재(비운 행) · (b) 보관 → 대표는 비운 행.
        #expect(outcome.counts(verse: 1) == BackupImportPreview(new: 1, archived: 1, chapters: [Sample.genesis1]))
        #expect(try await harness.representative(verse: 1)?.lineData == nil)
        // 2절 — (a) 건너뜀(비우지 않는다) · (b) 보관 → X 그대로.
        #expect(outcome.counts(verse: 2) == BackupImportPreview(archived: 1, skippedEmpty: 1, chapters: [Sample.genesis1]))
        #expect(try await harness.representative(verse: 2)?.rowKey == "X-2")
        // 3절 — (a) 이미 비운 상태 · (b) 보관 → 비운 대표 그대로.
        #expect(outcome.counts(verse: 3) == BackupImportPreview(same: 1, archived: 1, chapters: [Sample.genesis1]))
        #expect(try await harness.representative(verse: 3)?.rowKey == "CLEARED-3")
        #expect(try await harness.rows().count == 2 + 4)
    }

    @Test("지운 절 보호 — 백업보다 뒤에 지운 절에는 보관으로만 넣고, 백업보다 앞서 지운 절에는 현재로 넣는다")
    func protectsVersesClearedAfterTheBackup() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        // Given: 1절은 9/29 에, 2절은 9/10 에 지운 비운 대표.
        try harness.seed([
            BackupExportRowSeed(
                verse: 1, rowUUID: "CLEARED-1", creationDate: Sample.sep(1), updateDate: Sample.sep(29),
                lineData: nil, layoutMetadataData: Sample.metadata
            ),
            BackupExportRowSeed(
                verse: 2, rowUUID: "CLEARED-2", creationDate: Sample.sep(1), updateDate: Sample.sep(10),
                lineData: nil, layoutMetadataData: Sample.metadata
            )
        ])
        // 백업의 현재 필기 Y(9/20) — 두 절 모두.
        let entries = (1...2).map { verse in
            BackupRestoreEntry(
                verse: verse, sourceKey: "Y-\(verse)", ink: Sample.ink("Y-\(verse)"), isCurrent: true,
                createdAt: Sample.sep(20), updatedAt: Sample.sep(20)
            )
        }

        // When
        let outcome = try await harness.restorer.restore(
            BackupChapterRestoreCommand(entries: entries), chapter: Sample.genesis1, generation: await harness.generation()
        )

        // Then: 1절은 지운 것을 되살리지 않고 기록으로만, 2절은 Y 가 대표가 된다.
        #expect(outcome.decisions.map(\.decision) == [.protectCleared, .insertCurrent])
        #expect(outcome.pins.isEmpty)
        let rows = try await harness.rows()
        #expect(rows.first { $0.lineData == Sample.ink("Y-1") }?.isPresent == false)
        #expect(try await harness.representative(verse: 1)?.rowKey == "CLEARED-1")
        #expect(rows.first { $0.lineData == Sample.ink("Y-2") }?.isPresent == true)
        #expect(try await harness.representative(verse: 2)?.lineData == Sample.ink("Y-2"))
    }

    @Test("대표 고정 — isPresent 가 모두 false 인 legacy 절에 더 늦은 다른 내용을 보관으로 넣어도 화면의 대표가 그대로다")
    func legacyVerseKeepsItsRepresentative() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        try harness.seed([legacyL, legacyM])
        // Given: 백업의 현재 필기 Y(9/20)와 보관 필기 Z(9/25) — 둘 다 지금 대표 L 보다 늦고 내용이 다르다.
        let backupCurrent = BackupRestoreEntry(verse: 1, sourceKey: "Y", ink: Sample.ink("Y"), isCurrent: true, createdAt: Sample.sep(20), updatedAt: Sample.sep(20))
        let backupArchive = BackupRestoreEntry(verse: 1, sourceKey: "Z", ink: Sample.ink("Z"), isCurrent: false, createdAt: Sample.sep(25), updatedAt: Sample.sep(25))
        let command = BackupChapterRestoreCommand(entries: [backupCurrent, backupArchive])

        // When
        let outcome = try await harness.restorer.restore(command, chapter: Sample.genesis1, generation: await harness.generation())

        // Then: 둘 다 보관으로 넣고 L 을 고정했다.
        #expect(outcome.decisions.map(\.decision) == [.insertArchived, .insertArchived])
        #expect(outcome.pins == [BackupRepresentativePin(verse: 1, rowKey: legacyL.rowKey)])
        let rows = try await harness.rows()
        #expect(rows.count == 4)
        // L 은 isPresent 만 true 가 됐다 — 내용 · 시각 · 좌표 형식은 그대로. M 은 그대로다.
        let pinned = try #require(rows.first { $0.rowKey == legacyL.rowKey })
        #expect(pinned.isPresent == true)
        #expect(pinned.lineData == legacyL.lineData)
        #expect(pinned.updateDate == legacyL.updateDate)
        #expect(pinned.creationDate == legacyL.creationDate)
        #expect(pinned.drawingVersion == 1)
        #expect(rows.first { $0.rowKey == legacyM.rowKey } == legacyM.record)
        // 화면의 대표(장 조회)는 그대로 L 이다 — 고정하지 않았다면 9/25 의 Z 가 보였다.
        let load = try await SwiftDataDrawingRepository(actor: harness.database).load(chapter: Sample.genesis1)
        #expect(load.snapshots.representativesByVerse()[1]?.rowID.raw == legacyL.rowKey)

        // Then: 다시 불러오면 넣을 행도 고정도 없다.
        let again = try await harness.restorer.restore(command, chapter: Sample.genesis1, generation: await harness.generation())
        #expect(again.decisions.map(\.decision) == [.skipSame, .skipSame])
        #expect(again.pins.isEmpty)
        #expect(!again.changedStore)
        #expect(try await harness.rows().count == 4)
    }

    @Test("행 없는 절은 고정하지 않는다 — 빈 자리 행을 만들지 않고, 보관 항목 중 가장 늦은 것이 대표 규칙대로 보인다")
    func emptyVerseIsNotPinned() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        // Given: 현재 후보가 없는 절 — 보이지 않던 초안(9/20)과 보관 행(9/10).
        let hiddenDraft = BackupRestoreEntry(
            kind: .draft, verse: 3, sourceKey: "local|S|NKRV|1-01Genesis.txt|1|3|3", ink: Sample.ink("hidden"),
            isCurrent: false, createdAt: nil, updatedAt: Sample.sep(20)
        )
        let oldRow = BackupRestoreEntry(verse: 3, sourceKey: "OLD", ink: Sample.ink("old"), isCurrent: false, createdAt: Sample.sep(10), updatedAt: Sample.sep(10))

        // When
        let outcome = try await harness.restorer.restore(
            BackupChapterRestoreCommand(entries: [hiddenDraft, oldRow]), chapter: Sample.genesis1, generation: await harness.generation()
        )

        // Then
        #expect(outcome.decisions.allSatisfy { $0.decision == .insertArchived })
        #expect(outcome.pins.isEmpty)
        let rows = try await harness.rows()
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.isPresent == false })
        #expect(try await harness.representative(verse: 3)?.lineData == Sample.ink("hidden"))
    }

    @Test("넣을 행의 바이트가 빠졌으면 아무것도 쓰지 않는다 — 다른 행 · 대표 고정도")
    func missingBytesWriteNothing() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        try harness.seed([legacyL])
        // Given: 보관으로 들어갈 두 항목 중 하나의 잉크 바이트가 명령에 없다(고정도 계획된다).
        let first = BackupRestoreEntry(verse: 1, sourceKey: "Y", ink: Sample.ink("Y"), isCurrent: false, createdAt: Sample.sep(20), updatedAt: Sample.sep(20))
        let second = BackupRestoreEntry(verse: 1, sourceKey: "Z", ink: Sample.ink("Z"), isCurrent: false, createdAt: Sample.sep(25), updatedAt: Sample.sep(25))
        let full = BackupChapterRestoreCommand(entries: [first, second])
        var blobs = full.blobs
        blobs[BackupFormat.sha256Hex(Sample.ink("Z"))] = nil
        let command = BackupChapterRestoreCommand(items: full.items, blobs: blobs)

        // When / Then
        await #expect(throws: BackupChapterRestoreError.blobUnavailable(name: BackupFormat.sha256Hex(Sample.ink("Z")))) {
            _ = try await harness.restorer.restore(command, chapter: Sample.genesis1, generation: await harness.generation())
        }
        let rows = try await harness.rows()
        #expect(rows == [legacyL.record])
    }

    @Test("blob 바이트가 이름(SHA-256)과 다르면 쓰지 않는다")
    func mismatchedBytesWriteNothing() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let entry = BackupRestoreEntry(verse: 1, sourceKey: "ROW-1", ink: Sample.ink("1"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2))
        let full = BackupChapterRestoreCommand(entries: [entry])
        var blobs = full.blobs
        let inkName = BackupFormat.sha256Hex(Sample.ink("1"))
        blobs[inkName] = Sample.ink("tampered")
        let command = BackupChapterRestoreCommand(items: full.items, blobs: blobs)

        await #expect(throws: BackupChapterRestoreError.blobUnavailable(name: inkName)) {
            _ = try await harness.restorer.restore(command, chapter: Sample.genesis1, generation: await harness.generation())
        }
        #expect(try await harness.rows().isEmpty)
    }

    @Test("다른 장 항목과 지원하지 않는 항목은 쓰지 않고, 결정에 지원 안 됨으로 남긴다")
    func otherChapterAndUnsupportedItemsAreNotWritten() async throws {
        let harness = try BackupRestoreHarness()
        defer { harness.remove() }
        let here = BackupRestoreEntry(verse: 1, sourceKey: "HERE", ink: Sample.ink("here"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2))
        let otherChapter = BackupRestoreEntry(
            chapter: Sample.genesis2, verse: 1, sourceKey: "THERE", ink: Sample.ink("there"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2)
        )
        let unknownTranslation = BackupRestoreEntry(
            verse: 2, sourceKey: "KJV", ink: Sample.ink("kjv"), isCurrent: true, createdAt: Sample.sep(1), updatedAt: Sample.sep(2), translation: "KJV"
        )
        let brokenMetadata = BackupRestoreEntry(
            verse: 3, sourceKey: "BROKEN", ink: Sample.ink("broken"), metadata: Data("깨진 메타데이터".utf8), isCurrent: true,
            createdAt: Sample.sep(1), updatedAt: Sample.sep(2)
        )

        let outcome = try await harness.restorer.restore(
            BackupChapterRestoreCommand(entries: [here, otherChapter, unknownTranslation, brokenMetadata]),
            chapter: Sample.genesis1,
            generation: await harness.generation()
        )

        #expect(outcome.counts == BackupImportPreview(
            new: 1, unsupported: [.unknownTranslation: 1, .undecodableMetadata: 1], chapters: [Sample.genesis1]
        ))
        #expect(try await harness.rows().map(\.lineData) == [Sample.ink("here")])
        #expect(try await harness.rows(Sample.genesis2).isEmpty)
    }
}
