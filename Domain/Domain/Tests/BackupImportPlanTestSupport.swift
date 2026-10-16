//
//  BackupImportPlanTestSupport.swift
//  DomainTest
//
//  불러오기 판정기 시험의 공용 표본 — 고정 바이트 잉크 · 고정 시각으로 만든 백업 항목과 지금 저장소 행, 판정 결과를 저장소에 넣은 모습.
//

import Foundation

@testable import Domain

/// 고정 표본. 잉크는 `PKDrawing` 이 아니라 고정 바이트다 — `PKDrawing` 바이트는 만들 때마다 달라진다.
enum BackupImportPlanSample {
    /// 판정하는 장 — 창세기 1장.
    static let chapter = BibleChapter(title: .genesis, chapter: 1)
    /// 판정 단위 — 기본 필사책의 창세기 1장.
    static let page = NotebookChapter(notebook: .default, chapter: chapter)

    /// `DrawingLayoutMetadata.decode` 로 풀리는 메타데이터. 비운 행에도 남는다(「지우기」 는 `lineData` 만 비운다).
    static let layoutMetadata = Data("""
    {"metadataSchemaVersion":1,"baseWritingWidth":300,"baseWritingHeight":400,\
    "baseUnderlineAnchors":[0,30],"layoutSignature":"cl2-import-plan"}
    """.utf8)

    /// 2026-09-01T00:00:00Z. 시각은 설계 §5-1 의 예(9/25 · 9/30 · 10/01)를 그대로 읽게 날짜로 적는다.
    static let september1 = Date(timeIntervalSinceReferenceDate: 809_913_600)

    /// 2026년 9월 그날 0시(UTC).
    static func sep(_ day: Int) -> Date {
        september1.addingTimeInterval(Double(day - 1) * 86_400)
    }

    /// 2026년 10월 그날 0시(UTC).
    static func oct(_ day: Int) -> Date {
        sep(30 + day)
    }

    /// 잉크 바이트 — 이름이 같으면 같은 바이트다.
    static func ink(_ name: String) -> Data {
        Data("ink-\(name)".utf8)
    }

    /// 내용 지문 — 내보내기 · 백업 전용 조회와 같은 규칙(원본 바이트).
    static func fingerprint(_ ink: Data, drawingVersion: Int? = 3, metadata: Data? = layoutMetadata) -> String {
        VerseContentFingerprint.make(lineData: ink, drawingVersion: drawingVersion, layoutMetadataBlob: metadata)
    }

    /// 백업 항목 하나. `ink` 가 nil 이면 비운 항목이다.
    ///
    /// id 는 `BackupItemID.make` 로 원본 키 · 지문에서 만든다(`id` 를 주면 그 값 — 동률 · 순서 시험용). 초안은 만든 시각이 없다(설계 §2-4).
    static func item(
        _ sourceKey: String,
        verse: Int = 1,
        ink: Data?,
        isCurrent: Bool,
        updatedAt: Date?,
        createdAt: Date? = september1,
        drawingVersion: Int? = 3,
        metadata: Data? = layoutMetadata,
        translation: String? = "NKRV",
        book: String = "GEN",
        chapter: Int = 1,
        kind: BackupItemKind = .row,
        id: String? = nil
    ) -> BackupItem {
        let fingerprint = ink.map { Self.fingerprint($0, drawingVersion: drawingVersion, metadata: metadata) }
        let titleName = BibleBookCode(rawValue: book)?.title.rawValue ?? book
        return BackupItem(
            id: id ?? BackupItemID.make(kind: kind, sourceKey: sourceKey, fingerprint: fingerprint),
            kind: kind,
            verse: BackupVerseKey(translation: translation, book: book, chapter: chapter, verse: verse),
            drawingVersion: drawingVersion,
            inkBlob: ink.map(BackupFormat.sha256Hex),
            metadataBlob: metadata.map(BackupFormat.sha256Hex),
            fingerprint: fingerprint,
            isCurrent: isCurrent,
            createdAt: kind == .draft ? nil : createdAt,
            updatedAt: updatedAt,
            source: kind == .row
                ? BackupItemSource(titleName: titleName, rowKey: sourceKey)
                : BackupItemSource(titleName: titleName, draftScope: BackupItemSource.DraftScope.local.rawValue, draftRevision: 1)
        )
    }

    /// 지금 저장소 행 하나(백업 전용 조회의 모양). `ink` 가 nil 이면 비운 행이다.
    static func row(
        _ rowKey: String,
        verse: Int = 1,
        ink: Data?,
        isPresent: Bool?,
        updatedAt: Date?,
        drawingVersion: Int? = 3,
        metadata: Data? = layoutMetadata,
        translation: String? = "NKRV",
        title: BibleTitle = .genesis,
        chapter: Int = 1
    ) -> BackupRowRecord {
        BackupRowRecord(
            rowUUID: rowKey,
            businessID: "\(title.rawValue).\(chapter).\(verse).1700000000",
            titleName: title.rawValue,
            chapter: chapter,
            verse: verse,
            translation: translation,
            isPresent: isPresent,
            creationDate: september1,
            updateDate: updatedAt,
            drawingVersion: drawingVersion,
            lineData: ink,
            layoutMetadataData: metadata
        )
    }

    /// 1.3.0 이 만든 legacy 행 — `rowUUID` 가 없어 business id 가 행 키이고, 좌표 형식 1 · 메타데이터 없음, `isPresent` 를 켜지 않았다.
    static func legacyRow(_ businessID: String, verse: Int = 1, ink: Data?, isPresent: Bool? = false, updatedAt: Date?) -> BackupRowRecord {
        BackupRowRecord(
            rowUUID: nil,
            businessID: businessID,
            titleName: BibleTitle.genesis.rawValue,
            chapter: 1,
            verse: verse,
            translation: "NKRV",
            isPresent: isPresent,
            creationDate: updatedAt,
            updateDate: updatedAt,
            drawingVersion: 1,
            lineData: ink,
            layoutMetadataData: nil
        )
    }

    /// 기본 필사책의 창세기 1장을 판정한다.
    static func plan(
        _ items: [BackupItem],
        current: [BackupRowRecord] = [],
        unsupported: [String: BackupUnsupportedReason] = [:]
    ) -> BackupChapterPlan {
        BackupImportPlanner.plan(items: items, unsupported: unsupported, current: current, page: page)
    }

    /// 판정 결과를 저장소에 넣은 모습 — 대표 고정(`pins`)한 지금 행은 `isPresent` 만 true 로 바꾸고, 넣을 행을 blob 바이트로 되살려 더한다.
    ///
    /// 복원 쓰기와 같은 값이고 `rowUUID` 만 시험용 고정값이다(실제는 늘 새로 발급한다).
    /// - Parameter blobs: 항목이 가리키는 잉크 바이트. 표본 메타데이터는 따로 넣는다.
    static func applying(_ plan: BackupChapterPlan, to rows: [BackupRowRecord], blobs: [Data]) -> [BackupRowRecord] {
        var bytes = [BackupFormat.sha256Hex(layoutMetadata): layoutMetadata]
        for blob in blobs {
            bytes[BackupFormat.sha256Hex(blob)] = blob
        }
        let pinned = Set(plan.pins)
        let kept = rows.map { row in
            pinned.contains(BackupRepresentativePin(verse: row.verse, rowKey: row.rowKey)) ? presented(row) : row
        }
        let inserted = plan.insertions.enumerated().map { offset, insertion in
            BackupRowRecord(
                rowUUID: "IMPORTED-\(offset)",
                businessID: nil,
                titleName: insertion.titleName,
                chapter: insertion.page.chapter.chapter,
                verse: insertion.verse,
                translation: insertion.translation,
                isPresent: insertion.isPresent,
                creationDate: insertion.creationDate,
                updateDate: insertion.updateDate,
                drawingVersion: insertion.drawingVersion,
                lineData: insertion.inkBlob.flatMap { bytes[$0] },
                layoutMetadataData: insertion.metadataBlob.flatMap { bytes[$0] }
            )
        }
        return kept + inserted
    }

    /// 같은 행을 `isPresent = true` 로 — 대표 고정을 적용한 모습(다른 값은 그대로).
    static func presented(_ row: BackupRowRecord) -> BackupRowRecord {
        BackupRowRecord(
            rowUUID: row.rowUUID,
            businessID: row.businessID,
            titleName: row.titleName,
            chapter: row.chapter,
            verse: row.verse,
            translation: row.translation,
            isPresent: true,
            creationDate: row.creationDate,
            updateDate: row.updateDate,
            drawingVersion: row.drawingVersion,
            lineData: row.lineData,
            layoutMetadataData: row.layoutMetadataData
        )
    }

    /// 그 절의 대표 — 화면(`DrawingCodec.compose` 의 `representativesByVerse`)과 같은 규칙.
    static func representative(of rows: [BackupRowRecord], verse: Int = 1) -> BackupRowRecord? {
        DrawingRepresentativeRule.pick(rows.filter { $0.verse == verse })
    }
}
