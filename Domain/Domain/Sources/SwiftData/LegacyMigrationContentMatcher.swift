//
//  LegacyMigrationContentMatcher.swift
//  Domain
//
//  첫 로그인 V3 귀속 전에 보존한 원본과 로컬 마이그레이션 결과를 대조한다.
//

import Foundation
import SwiftData

/// 로그인 사실만으로 현재 로컬 행을 원본 legacy 자료로 간주하지 않도록 콘텐츠를 교차 확인한다.
enum LegacyMigrationContentMatcher {
    private struct VerseRow: Equatable {
        var id: String?
        var titleName: String?
        var titleChapter: Int?
        var verse: Int?
        var creationDate: Date?
        var updateDate: Date?
        var translation: String?
        var drawingVersion: Int?
        var isPresent: Bool?
        var layoutMetadataData: Data?
        var rowUUID: String?
        var lineData: Data?
    }

    private struct PageRow: Equatable {
        var id: String?
        var titleName: String?
        var titleChapter: Int?
        var creationDate: Date?
        var updateDate: Date?
        var translation: String?
        var fullLineData: Data?
    }

    private struct Content: Equatable {
        var verses: [VerseRow]
        var pages: [PageRow]
    }

    private enum MatchFailure: Error {
        case unexpectedNewV6Rows
    }

    /// 보존한 V3와 현재 로컬 사본의 필기 payload·좌표 버전·표시 상태를 비교한다. 두 입력 모두 사본이어야 한다.
    static func matches(sourceSnapshot: URL, currentStore: URL, fileManager: FileManager = .default) -> Bool {
        mismatchSummary(sourceSnapshot: sourceSnapshot, currentStore: currentStore, fileManager: fileManager) == ""
    }

    /// 테스트 진단용 안전 요약. 행 ID·필기 bytes·계정 metadata 값은 반환하지 않는다.
    static func mismatchSummary(sourceSnapshot: URL, currentStore: URL, fileManager: FileManager = .default) -> String? {
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("legacy-migration-content-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratch) }
        var stage = "사본 준비"

        do {
            try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
            let sourceCopyDirectory = scratch.appendingPathComponent("source", isDirectory: true)
            try fileManager.copyItem(at: sourceSnapshot.deletingLastPathComponent(), to: sourceCopyDirectory)
            let sourceCopy = sourceCopyDirectory.appendingPathComponent(sourceSnapshot.lastPathComponent)

            let currentCopyDirectory = scratch.appendingPathComponent("current", isDirectory: true)
            let currentCopy = try LegacyRowLinkageReader.copyStoreFiles(from: currentStore, into: currentCopyDirectory, fileManager: fileManager)
            let sourceSupport = RawStoreSnapshot.supportDirectory(for: currentStore)
            if fileManager.fileExists(atPath: sourceSupport.path) {
                try fileManager.copyItem(at: sourceSupport, to: RawStoreSnapshot.supportDirectory(for: currentCopy))
            }

            stage = "저장소 model 판별"
            guard case .known(let sourceVersion) = LocalStoreLoader.storeKind(at: sourceCopy), sourceVersion.major == 3,
                  case .known(let currentVersion) = LocalStoreLoader.storeKind(at: currentCopy), [3, 6].contains(currentVersion.major) else {
                return "지원 저장소 model profile이 아님"
            }

            stage = "보존한 V3 읽기"
            let source = try contentV3(at: sourceCopy)
            let current: Content
            if currentVersion.major == 3 {
                stage = "현재 V3 읽기"
                current = try contentV3(at: currentCopy)
            } else {
                stage = "현재 V6 읽기"
                current = try contentV6(at: currentCopy)
            }

            return mismatchSummary(source: source, current: current)
        } catch {
            if error is MatchFailure { return "새 V6 필기·즐겨찾기 자료가 있음" }
            return stage + " 실패 (" + String(reflecting: type(of: error)) + ")"
        }
    }

    private static func mismatchSummary(source: Content, current: Content) -> String {
        var categories: [String] = []
        let sourceVerses = source.verses.sorted { ($0.id ?? "") < ($1.id ?? "") }
        let currentVerses = current.verses.sorted { ($0.id ?? "") < ($1.id ?? "") }
        if sourceVerses.count != currentVerses.count {
            categories.append("절 행 수")
        } else {
            for (sourceRow, currentRow) in zip(sourceVerses, currentVerses) {
                if sourceRow.id != currentRow.id { categories.append("절 행 식별자"); break }
                if sourceRow.titleName != currentRow.titleName || sourceRow.titleChapter != currentRow.titleChapter
                    || sourceRow.verse != currentRow.verse || sourceRow.creationDate != currentRow.creationDate
                    || sourceRow.updateDate != currentRow.updateDate || sourceRow.translation != currentRow.translation
                    || sourceRow.drawingVersion != currentRow.drawingVersion || sourceRow.isPresent != currentRow.isPresent
                    || sourceRow.layoutMetadataData != currentRow.layoutMetadataData || sourceRow.rowUUID != currentRow.rowUUID {
                    categories.append("절 좌표·표시 metadata")
                    break
                }
                if sourceRow.lineData != currentRow.lineData {
                    categories.append("절 필기 payload")
                    break
                }
            }
        }

        let sourcePages = source.pages.sorted { ($0.id ?? "") < ($1.id ?? "") }
        let currentPages = current.pages.sorted { ($0.id ?? "") < ($1.id ?? "") }
        if sourcePages.count != currentPages.count {
            categories.append("장 행 수")
        } else {
            for (sourceRow, currentRow) in zip(sourcePages, currentPages) {
                if sourceRow.id != currentRow.id || sourceRow.titleName != currentRow.titleName
                    || sourceRow.titleChapter != currentRow.titleChapter || sourceRow.creationDate != currentRow.creationDate
                    || sourceRow.updateDate != currentRow.updateDate || sourceRow.translation != currentRow.translation {
                    categories.append("장 표시 metadata")
                    break
                }
                if sourceRow.fullLineData != currentRow.fullLineData {
                    categories.append("장 필기 payload")
                    break
                }
            }
        }
        return categories.joined(separator: ", ")
    }

    private static func content(in container: ModelContainer) throws -> Content {
        try content(in: ModelContext(container))
    }

    private static func contentV3(at storeURL: URL) throws -> Content {
        let container = try ModelContainer(
            for: Schema(DrawingSchemaV3.models),
            configurations: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        )
        return try contentV3(in: container)
    }

    private static func contentV6(at storeURL: URL) throws -> Content {
        let container = try ModelContainer(
            for: AppStoreSchema.schema,
            migrationPlan: DrawingDataMigrationPlan.self,
            configurations: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        guard try context.fetchCount(FetchDescriptor<FavoriteVerse>()) == 0,
              try context.fetchCount(FetchDescriptor<VerseDrawingVersion>()) == 0,
              try context.fetchCount(FetchDescriptor<DrawingEraseEpoch>()) == 0 else {
            throw MatchFailure.unexpectedNewV6Rows
        }
        return try content(in: context)
    }

    private static func contentV3(in container: ModelContainer) throws -> Content {
        let context = ModelContext(container)
        let verses = try context.fetch(FetchDescriptor<DrawingSchemaV3.BibleDrawing>()).map { row in
            VerseRow(
                id: row.id, titleName: row.titleName, titleChapter: row.titleChapter, verse: row.verse,
                creationDate: row.creationDate, updateDate: row.updateDate, translation: row.translation?.rawValue,
                drawingVersion: row.drawingVersion, isPresent: row.isPresent, layoutMetadataData: nil,
                rowUUID: nil, lineData: row.lineData
            )
        }
        let pages = try context.fetch(FetchDescriptor<DrawingSchemaV3.BiblePageDrawing>()).map { row in
            PageRow(
                id: row.id, titleName: row.titleName, titleChapter: row.titleChapter,
                creationDate: row.creationDate, updateDate: row.updateDate, translation: row.translation?.rawValue,
                fullLineData: row.fullLineData
            )
        }
        return Content(verses: verses, pages: pages)
    }

    private static func content(in context: ModelContext) throws -> Content {
        let verses = try context.fetch(FetchDescriptor<DrawingSchemaV4.BibleDrawing>()).map { row in
            VerseRow(
                id: row.id, titleName: row.titleName, titleChapter: row.titleChapter, verse: row.verse,
                creationDate: row.creationDate, updateDate: row.updateDate, translation: row.translation?.rawValue,
                drawingVersion: row.drawingVersion, isPresent: row.isPresent, layoutMetadataData: row.layoutMetadataData,
                rowUUID: row.rowUUID, lineData: row.lineData
            )
        }
        let pages = try context.fetch(FetchDescriptor<DrawingSchemaV4.BiblePageDrawing>()).map { row in
            PageRow(
                id: row.id, titleName: row.titleName, titleChapter: row.titleChapter,
                creationDate: row.creationDate, updateDate: row.updateDate, translation: row.translation?.rawValue,
                fullLineData: row.fullLineData
            )
        }
        return Content(verses: verses, pages: pages)
    }
}
