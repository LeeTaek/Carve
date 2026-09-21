//
//  FavoriteVerseRepositoryTesting.swift
//  DomainTest
//
//  즐겨찾기 저장소 — 추가 당시 보존 · 최근 추가순 · 키(번역본 · 권 · 장 · 절)로 합치기 · 해제가 필사 행을 건드리지 않음.
//  격리된 인메모리 컨테이너로 돈다 — 테스트끼리 공유 상태가 없다.
//

@testable import Domain
import Foundation
import SwiftData
import Testing

/// 테스트마다 새 인메모리 컨테이너 + actor + repository. 앱과 같은 엔티티 셋(V5)이다.
struct FavoriteRepositoryHarness {
    let actor: SwiftDatabaseActor
    let repository: SwiftDataFavoriteVerseRepository

    init() throws {
        let container = try ModelContainer(
            for: AppStoreSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        actor = SwiftDatabaseActor(modelContainer: container)
        repository = SwiftDataFavoriteVerseRepository(actor: actor)
    }

    /// 저장소를 거치지 않고 센 즐겨찾기 행 수 — 중복 행이 합쳐졌는지 본다.
    func rowCount() async throws -> Int {
        let rows: [FavoriteVerse] = try await actor.fetch(FetchDescriptor<FavoriteVerse>())
        return rows.count
    }

    /// CloudKit 이 다른 기기에서 실어 온 행처럼 저장소를 거치지 않고 넣는다.
    func insertRow(verse: Int, chapter: BibleChapter, sentence: String, createdAt seconds: TimeInterval) async throws {
        try await actor.insert(FavoriteVerse(
            chapter: chapter,
            verse: verse,
            translation: .NKRV,
            sentence: sentence,
            lineData: nil,
            createdDate: Date(timeIntervalSince1970: seconds)
        ))
    }
}

@Suite("즐겨찾기 — FavoriteVerseRepository (SwiftData)")
struct FavoriteVerseRepositoryTesting {
    private static let psalm23 = BibleChapter(title: .psalms, chapter: 23)
    private static let psalm24 = BibleChapter(title: .psalms, chapter: 24)

    private static func favorite(
        _ verse: Int,
        in chapter: BibleChapter = psalm23,
        createdAt seconds: TimeInterval,
        lineData: Data? = nil,
        sentence: String = "본문"
    ) -> FavoriteVerseSnapshot {
        FavoriteVerseSnapshot(
            key: FavoriteVerseKey(chapter: chapter, verse: verse),
            sentence: sentence,
            lineData: lineData,
            createdDate: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test("저장한 즐겨찾기는 장의 절 표시와 목록에 추가 당시의 본문 · 필기 · 시각 그대로 나온다")
    func savedFavoriteKeepsSnapshot() async throws {
        let harness = try FavoriteRepositoryHarness()
        let saved = Self.favorite(1, createdAt: 100, lineData: Data([7, 7, 7]), sentence: "여호와는 나의 목자시니")

        try await harness.repository.save(saved)

        #expect(try await harness.repository.favoriteVerses(in: Self.psalm23, translation: .NKRV) == [1])
        #expect(try await harness.repository.favorites() == [saved])
    }

    @Test("목록은 장이 달라도 최근 추가순이다")
    func favoritesAreNewestFirst() async throws {
        let harness = try FavoriteRepositoryHarness()
        let oldest = Self.favorite(3, createdAt: 100)
        let newest = Self.favorite(1, in: Self.psalm24, createdAt: 300)
        let middle = Self.favorite(2, createdAt: 200)
        for favorite in [oldest, newest, middle] {
            try await harness.repository.save(favorite)
        }

        #expect(try await harness.repository.favorites() == [newest, middle, oldest])
    }

    @Test("장의 절 표시는 그 장의 즐겨찾기만 담는다")
    func versesAreScopedToChapter() async throws {
        let harness = try FavoriteRepositoryHarness()
        try await harness.repository.save(Self.favorite(1, createdAt: 100))
        try await harness.repository.save(Self.favorite(4, createdAt: 110))
        try await harness.repository.save(Self.favorite(1, in: Self.psalm24, createdAt: 120))

        #expect(try await harness.repository.favoriteVerses(in: Self.psalm23, translation: .NKRV) == [1, 4])
        #expect(try await harness.repository.favoriteVerses(in: Self.psalm24, translation: .NKRV) == [1])
        #expect(try await harness.repository.favoriteVerses(in: BibleChapter(title: .psalms, chapter: 25), translation: .NKRV).isEmpty)
    }

    @Test("같은 절을 다시 저장하면 행을 늘리지 않고 새 값으로 바꾼다")
    func savingSameKeyReplacesInPlace() async throws {
        let harness = try FavoriteRepositoryHarness()
        try await harness.repository.save(Self.favorite(1, createdAt: 100, lineData: Data([1])))
        let replaced = Self.favorite(1, createdAt: 200, lineData: Data([2]), sentence: "다시 추가")

        try await harness.repository.save(replaced)

        #expect(try await harness.rowCount() == 1)
        #expect(try await harness.repository.favorites() == [replaced])
    }

    @Test("다른 기기가 따로 만든 같은 절의 행은 목록에서 가장 최근 하나로 보이고, 해제하면 모두 지워진다")
    func duplicateRowsCollapseAndRemoveTogether() async throws {
        let harness = try FavoriteRepositoryHarness()
        // CloudKit 은 unique 제약이 없어 두 기기가 같은 절을 따로 추가하면 행이 둘이 된다.
        try await harness.insertRow(verse: 1, chapter: Self.psalm23, sentence: "기기 A", createdAt: 100)
        try await harness.insertRow(verse: 1, chapter: Self.psalm23, sentence: "기기 B", createdAt: 200)

        #expect(try await harness.repository.favorites().map(\.sentence) == ["기기 B"])
        #expect(try await harness.repository.favoriteVerses(in: Self.psalm23, translation: .NKRV) == [1])

        try await harness.repository.remove(FavoriteVerseKey(chapter: Self.psalm23, verse: 1))

        #expect(try await harness.rowCount() == 0)
        #expect(try await harness.repository.favorites().isEmpty)
    }

    @Test("중복 행이 있는 절을 이 기기에서 다시 저장하면 한 행으로 합친다")
    func savingCollapsesDuplicates() async throws {
        let harness = try FavoriteRepositoryHarness()
        try await harness.insertRow(verse: 1, chapter: Self.psalm23, sentence: "기기 A", createdAt: 100)
        try await harness.insertRow(verse: 1, chapter: Self.psalm23, sentence: "기기 B", createdAt: 200)
        let saved = Self.favorite(1, createdAt: 300, sentence: "이 기기")

        try await harness.repository.save(saved)

        #expect(try await harness.rowCount() == 1)
        #expect(try await harness.repository.favorites() == [saved])
    }

    @Test("해제는 즐겨찾기만 지운다 — 같은 절의 필사 행은 그대로다")
    func removingFavoriteKeepsDrawings() async throws {
        let harness = try FavoriteRepositoryHarness()
        try await harness.actor.insert(BibleDrawing(bibleTitle: Self.psalm23, verse: 1, lineData: Data([1, 2, 3]), rowUUID: "row-1"))
        try await harness.repository.save(Self.favorite(1, createdAt: 100, lineData: Data([1, 2, 3])))

        try await harness.repository.remove(FavoriteVerseKey(chapter: Self.psalm23, verse: 1))

        let drawings: [BibleDrawing] = try await harness.actor.fetch(FetchDescriptor<BibleDrawing>())
        #expect(drawings.map(\.rowKey) == ["row-1"])
        #expect(drawings.first?.lineData == Data([1, 2, 3]))
        #expect(try await harness.repository.favorites().isEmpty)
    }

    @Test("해제한 항목을 그대로 다시 저장하면 추가 시각이 같아 원래 순서로 돌아간다 — 실행 취소")
    func restoringRemovedFavoriteKeepsOrder() async throws {
        let harness = try FavoriteRepositoryHarness()
        let newer = Self.favorite(1, createdAt: 300)
        let middle = Self.favorite(2, createdAt: 200)
        let older = Self.favorite(3, createdAt: 100)
        for favorite in [newer, middle, older] {
            try await harness.repository.save(favorite)
        }

        try await harness.repository.remove(middle.key)
        #expect(try await harness.repository.favorites() == [newer, older])

        try await harness.repository.save(middle)
        #expect(try await harness.repository.favorites() == [newer, middle, older])
    }

    @Test("권 이름을 해석할 수 없는 행은 목록에 올리지 않는다")
    func unreadableRowsAreSkipped() async throws {
        let harness = try FavoriteRepositoryHarness()
        let broken = FavoriteVerse()
        broken.titleName = "unknown.txt"
        broken.titleChapter = 1
        broken.verse = 1
        broken.createdDate = Date(timeIntervalSince1970: 500)
        try await harness.actor.insert(broken)
        let valid = Self.favorite(1, createdAt: 100)
        try await harness.repository.save(valid)

        #expect(try await harness.repository.favorites() == [valid])
    }

    @Test("없는 즐겨찾기를 해제해도 오류가 아니다")
    func removingMissingFavoriteIsNoOp() async throws {
        let harness = try FavoriteRepositoryHarness()

        try await harness.repository.remove(FavoriteVerseKey(chapter: Self.psalm23, verse: 9))

        #expect(try await harness.rowCount() == 0)
    }
}
