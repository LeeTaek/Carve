//
//  TranslationDrawingIsolationTesting.swift
//  DomainTest
//
//  영어 현지화 결정 1 — 필사 행(`BibleDrawing`)의 저장 · 조회를 번역본별로 가른다.
//  같은 권 · 장 · 절의 개역개정 · KJV · BSB 행이 장 조회 · 절 이력 · 대표 옮기기 · 권 기록 요약 · 지우기에서 서로 섞이지 않고,
//  영어 행은 `titleName` 접두 · 열 nil 로, 개역개정 행은 지금 형식 그대로 저장되는지 고정한다.
//  시험마다 인메모리 컨테이너를 따로 연다 — 공유 actor(`createSwiftDataActor.testValue`)를 쓰지 않는다.
//

@testable import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import Dependencies

@Suite("영어 현지화 — 필사 행의 번역본 격리")
struct TranslationDrawingIsolationTesting {
    fileprivate static let title = BibleTitle.habakkuk
    fileprivate static let chapterNumber = 3
    fileprivate static let verse = 4
    fileprivate static let nkrv = BibleChapter(title: title, chapter: chapterNumber, translation: .NKRV)
    fileprivate static let kjv = BibleChapter(title: title, chapter: chapterNumber, translation: .KJV)
    fileprivate static let bsb = BibleChapter(title: title, chapter: chapterNumber, translation: .BSB)
    fileprivate static let allChapters = [nkrv, kjv, bsb]
    fileprivate static let base = Date(timeIntervalSince1970: 1_700_000_000)
    private static let window = DateInterval(start: base - 1_000, end: base + 10_000)

    /// 실제 획이 하나 있는 `PKDrawing` 데이터. 바이트로 견주므로 한 번 만들어 재사용한다(만들 때마다 바이트가 다르다).
    private static let inkData: Data = makeInk(at: 5)

    // MARK: 새 행

    @Test("새 행 — 개역개정은 titleName · 열이 지금과 같고, 영어 행은 titleName 접두 · 열 nil 이다")
    func newRowsUseStoredBookKey() async throws {
        let harness = try TranslationIsolationHarness()
        var created: [Translation: BibleDrawingRowID] = [:]
        for chapter in Self.allChapters {
            created[chapter.translation] = try await harness.create(chapter, verse: Self.verse, data: Self.inkData)
        }
        // 행이 없는 절의 clear 도 새 행을 만든다 — 그 경로도 같은 규칙이다.
        let clearedRowID = BibleDrawingRowID.issue()
        try await harness.apply([.clear(verse: 9, rowID: clearedRowID)], chapter: Self.kjv)

        let rows = try harness.storedRows()
        #expect(rows.count == 4)

        let nkrvRow = try #require(rows.first { $0.rowKey == created[.NKRV]?.raw })
        #expect(nkrvRow.titleName == "1-35Habakkuk.txt")
        #expect(nkrvRow.translation == .NKRV)
        #expect(nkrvRow.businessID?.hasPrefix("1-35Habakkuk.txt.3.4.") == true)

        let kjvRow = try #require(rows.first { $0.rowKey == created[.KJV]?.raw })
        #expect(kjvRow.titleName == "KJV-1-35Habakkuk.txt")
        #expect(kjvRow.translation == nil)
        #expect(kjvRow.businessID?.hasPrefix("KJV-1-35Habakkuk.txt.3.4.") == true)

        let bsbRow = try #require(rows.first { $0.rowKey == created[.BSB]?.raw })
        #expect(bsbRow.titleName == "BSB-1-35Habakkuk.txt")
        #expect(bsbRow.translation == nil)

        let clearedRow = try #require(rows.first { $0.rowKey == clearedRowID.raw })
        #expect(clearedRow.titleName == "KJV-1-35Habakkuk.txt")
        #expect(clearedRow.translation == nil)

        // 열에는 영어 값을 절대 쓰지 않는다.
        #expect(rows.allSatisfy { $0.translation == nil || $0.translation == .NKRV })
        #expect(rows.allSatisfy { $0.titleChapter == Self.chapterNumber })
    }

    @Test("모델 이니셜라이저 — 장의 번역본으로 titleName · 열을 짓고, 생략하면 개역개정이다")
    func modelInitializerFollowsChapterTranslation() throws {
        // iOS 17 SwiftData 는 모델을 만들기 전에 그 스키마의 컨테이너가 있어야 한다.
        let harness = try TranslationIsolationHarness()
        let context = ModelContext(harness.actor.modelContainer)

        let legacyCall = BibleDrawing(bibleTitle: BibleChapter(title: Self.title, chapter: 1), verse: 1)
        let english = BibleDrawing(bibleTitle: BibleChapter(title: Self.title, chapter: 1, translation: .BSB), verse: 1)
        context.insert(legacyCall)
        context.insert(english)

        #expect(legacyCall.titleName == Self.title.rawValue)
        #expect(legacyCall.translation == .NKRV)
        #expect(english.titleName == StoredBookKey.titleName(title: Self.title, translation: .BSB))
        #expect(english.translation == nil)
    }

    // MARK: 조회

    @Test("장 조회 · 절 이력 조회는 그 번역본 행만 읽고 스냅샷에 번역본을 싣는다")
    func loadAndVerseSnapshotsAreIsolated() async throws {
        let harness = try TranslationIsolationHarness()
        var created: [Translation: BibleDrawingRowID] = [:]
        for chapter in Self.allChapters {
            created[chapter.translation] = try await harness.create(chapter, verse: Self.verse, data: Self.inkData)
        }

        for chapter in Self.allChapters {
            let loaded = try await harness.repository.load(chapter: chapter).snapshots
            #expect(loaded.map(\.rowID) == [created[chapter.translation]].compactMap { $0 })
            #expect(loaded.allSatisfy { $0.translation == chapter.translation })

            let listed = try await harness.database.fetchVerseSnapshots(chapter: chapter, verse: Self.verse)
            #expect(listed.map(\.rowID) == [created[chapter.translation]].compactMap { $0 })
            #expect(listed.allSatisfy { $0.translation == chapter.translation })
        }
    }

    @Test("접두 없는 옛 행은 열이 nil 이든 .NKRV 든 개역개정으로 읽히고 영어 장에는 보이지 않는다")
    func legacyRowsWithoutPrefixReadAsNKRV() async throws {
        let harness = try TranslationIsolationHarness()
        let columnNil = try harness.seed(Self.nkrv, rowUUID: nil, lineData: Self.inkData, at: Self.base, column: .some(nil))
        let columnNKRV = try harness.seed(Self.nkrv, lineData: Self.inkData, at: Self.base + 10, column: .some(.NKRV))

        let nkrvLoad = try await harness.repository.load(chapter: Self.nkrv).snapshots
        #expect(Set(nkrvLoad.map(\.rowID.raw)) == [columnNil, columnNKRV])
        #expect(nkrvLoad.allSatisfy { $0.translation == .NKRV })

        let nkrvListed = try await harness.database.fetchVerseSnapshots(chapter: Self.nkrv, verse: Self.verse)
        #expect(nkrvListed.map(\.rowID.raw) == [columnNKRV, columnNil])   // updateDate 최신순
        #expect(nkrvListed.allSatisfy { $0.translation == .NKRV })

        for english in [Self.kjv, Self.bsb] {
            #expect(try await harness.repository.load(chapter: english).snapshots.isEmpty)
            #expect(try await harness.database.fetchVerseSnapshots(chapter: english, verse: Self.verse).isEmpty)
            #expect(try await harness.database.fetchDrawingRecord(title: Self.title, translation: english.translation)
                    == BibleTitleDrawingRecord())
        }
        #expect(try await harness.database.fetchDrawingRecord(title: Self.title)
                == BibleTitleDrawingRecord(drawnChapters: [Self.chapterNumber], latestChapter: Self.chapterNumber))

        let activities = try await harness.activityRepository.activities(in: Self.window)
        #expect(activities.count == 2)
        #expect(activities.allSatisfy { $0.translation == .NKRV && $0.chapter == Self.nkrv })
    }

    @Test("다른 번역본의 같은 권 · 장 행은 저장 명령으로 주소지정되지 않는다")
    func replaceCannotAddressRowOfAnotherTranslation() async throws {
        let harness = try TranslationIsolationHarness()
        let nkrvRowID = try await harness.create(Self.nkrv, verse: Self.verse, data: Self.inkData)

        await #expect(throws: DrawingRepositoryError.rowNotFound(nkrvRowID)) {
            try await harness.apply(
                [.replace(verse: Self.verse, rowID: nkrvRowID, data: Data([7]), metadata: TranslationIsolationHarness.metadata(verse: Self.verse))],
                chapter: Self.kjv
            )
        }

        let rows = try harness.storedRows()
        #expect(rows.count == 1)
        #expect(rows.first?.lineData == Self.inkData)
        #expect(rows.first?.titleName == Self.title.rawValue)
    }

    // MARK: 대표 옮기기

    @Test("대표 옮기기(markPresent)는 그 번역본 행만 바꾼다")
    func markPresentChangesOnlyThatTranslation() async throws {
        let harness = try TranslationIsolationHarness()
        var older: [Translation: String] = [:]
        var newer: [Translation: String] = [:]
        for chapter in Self.allChapters {
            older[chapter.translation] = try harness.seed(chapter, lineData: Self.inkData, at: Self.base, isPresent: false)
            newer[chapter.translation] = try harness.seed(chapter, lineData: Self.inkData, at: Self.base + 100, isPresent: true)
        }
        let kjvOlder = try #require(older[.KJV])

        await harness.database.updatePresentDrawing(chapter: Self.kjv, verse: Self.verse, presentRowID: BibleDrawingRowID(raw: kjvOlder))

        let presence = Dictionary(uniqueKeysWithValues: try harness.storedRows().map { ($0.rowKey, $0.isPresent ?? false) })
        #expect(presence[kjvOlder] == true)
        #expect(presence[newer[.KJV] ?? ""] == false)
        for translation in [Translation.NKRV, .BSB] {
            #expect(presence[older[translation] ?? ""] == false)
            #expect(presence[newer[translation] ?? ""] == true)
        }

        let kjvListed = try await harness.database.fetchVerseSnapshots(chapter: Self.kjv, verse: Self.verse)
        #expect(kjvListed.representative()?.rowID.raw == kjvOlder)
        let nkrvListed = try await harness.database.fetchVerseSnapshots(chapter: Self.nkrv, verse: Self.verse)
        #expect(nkrvListed.representative()?.rowID.raw == newer[.NKRV])
    }

    // MARK: 권 기록 요약

    @Test("권의 필사 기록 요약은 번역본마다 따로 세고, 번역본을 생략하면 개역개정이다")
    func drawingRecordIsPerTranslation() async throws {
        let harness = try TranslationIsolationHarness()
        try harness.seed(BibleChapter(title: Self.title, chapter: 2, translation: .NKRV), lineData: Self.inkData, at: Self.base)
        try harness.seed(BibleChapter(title: Self.title, chapter: 1, translation: .KJV), lineData: Self.inkData, at: Self.base + 10)
        try harness.seed(BibleChapter(title: Self.title, chapter: 3, translation: .KJV), lineData: Self.inkData, at: Self.base + 300)
        // BSB 는 비운 행만 있다 — 기록이 아니다.
        try harness.seed(BibleChapter(title: Self.title, chapter: 2, translation: .BSB), lineData: nil, at: Self.base + 500)

        let database = harness.database
        #expect(try await database.fetchDrawingRecord(title: Self.title)
                == BibleTitleDrawingRecord(drawnChapters: [2], latestChapter: 2))
        #expect(try await database.fetchDrawingRecord(title: Self.title, translation: .NKRV)
                == BibleTitleDrawingRecord(drawnChapters: [2], latestChapter: 2))
        #expect(try await database.fetchDrawingRecord(title: Self.title, translation: .KJV)
                == BibleTitleDrawingRecord(drawnChapters: [1, 3], latestChapter: 3))
        #expect(try await database.fetchDrawingRecord(title: Self.title, translation: .BSB) == BibleTitleDrawingRecord())
    }

    // MARK: 지우기

    @Test("지우기 — 보관 행은 원래 행의 titleName · 열을 옮기고 다른 번역본 행은 그대로다")
    func eraseArchivesWithinTranslation() async throws {
        let harness = try TranslationIsolationHarness()
        var created: [Translation: BibleDrawingRowID] = [:]
        for chapter in Self.allChapters {
            created[chapter.translation] = try await harness.create(chapter, verse: Self.verse, data: Self.inkData)
        }
        let kjvActive = try #require(created[.KJV])
        let archiveRowID = BibleDrawingRowID.issue()

        let outcome = try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: Self.verse, activeRowID: kjvActive, archiveRowID: archiveRowID),
            chapter: Self.kjv
        )
        #expect(outcome == .archived)

        let rows = try harness.storedRows()
        #expect(rows.count == 4)
        let archived = try #require(rows.first { $0.rowKey == archiveRowID.raw })
        #expect(archived.titleName == "KJV-1-35Habakkuk.txt")
        #expect(archived.translation == nil)
        #expect(archived.isPresent == false)
        #expect(archived.lineData == Self.inkData)
        let active = try #require(rows.first { $0.rowKey == kjvActive.raw })
        #expect(active.lineData == nil)
        #expect(active.isPresent == true)

        for translation in [Translation.NKRV, .BSB] {
            let untouched = try #require(rows.first { $0.rowKey == created[translation]?.raw })
            #expect(untouched.lineData == Self.inkData)
            #expect(untouched.isPresent == true)
        }

        let kjvLoad = try await harness.repository.load(chapter: Self.kjv).snapshots
        #expect(Set(kjvLoad.map(\.rowID)) == [kjvActive, archiveRowID])
        #expect(kjvLoad.allSatisfy { $0.translation == .KJV })
        #expect(try await harness.repository.load(chapter: Self.nkrv).snapshots.map(\.rowID) == [created[.NKRV]].compactMap { $0 })
        #expect(try await harness.repository.load(chapter: Self.bsb).snapshots.map(\.rowID) == [created[.BSB]].compactMap { $0 })
    }

    @Test("지우기 — 개역개정 보관 행은 원래 행의 열을 그대로 옮긴다(옛 행 nil · 새 행 .NKRV)")
    func eraseCopiesNKRVColumnAsIs() async throws {
        let harness = try TranslationIsolationHarness()
        let legacyChapter = BibleChapter(title: Self.title, chapter: 1)
        let legacyActive = try harness.seed(legacyChapter, lineData: Self.inkData, at: Self.base, isPresent: true, column: .some(nil))
        let currentActive = try harness.seed(Self.nkrv, lineData: Self.inkData, at: Self.base, isPresent: true, column: .some(.NKRV))
        let legacyArchive = BibleDrawingRowID.issue()
        let currentArchive = BibleDrawingRowID.issue()

        #expect(try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: Self.verse, activeRowID: BibleDrawingRowID(raw: legacyActive), archiveRowID: legacyArchive),
            chapter: legacyChapter
        ) == .archived)
        #expect(try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: Self.verse, activeRowID: BibleDrawingRowID(raw: currentActive), archiveRowID: currentArchive),
            chapter: Self.nkrv
        ) == .archived)

        let rows = try harness.storedRows()
        let legacyArchived = try #require(rows.first { $0.rowKey == legacyArchive.raw })
        #expect(legacyArchived.titleName == Self.title.rawValue)
        #expect(legacyArchived.translation == nil)
        let currentArchived = try #require(rows.first { $0.rowKey == currentArchive.raw })
        #expect(currentArchived.titleName == Self.title.rawValue)
        #expect(currentArchived.translation == .NKRV)
    }

    // MARK: 필사 활동

    @Test("필사 활동은 모든 번역본의 행을 읽고 행마다 번역본을 싣는다 — 모르는 권 이름은 장이 nil 이다")
    func activitiesCarryTranslation() async throws {
        let harness = try TranslationIsolationHarness()
        for (offset, chapter) in Self.allChapters.enumerated() {
            try harness.seed(chapter, lineData: Self.inkData, at: Self.base + TimeInterval(offset * 10))
        }
        // 나중 버전이 만든 모르는 접두 — 지금처럼 활동에는 들고(날짜별 수), 장으로는 풀리지 않는다.
        try harness.seed(Self.nkrv, lineData: Self.inkData, at: Self.base + 100, titleName: "ESV-1-35Habakkuk.txt")

        let activities = try await harness.activityRepository.activities(in: Self.window)
        #expect(activities.count == 4)
        #expect(activities.compactMap(\.chapter) == [Self.bsb, Self.kjv, Self.nkrv])   // updateDate 최신순, 모르는 행은 빠진다
        #expect(activities.map(\.translation) == [nil, .BSB, .KJV, .NKRV])
        #expect(activities.first?.titleName == "ESV-1-35Habakkuk.txt")

        let recent = try await harness.activityRepository.recentActivities(limit: 10)
        #expect(recent == activities)
    }

    @Test("필사 활동 값 — 장으로 지으면 저장 행과 같은 titleName 이고, 접두 없는 권 이름은 개역개정으로 풀린다")
    func activityValueDecodesTranslation() {
        let english = DrawingActivity(updateDate: nil, chapter: Self.kjv, verse: 1)
        #expect(english.titleName == StoredBookKey.titleName(for: Self.kjv))
        #expect(english.chapter == Self.kjv)
        #expect(english.translation == .KJV)

        let legacy = DrawingActivity(updateDate: nil, titleName: Self.title.rawValue, titleChapter: Self.chapterNumber, verse: 1)
        #expect(legacy.chapter == Self.nkrv)
        #expect(legacy.translation == .NKRV)

        #expect(DrawingActivity(updateDate: nil, titleName: Self.title.rawValue, titleChapter: nil, verse: 1).chapter == nil)
        #expect(DrawingActivity(updateDate: nil, titleName: "Unknown.txt", titleChapter: 2, verse: 1).chapter == nil)
        #expect(DrawingActivity(updateDate: nil, titleName: nil, titleChapter: 2, verse: 1).translation == nil)
    }

    private static func makeInk(at seed: CGFloat) -> Data {
        let path = PKStrokePath(
            controlPoints: [PKStrokePoint(location: CGPoint(x: seed, y: seed), timeOffset: 0,
                                          size: CGSize(width: 2, height: 2), opacity: 1,
                                          force: 1, azimuth: 0, altitude: 0)],
            creationDate: Date(timeIntervalSince1970: 0)
        )
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
    }
}

// MARK: - 하네스

/// 시험 하나의 인메모리 저장소 — actor · 저장소 · 옛 클라이언트 · 활동 저장소가 같은 컨테이너를 본다.
private struct TranslationIsolationHarness {
    let actor: SwiftDatabaseActor
    let repository: SwiftDataDrawingRepository
    let database: DrawingDatabase
    let activityRepository: SwiftDataDrawingActivityRepository

    init() throws {
        let container = try ModelContainer(
            for: AppStoreSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let actor = SwiftDatabaseActor(modelContainer: container)
        let database = withDependencies {
            $0.createSwiftDataActor = actor
        } operation: {
            DrawingDatabase()
        }
        self.actor = actor
        self.repository = SwiftDataDrawingRepository(actor: actor)
        self.database = database
        self.activityRepository = SwiftDataDrawingActivityRepository(database: database)
    }

    static func metadata(verse: Int) -> DrawingLayoutMetadata {
        DrawingLayoutMetadata(
            baseWritingWidth: 372,
            baseWritingHeight: 60,
            baseUnderlineAnchors: [0, 30],
            layoutSignature: "cl1-test-\(verse)"
        )
    }

    /// 지금 세대로 저장 명령을 적용한다.
    func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter) async throws {
        let generation = try await repository.load(chapter: chapter).generation
        try await repository.apply(mutations, chapter: chapter, generation: generation)
    }

    /// 저장소 경로(`create`)로 새 행을 만든다.
    func create(_ chapter: BibleChapter, verse: Int, data: Data) async throws -> BibleDrawingRowID {
        let rowID = BibleDrawingRowID.issue()
        try await apply([.create(verse: verse, rowID: rowID, data: data, metadata: Self.metadata(verse: verse))], chapter: chapter)
        return rowID
    }

    /// 행을 시험 문맥으로 직접 심는다 — 모델은 actor 로 넘기지 않는다. actor 는 저장된 행을 읽는다.
    /// - Parameters:
    ///   - rowUUID: nil 이면 legacy 행(business `id` 가 행 키)이다.
    ///   - column: 넣으면 `translation` 열을 그 값으로 덮는다(`.some(nil)` = 열 nil 인 옛 행).
    ///   - titleName: 넣으면 `titleName` 을 그 값으로 덮는다(모르는 권 이름 흉내).
    /// - Returns: 행 키.
    @discardableResult
    func seed(
        _ chapter: BibleChapter,
        verse: Int = TranslationDrawingIsolationTesting.verse,
        rowUUID: String? = UUID().uuidString,
        lineData: Data?,
        at updateDate: Date,
        isPresent: Bool = true,
        column: Translation?? = .none,
        titleName: String? = nil
    ) throws -> String {
        let context = ModelContext(actor.modelContainer)
        let row = BibleDrawing(bibleTitle: chapter, verse: verse, lineData: lineData, updateDate: updateDate, rowUUID: rowUUID)
        if rowUUID == nil {
            // legacy business id 는 초 단위라 같은 초 두 행이 겹친다 — updateDate 의 초로 짓는다.
            row.id = "\(StoredBookKey.titleName(for: chapter)).\(chapter.chapter).\(verse).\(Int(updateDate.timeIntervalSince1970))"
        }
        row.isPresent = isPresent
        if case .some(let value) = column {
            row.translation = value
        }
        if let titleName {
            row.titleName = titleName
        }
        let rowKey = row.rowKey
        context.insert(row)
        try context.save()
        return rowKey
    }

    /// 저장된 행을 값으로 읽는다 — 새 문맥에서 읽고 모델은 들고 나오지 않는다.
    func storedRows() throws -> [TranslationIsolationRow] {
        try ModelContext(actor.modelContainer).fetch(FetchDescriptor<BibleDrawing>()).map(TranslationIsolationRow.init(row:))
    }
}

/// 저장된 행 한 줄의 값.
private struct TranslationIsolationRow {
    let rowKey: String
    let businessID: String?
    let titleName: String?
    let titleChapter: Int?
    let translation: Translation?
    let isPresent: Bool?
    let lineData: Data?

    init(row: BibleDrawing) {
        rowKey = row.rowKey
        let business: String? = row.id
        businessID = business
        titleName = row.titleName
        titleChapter = row.titleChapter
        translation = row.translation
        isPresent = row.isPresent
        lineData = row.lineData
    }
}
