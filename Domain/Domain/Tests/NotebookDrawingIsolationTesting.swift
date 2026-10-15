//
//  NotebookDrawingIsolationTesting.swift
//  DomainTest
//
//  2.2 「회차별 필사책」 결정 1 — 필사 행(`BibleDrawing`)의 저장 · 조회를 필사책별로 가른다.
//  같은 권 · 장 · 절 · 번역본의 기본 · 필사책 A · B 행이 장 조회 · 저장 명령 · 지우기 · 절 이력 · 대표 옮기기 · 권 기록 요약에서
//  서로 섞이지 않고, 기본 필사책 행은 지금 형식 그대로(혼재 버전 규칙 ①), 다른 필사책 행은 `titleName` 접두로만 갈리는지 고정한다.
//  활동(차트)은 모든 필사책의 행을 합산하고(결정 10), 옛 앱의 술어(`titleName ==` 권 rawValue)는 접두 행을 잡지 않는다(2.0 · 2.1 흉내).
//  시험마다 인메모리 컨테이너를 따로 연다 — 공유 actor(`createSwiftDataActor.testValue`)를 쓰지 않는다. @Model 은 컨테이너를 연 뒤 만든다.
//

@testable import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import Dependencies

@Suite("회차별 필사책 — 필사 행의 필사책 격리")
struct NotebookDrawingIsolationTesting {
    fileprivate static let title = BibleTitle.jonah
    fileprivate static let chapterNumber = 2
    fileprivate static let verse = 3
    fileprivate static let chapter = BibleChapter(title: title, chapter: chapterNumber, translation: .NKRV)
    fileprivate static let notebookA = NotebookID.make(uuid: UUID(uuidString: "0F3A9C2E-7B41-4D6A-9E15-2C8B7D04A1F3")!)
    fileprivate static let notebookB = NotebookID.make(uuid: UUID(uuidString: "A1B2C3D4-E5F6-4789-8ABC-DEF012345678")!)
    fileprivate static let defaultPage = NotebookChapter(notebook: .default, chapter: chapter)
    fileprivate static let pageA = NotebookChapter(notebook: notebookA, chapter: chapter)
    fileprivate static let pageB = NotebookChapter(notebook: notebookB, chapter: chapter)
    fileprivate static let allPages = [defaultPage, pageA, pageB]
    fileprivate static let base = Date(timeIntervalSince1970: 1_700_000_000)
    private static let window = DateInterval(start: base - 1_000, end: base + 10_000)

    /// 실제 획이 하나 있는 `PKDrawing` 데이터. 바이트로 견주므로 한 번 만들어 재사용한다(만들 때마다 바이트가 다르다).
    private static let inkData: Data = makeInk(at: 5)

    // MARK: 새 행

    @Test("새 행 — 기본 필사책은 titleName · 열 · id 가 지금과 같고, 다른 필사책은 titleName 접두만 다르다")
    func newRowsUseNotebookPrefix() async throws {
        // Given: 같은 권 · 장 · 절 · 번역본에 세 필사책의 행을 저장소 경로로 만든다.
        let harness = try NotebookIsolationHarness()
        var created: [NotebookID: BibleDrawingRowID] = [:]
        for page in Self.allPages {
            created[page.notebook] = try await harness.create(page, verse: Self.verse, data: Self.inkData)
        }
        // 옛 장 경로(`chapter:`)로 만든 행 — 기본 필사책 행이 2.2 이전과 같은 형식인지 견줄 기준이다.
        let legacyPathRowID = BibleDrawingRowID.issue()
        let generation = try await harness.repository.load(chapter: Self.chapter).generation
        try await harness.repository.apply(
            [.create(verse: 7, rowID: legacyPathRowID, data: Self.inkData, metadata: NotebookIsolationHarness.metadata(verse: 7))],
            chapter: Self.chapter, generation: generation
        )
        // 행이 없는 절의 clear 도 새 행을 만든다 — 그 경로도 그 필사책의 행이다.
        let clearedRowID = BibleDrawingRowID.issue()
        try await harness.apply([.clear(verse: 9, rowID: clearedRowID)], page: Self.pageA)

        // Then
        let rows = try harness.storedRows()
        #expect(rows.count == 5)

        let defaultRow = try #require(rows.first { $0.rowKey == created[.default]?.raw })
        let legacyPathRow = try #require(rows.first { $0.rowKey == legacyPathRowID.raw })
        #expect(defaultRow.titleName == "1-32Jonah.txt")
        #expect(defaultRow.titleName == legacyPathRow.titleName)
        #expect(defaultRow.translation == .NKRV)
        #expect(defaultRow.translation == legacyPathRow.translation)
        #expect(defaultRow.businessID?.hasPrefix("1-32Jonah.txt.2.3.") == true)
        #expect(legacyPathRow.businessID?.hasPrefix("1-32Jonah.txt.2.7.") == true)

        let rowA = try #require(rows.first { $0.rowKey == created[Self.notebookA]?.raw })
        #expect(rowA.titleName == "nb_0f3a9c2e7b414d6a9e152c8b7d04a1f3~1-32Jonah.txt")
        #expect(rowA.titleName == StoredBookKey.titleName(for: Self.pageA))
        #expect(rowA.translation == .NKRV)   // 열은 번역본으로만 정한다 — 필사책을 열에 적지 않는다(혼재 버전 규칙 ②)
        #expect(rowA.businessID?.hasPrefix("nb_0f3a9c2e7b414d6a9e152c8b7d04a1f3~1-32Jonah.txt.2.3.") == true)

        let rowB = try #require(rows.first { $0.rowKey == created[Self.notebookB]?.raw })
        #expect(rowB.titleName == StoredBookKey.titleName(for: Self.pageB))
        #expect(rowB.translation == .NKRV)

        let clearedRow = try #require(rows.first { $0.rowKey == clearedRowID.raw })
        #expect(clearedRow.titleName == StoredBookKey.titleName(for: Self.pageA))
        #expect(clearedRow.lineData == nil)

        #expect(rows.allSatisfy { $0.titleChapter == Self.chapterNumber })
    }

    @Test("새 행 — 다른 필사책의 영어 행은 번역본 접두 앞에 필사책 접두가 붙고 열은 nil 이다")
    func englishRowInNotebookKeepsTranslationRule() async throws {
        let harness = try NotebookIsolationHarness()
        let kjvPage = NotebookChapter(notebook: Self.notebookA, chapter: BibleChapter(title: Self.title, chapter: Self.chapterNumber, translation: .KJV))

        let rowID = try await harness.create(kjvPage, verse: Self.verse, data: Self.inkData)

        let row = try #require(try harness.storedRows().first { $0.rowKey == rowID.raw })
        #expect(row.titleName == "nb_0f3a9c2e7b414d6a9e152c8b7d04a1f3~KJV-1-32Jonah.txt")
        #expect(row.translation == nil)
        let loaded = try await harness.repository.load(kjvPage).snapshots
        #expect(loaded.map(\.rowID) == [rowID])
        #expect(loaded.allSatisfy { $0.translation == .KJV && $0.notebook == Self.notebookA })
        #expect(try await harness.repository.load(Self.pageA).snapshots.isEmpty)
    }

    // MARK: 조회

    @Test("장 조회 · 절 이력 조회는 그 필사책 행만 읽고 스냅샷에 필사책을 싣는다 — 저장소 계약(any)으로 불러도 같다")
    func loadAndVerseSnapshotsAreIsolated() async throws {
        let harness = try NotebookIsolationHarness()
        var created: [NotebookID: BibleDrawingRowID] = [:]
        for page in Self.allPages {
            created[page.notebook] = try await harness.create(page, verse: Self.verse, data: Self.inkData)
        }
        // 과도기 기본 구현(`unsupportedNotebook`)이 아니라 SwiftData 구현이 불려야 한다.
        let contract: any DrawingRepository = harness.repository

        for page in Self.allPages {
            let expected = [created[page.notebook]].compactMap { $0 }
            let loaded = try await contract.load(page).snapshots
            #expect(loaded.map(\.rowID) == expected)
            #expect(loaded.allSatisfy { $0.notebook == page.notebook && $0.translation == .NKRV })

            let listed = try await harness.database.fetchVerseSnapshots(page: page, verse: Self.verse)
            #expect(listed.map(\.rowID) == expected)
            #expect(listed.allSatisfy { $0.notebook == page.notebook })
        }

        // 옛 장 경로는 기본 필사책이다.
        let legacyLoad = try await harness.repository.load(chapter: Self.chapter)
        let defaultLoad = try await harness.repository.load(Self.defaultPage)
        #expect(legacyLoad == defaultLoad)
        let legacyListed = try await harness.database.fetchVerseSnapshots(chapter: Self.chapter, verse: Self.verse)
        let defaultListed = try await harness.database.fetchVerseSnapshots(page: Self.defaultPage, verse: Self.verse)
        #expect(legacyListed == defaultListed)
    }

    @Test("다른 필사책의 같은 권 · 장 행은 저장 명령으로 주소지정되지 않는다")
    func replaceCannotAddressRowOfAnotherNotebook() async throws {
        let harness = try NotebookIsolationHarness()
        let rowIDA = try await harness.create(Self.pageA, verse: Self.verse, data: Self.inkData)
        let replace = VerseDrawingMutation.replace(
            verse: Self.verse, rowID: rowIDA, data: Data([7]), metadata: NotebookIsolationHarness.metadata(verse: Self.verse)
        )

        for page in [Self.defaultPage, Self.pageB] {
            await #expect(throws: DrawingRepositoryError.rowNotFound(rowIDA)) {
                try await harness.apply([replace], page: page)
            }
        }

        let rows = try harness.storedRows()
        #expect(rows.count == 1)
        #expect(rows.first?.lineData == Self.inkData)
        #expect(rows.first?.titleName == StoredBookKey.titleName(for: Self.pageA))
    }

    // MARK: 지우기

    @Test("지우기 — A 에서 지우면 A 의 보관 행만 생기고 다른 필사책 행의 내용 · isPresent 는 그대로다")
    func eraseArchivesWithinNotebook() async throws {
        let harness = try NotebookIsolationHarness()
        var created: [NotebookID: BibleDrawingRowID] = [:]
        for page in Self.allPages {
            created[page.notebook] = try await harness.create(page, verse: Self.verse, data: Self.inkData)
        }
        // 다른 필사책에는 보관 행(`isPresent == false`)도 있다 — 지우기가 건드리지 않아야 한다.
        let defaultArchived = try harness.seed(Self.defaultPage, lineData: Self.inkData, at: Self.base, isPresent: false)
        let archivedB = try harness.seed(Self.pageB, lineData: Self.inkData, at: Self.base, isPresent: false)
        let before = try harness.storedRows()
        let activeA = try #require(created[Self.notebookA])
        let archiveRowID = BibleDrawingRowID.issue()

        let outcome = try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: Self.verse, activeRowID: activeA, archiveRowID: archiveRowID),
            page: Self.pageA
        )

        #expect(outcome == .archived)
        let rows = try harness.storedRows()
        #expect(rows.count == before.count + 1)
        let archived = try #require(rows.first { $0.rowKey == archiveRowID.raw })
        #expect(archived.titleName == StoredBookKey.titleName(for: Self.pageA))
        #expect(archived.translation == .NKRV)
        #expect(archived.isPresent == false)
        #expect(archived.lineData == Self.inkData)
        let active = try #require(rows.first { $0.rowKey == activeA.raw })
        #expect(active.lineData == nil)
        #expect(active.isPresent == true)

        // A 밖의 행은 한 줄도 바뀌지 않았다.
        let untouchedKeys = Set([created[.default], created[Self.notebookB]].compactMap { $0?.raw } + [defaultArchived, archivedB])
        let beforeByKey = Dictionary(uniqueKeysWithValues: before.map { ($0.rowKey, $0) })
        for row in rows where untouchedKeys.contains(row.rowKey) {
            let original = try #require(beforeByKey[row.rowKey])
            #expect(row.isPresent == original.isPresent)
            #expect(row.lineData == original.lineData)
            #expect(row.titleName == original.titleName)
        }

        let loadA = try await harness.repository.load(Self.pageA).snapshots
        let loadDefault = try await harness.repository.load(Self.defaultPage).snapshots
        let loadB = try await harness.repository.load(Self.pageB).snapshots
        #expect(Set(loadA.map(\.rowID)) == [activeA, archiveRowID])
        #expect(Set(loadDefault.map(\.rowID.raw)) == Set([created[.default]?.raw, defaultArchived].compactMap { $0 }))
        #expect(Set(loadB.map(\.rowID.raw)) == Set([created[Self.notebookB]?.raw, archivedB].compactMap { $0 }))
    }

    @Test("지우기 — 다른 필사책의 활성 행을 가리키면 그 필사책에서는 비어 있는 것으로 보고 아무것도 쓰지 않는다")
    func eraseCannotAddressRowOfAnotherNotebook() async throws {
        let harness = try NotebookIsolationHarness()
        let activeDefault = try await harness.create(Self.defaultPage, verse: Self.verse, data: Self.inkData)

        let outcome = try await harness.repository.archiveAndReset(
            VerseDrawingArchiveCommand(verse: Self.verse, activeRowID: activeDefault, archiveRowID: BibleDrawingRowID.issue()),
            page: Self.pageA
        )

        #expect(outcome == .alreadyEmpty)
        let rows = try harness.storedRows()
        #expect(rows.count == 1)
        #expect(rows.first?.lineData == Self.inkData)
        #expect(rows.first?.isPresent == true)
    }

    // MARK: 대표 옮기기

    @Test("대표 옮기기(updatePresentDrawing)는 그 필사책 행만 바꾼다")
    func markPresentChangesOnlyThatNotebook() async throws {
        let harness = try NotebookIsolationHarness()
        var older: [NotebookID: String] = [:]
        var newer: [NotebookID: String] = [:]
        for page in Self.allPages {
            older[page.notebook] = try harness.seed(page, lineData: Self.inkData, at: Self.base, isPresent: false)
            newer[page.notebook] = try harness.seed(page, lineData: Self.inkData, at: Self.base + 100, isPresent: true)
        }
        let olderA = try #require(older[Self.notebookA])

        await harness.database.updatePresentDrawing(page: Self.pageA, verse: Self.verse, presentRowID: BibleDrawingRowID(raw: olderA))

        let presence = Dictionary(uniqueKeysWithValues: try harness.storedRows().map { ($0.rowKey, $0.isPresent ?? false) })
        #expect(presence[olderA] == true)
        #expect(presence[newer[Self.notebookA] ?? ""] == false)
        for notebook in [NotebookID.default, Self.notebookB] {
            #expect(presence[older[notebook] ?? ""] == false)
            #expect(presence[newer[notebook] ?? ""] == true)
        }

        let listedA = try await harness.database.fetchVerseSnapshots(page: Self.pageA, verse: Self.verse)
        #expect(listedA.representative()?.rowID.raw == olderA)
        let listedDefault = try await harness.database.fetchVerseSnapshots(page: Self.defaultPage, verse: Self.verse)
        #expect(listedDefault.representative()?.rowID.raw == newer[.default])
    }

    // MARK: 권 기록 요약

    @Test("권의 필사 기록 요약은 필사책마다 따로 세고, 옛 호출은 기본 필사책이다")
    func drawingRecordIsPerNotebook() async throws {
        let harness = try NotebookIsolationHarness()
        try harness.seed(Self.page(chapter: 1, notebook: .default), lineData: Self.inkData, at: Self.base)
        try harness.seed(Self.page(chapter: 2, notebook: Self.notebookA), lineData: Self.inkData, at: Self.base + 10)
        try harness.seed(Self.page(chapter: 4, notebook: Self.notebookA), lineData: Self.inkData, at: Self.base + 300)
        // B 는 비운 행만 있다 — 기록이 아니다.
        try harness.seed(Self.page(chapter: 3, notebook: Self.notebookB), lineData: nil, at: Self.base + 500)

        let database = harness.database
        #expect(try await database.fetchDrawingRecord(notebook: .default, title: Self.title, translation: .NKRV)
                == BibleTitleDrawingRecord(drawnChapters: [1], latestChapter: 1))
        #expect(try await database.fetchDrawingRecord(notebook: Self.notebookA, title: Self.title, translation: .NKRV)
                == BibleTitleDrawingRecord(drawnChapters: [2, 4], latestChapter: 4))
        #expect(try await database.fetchDrawingRecord(notebook: Self.notebookB, title: Self.title, translation: .NKRV)
                == BibleTitleDrawingRecord())
        // 필사책 A 의 개역개정 행은 A 의 KJV 기록이 아니다.
        #expect(try await database.fetchDrawingRecord(notebook: Self.notebookA, title: Self.title, translation: .KJV)
                == BibleTitleDrawingRecord())
        #expect(try await database.fetchDrawingRecord(title: Self.title)
                == BibleTitleDrawingRecord(drawnChapters: [1], latestChapter: 1))
    }

    // MARK: 필사 활동

    @Test("필사 활동은 모든 필사책의 행을 page 로 돌려준다 — 장은 필사책과 무관하게 같고, 깨진 접두는 장이 nil 이다")
    func activitiesCarryAllNotebooks() async throws {
        let harness = try NotebookIsolationHarness()
        for (offset, page) in Self.allPages.enumerated() {
            try harness.seed(page, lineData: Self.inkData, at: Self.base + TimeInterval(offset * 10))
        }
        // 형식이 깨진 접두(기본 필사책 토큰) — 활동에는 들고(날짜별 수), 장으로는 풀리지 않는다.
        try harness.seed(Self.defaultPage, lineData: Self.inkData, at: Self.base + 100, titleName: "nb_default~1-32Jonah.txt")

        let activities = try await harness.activityRepository.activities(in: Self.window)
        #expect(activities.count == 4)
        #expect(activities.compactMap(\.page) == [Self.pageB, Self.pageA, Self.defaultPage])   // updateDate 최신순
        #expect(activities.compactMap(\.chapter) == [Self.chapter, Self.chapter, Self.chapter])   // 장별 수는 합산(결정 10)
        #expect(activities.map(\.translation) == [nil, .NKRV, .NKRV, .NKRV])
        #expect(activities.first?.titleName == "nb_default~1-32Jonah.txt")
        #expect(activities.first?.page == nil)

        let recent = try await harness.activityRepository.recentActivities(limit: 10)
        #expect(recent == activities)
    }

    @Test("필사 활동 값 — page 로 지으면 저장 행과 같은 titleName 이고, 옛 장 이니셜라이저는 기본 필사책이다")
    func activityValueDecodesNotebook() {
        let activityA = DrawingActivity(updateDate: nil, page: Self.pageA, verse: 1)
        #expect(activityA.titleName == StoredBookKey.titleName(for: Self.pageA))
        #expect(activityA.page == Self.pageA)
        #expect(activityA.chapter == Self.chapter)
        #expect(activityA.translation == .NKRV)

        let legacy = DrawingActivity(updateDate: nil, chapter: Self.chapter, verse: 1)
        #expect(legacy.titleName == Self.title.rawValue)
        #expect(legacy.page == Self.defaultPage)

        #expect(DrawingActivity(updateDate: nil, titleName: StoredBookKey.titleName(for: Self.pageB), titleChapter: nil, verse: 1).page == nil)
        #expect(DrawingActivity(updateDate: nil, titleName: StoredBookKey.titleName(for: Self.pageB), titleChapter: nil, verse: 1).translation == .NKRV)
    }

    // MARK: 옛 앱 흉내

    @Test("옛 앱의 술어(titleName == 권 rawValue)와 풀기는 접두 행을 잡지 않는다 — 기본 필사책 행만 본다")
    func legacyPredicateSkipsNotebookRows() async throws {
        let harness = try NotebookIsolationHarness()
        var created: [NotebookID: BibleDrawingRowID] = [:]
        for page in Self.allPages {
            created[page.notebook] = try await harness.create(page, verse: Self.verse, data: Self.inkData)
        }
        let kjvPageA = NotebookChapter(notebook: Self.notebookA, chapter: BibleChapter(title: Self.title, chapter: Self.chapterNumber, translation: .KJV))
        let kjvRowA = try await harness.create(kjvPageA, verse: Self.verse, data: Self.inkData)

        // 2.0.0 의 장 조회 · 2.1 의 번역본 조회와 같은 모양의 술어를 같은 저장소에 직접 건다.
        let context = ModelContext(harness.actor.modelContainer)
        let rawValue = Self.title.rawValue
        let kjvTitleName = StoredBookKey.titleName(title: Self.title, translation: .KJV, notebook: .default)
        let chapterNumber = Self.chapterNumber
        let nkrvKeys = try context.fetch(FetchDescriptor(predicate: #Predicate<BibleDrawing> {
            $0.titleName == rawValue && $0.titleChapter == chapterNumber
        })).map(\.rowKey)
        let kjvKeys = try context.fetch(FetchDescriptor(predicate: #Predicate<BibleDrawing> {
            $0.titleName == kjvTitleName && $0.titleChapter == chapterNumber
        })).map(\.rowKey)

        #expect(nkrvKeys == [created[.default]?.raw].compactMap { $0 })
        #expect(kjvKeys.isEmpty)

        // 옛 앱은 모르는 titleName 을 풀지 못해 건너뛴다 — 2.0.0 은 `BibleTitle(rawValue:)`, 2.1 은 번역본 접두 + `BibleTitle(rawValue:)`.
        for row in try harness.storedRows() where row.rowKey != created[.default]?.raw {
            let titleName = try #require(row.titleName)
            #expect(BibleTitle(rawValue: titleName) == nil)
            #expect(Self.decodeAs21(titleName) == nil)
            #expect(StoredBookKey.decodeRow(titleName) != nil)
        }
        let defaultTitleName = try #require(try harness.storedRows().first { $0.rowKey == created[.default]?.raw }?.titleName)
        #expect(Self.decodeAs21(defaultTitleName) == Self.title)
        #expect(try harness.storedRows().contains { $0.rowKey == kjvRowA.raw })
    }

    // MARK: 도움

    /// 2.1 이 행의 `titleName` 을 권으로 풀던 방식 그대로(지금 코드와 무관하게 고정) — 접두 없는 권 rawValue 또는 `KJV-` · `BSB-` + 권 rawValue.
    private static func decodeAs21(_ titleName: String) -> BibleTitle? {
        if let title = BibleTitle(rawValue: titleName) { return title }
        for prefix in ["KJV-", "BSB-"] where titleName.hasPrefix(prefix) {
            return BibleTitle(rawValue: String(titleName.dropFirst(prefix.count)))
        }
        return nil
    }

    private static func page(chapter number: Int, notebook: NotebookID) -> NotebookChapter {
        NotebookChapter(notebook: notebook, chapter: BibleChapter(title: title, chapter: number, translation: .NKRV))
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
private struct NotebookIsolationHarness {
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

    /// 지금 세대로 저장 명령을 필사책 경로로 적용한다.
    func apply(_ mutations: [VerseDrawingMutation], page: NotebookChapter) async throws {
        let generation = try await repository.load(page).generation
        try await repository.apply(mutations, page: page, generation: generation)
    }

    /// 저장소 경로(`create`)로 새 행을 만든다.
    func create(_ page: NotebookChapter, verse: Int, data: Data) async throws -> BibleDrawingRowID {
        let rowID = BibleDrawingRowID.issue()
        try await apply([.create(verse: verse, rowID: rowID, data: data, metadata: Self.metadata(verse: verse))], page: page)
        return rowID
    }

    /// 행을 시험 문맥으로 직접 심는다 — 모델은 actor 로 넘기지 않는다. actor 는 저장된 행을 읽는다.
    /// - Parameter titleName: 넣으면 `titleName` 을 그 값으로 덮는다(깨진 접두 흉내).
    /// - Returns: 행 키.
    @discardableResult
    func seed(
        _ page: NotebookChapter,
        verse: Int = NotebookDrawingIsolationTesting.verse,
        lineData: Data?,
        at updateDate: Date,
        isPresent: Bool = true,
        titleName: String? = nil
    ) throws -> String {
        let context = ModelContext(actor.modelContainer)
        let row = BibleDrawing(page: page, verse: verse, lineData: lineData, updateDate: updateDate, rowUUID: UUID().uuidString)
        row.isPresent = isPresent
        if let titleName {
            row.titleName = titleName
        }
        let rowKey = row.rowKey
        context.insert(row)
        try context.save()
        return rowKey
    }

    /// 저장된 행을 값으로 읽는다 — 새 문맥에서 읽고 모델은 들고 나오지 않는다.
    func storedRows() throws -> [NotebookIsolationRow] {
        try ModelContext(actor.modelContainer).fetch(FetchDescriptor<BibleDrawing>()).map(NotebookIsolationRow.init(row:))
    }
}

/// 저장된 행 한 줄의 값.
private struct NotebookIsolationRow {
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
