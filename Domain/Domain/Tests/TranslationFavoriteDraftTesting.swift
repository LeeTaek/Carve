//
//  TranslationFavoriteDraftTesting.swift
//  DomainTest
//
//  번역본별 즐겨찾기 · 기기 안 초안 · 필기 가져오기 (영어 현지화 결정 1).
//  행의 번역본은 titleName 접두(`StoredBookKey`)로 정하고, SwiftData 의 translation 열에는 영어 값을 쓰지 않는다.
//  초안은 동기화하지 않는 로컬 파일이라 키 · 파일 이름에 실제 번역본을 쓴다.
//

@testable import Domain
import Foundation
import SwiftData
import Testing

/// 이 파일이 막는 것:
/// - 같은 절의 KJV · 개역개정 즐겨찾기가 한 항목으로 합쳐지거나, 하나를 해제하면 다른 하나까지 지워지는 것
/// - 영어 즐겨찾기 · 가져온 영어 필기 행의 translation 열에 영어 값을 쓰는 것(2.0.0 기기가 모르는 열거값을 디코딩하다 죽을 수 있다)
/// - 접두 없는 옛 행(열 nil)을 개역개정이 아닌 것으로 읽는 것, 모르는 접두의 행을 개역개정에 붙이는 것
/// - 영어 초안이 개역개정 장의 초안 · 요약 · 「확인이 필요한 필기」 목록에 섞이는 것
/// - 모르는 번역본의 초안을 개역개정 장으로 가져오는 것(정책 §8 「미상 판본을 임의 귀속하지 않음」)
@Suite("번역본별 즐겨찾기 · 초안 · 가져오기")
struct TranslationFavoriteDraftTesting {
    private static let psalm23 = BibleChapter(title: .psalms, chapter: 23)
    private static let psalm23KJV = BibleChapter(title: .psalms, chapter: 23, translation: .KJV)
    private static let genesis1 = BibleChapter(title: .genesis, chapter: 1)
    private static let genesis1KJV = BibleChapter(title: .genesis, chapter: 1, translation: .KJV)
    private static let account = AccountScope(key: "acct-a")

    // MARK: - 즐겨찾기

    private static func favorite(_ verse: Int, in chapter: BibleChapter, createdAt seconds: TimeInterval, sentence: String = "본문") -> FavoriteVerseSnapshot {
        FavoriteVerseSnapshot(
            key: FavoriteVerseKey(chapter: chapter, verse: verse), sentence: sentence, lineData: nil, createdDate: Date(timeIntervalSince1970: seconds)
        )
    }

    /// 저장소에 실제로 남은 즐겨찾기 행의 권 이름 · 열 · 절. 같은 컨테이너의 새 문맥으로 읽어 모델을 actor 밖으로 받지 않는다.
    private struct StoredFavoriteRow: Equatable {
        let titleName: String?
        let translation: Translation?
        let verse: Int?
    }

    private static func storedFavoriteRows(_ harness: FavoriteRepositoryHarness) throws -> [StoredFavoriteRow] {
        try ModelContext(harness.actor.modelContainer).fetch(FetchDescriptor<FavoriteVerse>())
            .map { StoredFavoriteRow(titleName: $0.titleName, translation: $0.translation, verse: $0.verse) }
            .sorted { ($0.titleName ?? "", $0.verse ?? 0) < ($1.titleName ?? "", $1.verse ?? 0) }
    }

    /// 다른 판의 앱 · 다른 기기가 남긴 행처럼 저장소를 거치지 않고 넣는다 — 권 이름과 열을 그대로 쓴다.
    private static func insertStoredFavorite(
        _ harness: FavoriteRepositoryHarness, titleName: String, column: Translation?, verse: Int, createdAt seconds: TimeInterval
    ) async throws {
        let row = FavoriteVerse(
            chapter: psalm23, verse: verse, translation: .NKRV, sentence: "다른 기기", lineData: nil, createdDate: Date(timeIntervalSince1970: seconds)
        )
        row.titleName = titleName
        row.translation = column
        try await harness.actor.insert(row)
    }

    @Test("즐겨찾기 키는 장의 번역본을 그대로 담는다 — 번역본을 따로 주면 장도 그 번역본이다")
    func favoriteKeyCarriesTheChapterTranslation() {
        let fromChapter = FavoriteVerseKey(chapter: Self.psalm23KJV, verse: 1)
        #expect(fromChapter.translation == .KJV)

        let explicit = FavoriteVerseKey(chapter: Self.psalm23, verse: 1, translation: .KJV)
        #expect(explicit.chapter == Self.psalm23KJV)
        #expect(explicit == fromChapter)
        #expect(FavoriteVerseKey(chapter: Self.psalm23, verse: 1) != fromChapter)
        #expect(FavoriteVerseKey(chapter: Self.psalm23, verse: 1).translation == .NKRV)
    }

    @Test("같은 절의 KJV · 개역개정 즐겨찾기는 따로 저장되고 따로 해제된다")
    func sameVerseFavoritesStaySeparatePerTranslation() async throws {
        let harness = try FavoriteRepositoryHarness()
        let korean = Self.favorite(1, in: Self.psalm23, createdAt: 100, sentence: "여호와는 나의 목자시니")
        let english = Self.favorite(1, in: Self.psalm23KJV, createdAt: 200, sentence: "The LORD is my shepherd")
        let englishSecond = Self.favorite(2, in: Self.psalm23KJV, createdAt: 300, sentence: "He maketh me to lie down")
        for favorite in [korean, english, englishSecond] {
            try await harness.repository.save(favorite)
        }

        #expect(try await harness.rowCount() == 3)
        #expect(try await harness.repository.favorites() == [englishSecond, english, korean])
        #expect(try await harness.repository.favoriteVerses(in: Self.psalm23, translation: .NKRV) == [1])
        #expect(try await harness.repository.favoriteVerses(in: Self.psalm23KJV, translation: .KJV) == [1, 2])
        #expect(try await harness.repository.favoriteVerses(in: Self.psalm23KJV, translation: .BSB).isEmpty)

        // 같은 키를 다시 저장해도 다른 번역본의 행은 건드리지 않는다.
        let replaced = Self.favorite(1, in: Self.psalm23KJV, createdAt: 400, sentence: "다시 추가")
        try await harness.repository.save(replaced)
        #expect(try await harness.rowCount() == 3)

        try await harness.repository.remove(english.key)
        #expect(try await harness.repository.favorites() == [englishSecond, korean])
        #expect(try await harness.repository.favoriteVerses(in: Self.psalm23, translation: .NKRV) == [1])
    }

    @Test("영어 즐겨찾기 행은 권 이름에 번역본 접두를 붙이고 translation 열을 비운다 — 개역개정 행은 지금 형식 그대로다")
    func englishFavoriteRowLeavesTheColumnEmpty() async throws {
        let harness = try FavoriteRepositoryHarness()
        try await harness.repository.save(Self.favorite(1, in: Self.psalm23, createdAt: 100))
        try await harness.repository.save(Self.favorite(1, in: Self.psalm23KJV, createdAt: 200))
        try await harness.repository.save(Self.favorite(5, in: BibleChapter(title: .psalms, chapter: 23, translation: .BSB), createdAt: 300))

        #expect(try Self.storedFavoriteRows(harness) == [
            StoredFavoriteRow(titleName: "1-19Psalms.txt", translation: .NKRV, verse: 1),
            StoredFavoriteRow(titleName: "BSB-1-19Psalms.txt", translation: nil, verse: 5),
            StoredFavoriteRow(titleName: "KJV-1-19Psalms.txt", translation: nil, verse: 1)
        ])
    }

    @Test("접두 없는 옛 행은 열이 비어 있어도 개역개정이고, 모르는 접두의 행은 어느 번역본에도 붙이지 않는다")
    func legacyRowIsKoreanAndUnknownPrefixIsSkipped() async throws {
        let harness = try FavoriteRepositoryHarness()
        try await Self.insertStoredFavorite(harness, titleName: "1-19Psalms.txt", column: nil, verse: 3, createdAt: 100)
        try await Self.insertStoredFavorite(harness, titleName: "ESV-1-19Psalms.txt", column: nil, verse: 4, createdAt: 200)
        try await Self.insertStoredFavorite(harness, titleName: "NKRV-1-19Psalms.txt", column: .NKRV, verse: 6, createdAt: 300)

        #expect(try await harness.repository.favorites().map(\.key) == [FavoriteVerseKey(chapter: Self.psalm23, verse: 3)])
        #expect(try await harness.repository.favoriteVerses(in: Self.psalm23, translation: .NKRV) == [3])
        #expect(try await harness.repository.favoriteVerses(in: Self.psalm23KJV, translation: .KJV).isEmpty)

        // 옛 행은 개역개정 키로 해제된다. 모르는 행은 남는다 — 지우지도 붙이지도 않는다.
        try await harness.repository.remove(FavoriteVerseKey(chapter: Self.psalm23, verse: 3))
        #expect(try await harness.rowCount() == 2)
    }

    // MARK: - 초안

    private struct Areas {
        let preservation: PreservationArea
        let eraseState: EraseStateArea
    }

    private func withWriter(_ body: (LocalPreservationWriter, Areas) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("translation-drafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let areas = Areas(
            preservation: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        )
        try await body(LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState), areas)
    }

    private static let metadata = DrawingLayoutMetadata(
        baseWritingWidth: 320, baseWritingHeight: 30, baseUnderlineAnchors: [0], layoutSignature: "cl1-translation"
    )

    /// 초안 하나. 잉크에는 좌표 정보가 붙는다 — 목록 · 가져오기가 놓을 자리를 안다.
    private static func draft(
        chapter: BibleChapter, verse: Int, session: String = "s1", ink: Data, account: VerseEditAccountBasis = .localOnly
    ) -> VerseDraft {
        VerseDraft(
            key: VerseDraftKey(sessionID: session, page: chapter.inDefaultNotebook, verse: verse),
            revision: 1,
            rowID: BibleDrawingRowID(raw: "draft-row-\(chapter.translation.rawValue)-\(verse)"),
            lineData: ink,
            drawingVersion: 3,
            layoutMetadataData: try? metadata.encodedBlob(),
            base: .empty,
            baseFingerprint: nil,
            account: account,
            knownEpochs: [],
            storeOwnership: nil,
            eraseGeneration: 0,
            savedAt: Date(timeIntervalSince1970: 1_000 + Double(verse))
        )
    }

    /// 다른 판의 앱이 남긴, 이 판이 모르는 번역본의 초안.
    private static func unknownTranslationDraft(verse: Int, ink: Data) -> VerseDraft {
        var unknown = draft(chapter: genesis1, verse: verse, ink: ink)
        unknown.key.translation = "ESV"
        return unknown
    }

    /// 지금 계정으로 소유가 확인된 환경 — 연결 전 묶음(`.localOnly`)을 열고, 동기화 저장소에 써도 된다.
    private static var owned: DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(account), serverWork: AccountServerWorkToken(scope: account, generation: 1), knowledge: EraseEpochKnowledge(),
            storeOwnership: account
        )
    }

    /// 장 조회만 답하는 빈 저장소 — 어느 장(번역본 포함 — 읽은 page 의 장)을 읽었는지 남긴다. 쓰기가 오면 시험이 깨진다.
    private actor EmptyChapterRepository: DrawingRepository {
        private(set) var loadedChapters: [BibleChapter] = []

        func load(_ page: NotebookChapter) async throws -> DrawingChapterLoad {
            loadedChapters.append(page.chapter)
            return DrawingChapterLoad(snapshots: [], generation: DrawingStoreGeneration(raw: 0))
        }

        func apply(_ mutations: [VerseDrawingMutation], page: NotebookChapter, generation: DrawingStoreGeneration) async throws {
            Issue.record("목록 · 가져오기 판정이 편집 저장 경로로 썼다")
        }

        func archiveAndReset(_ command: VerseDrawingArchiveCommand, page: NotebookChapter) async throws -> VerseDrawingArchiveOutcome {
            Issue.record("목록 · 가져오기 판정이 편집 저장 경로로 썼다")
            return .alreadyEmpty
        }
    }

    /// 가져오기의 저장소 쓰기 한 번 — 받은 명령과 그 장(명령의 page 의 장).
    private struct ImportCall: Sendable {
        let command: VerseDrawingImportCommand
        let chapter: BibleChapter
    }

    /// 가져오기의 저장소 쓰기를 받아 적기만 하는 대역.
    private actor ImportSpy: DrawingVerseImporting {
        private(set) var calls: [ImportCall] = []

        func importVerse(_ command: VerseDrawingImportCommand, generation: DrawingStoreGeneration) async throws -> VerseDrawingImportOutcome {
            calls.append(ImportCall(command: command, chapter: command.page.chapter))
            return .imported(previousKept: false)
        }
    }

    @Test("영어 초안은 번역본 이름으로 시작하는 파일에 남고, 파일 이름에서 번역본까지 되살린다 — 모르는 번역본은 장을 만들지 않는다")
    func englishDraftFileNameCarriesTheTranslation() async throws {
        try await withWriter { writer, areas in
            let saved = Self.draft(chapter: Self.genesis1KJV, verse: 1, ink: importInk(1))
            #expect(saved.key.translation == "KJV")
            #expect(saved.key.bibleChapter == Self.genesis1KJV)
            #expect(try await writer.saveDraft(saved) == .written)

            let files = try FileManager.default.subpathsOfDirectory(atPath: areas.preservation.draftsDirectory.path)
            #expect(files.contains { $0.hasSuffix("/KJV~1-01Genesis.txt~1~1.json") })

            #expect(VerseDraftKey.chapter(fromFileName: "KJV~1-01Genesis.txt~1~1.json") == Self.genesis1KJV)
            #expect(VerseDraftKey.chapter(fromFileName: "BSB~1-01Genesis.txt~1~1.json") == BibleChapter(title: .genesis, chapter: 1, translation: .BSB))
            #expect(VerseDraftKey.chapter(fromFileName: "NKRV~1-01Genesis.txt~1~1.json") == Self.genesis1)
            #expect(VerseDraftKey.chapter(fromFileName: "ESV~1-01Genesis.txt~1~1.json") == nil)
            #expect(Self.unknownTranslationDraft(verse: 1, ink: importInk(2)).key.bibleChapter == nil)
        }
    }

    @Test("한 장의 초안과 묶음 요약은 번역본을 나눈다 — 같은 권 · 장 · 절의 KJV 와 개역개정이 섞이지 않는다")
    func chapterDraftsAndSummaryArePerTranslation() async throws {
        try await withWriter { writer, _ in
            _ = try await writer.saveDraft(Self.draft(chapter: Self.genesis1, verse: 1, ink: importInk(1)))
            _ = try await writer.saveDraft(Self.draft(chapter: Self.genesis1KJV, verse: 1, ink: importInk(2)))
            _ = try await writer.saveDraft(Self.draft(chapter: Self.genesis1KJV, verse: 2, ink: importInk(3)))
            _ = try await writer.saveDraft(Self.unknownTranslationDraft(verse: 3, ink: importInk(4)))
            let scope = AccountScope.localOnly

            #expect(try await writer.drafts(in: scope, page: Self.genesis1.inDefaultNotebook).map(\.lineData) == [importInk(1)])
            #expect(try await writer.drafts(in: scope, page: Self.genesis1KJV.inDefaultNotebook).map(\.key.verse) == [1, 2])
            #expect(try await writer.drafts(in: scope, page: BibleChapter(title: .genesis, chapter: 1, translation: .BSB).inDefaultNotebook).isEmpty)

            let summary = try await writer.draftSummary(in: scope)
            // 모르는 번역본의 초안도 파일로는 센다 — 자리를 차지한다. 그 장은 어느 번역본에도 붙이지 않는다.
            #expect(summary.draftCount == 4)
            #expect(summary.draftCountByTranslation == [.NKRV: 1, .KJV: 2])
            #expect(summary.pages == [Self.genesis1.inDefaultNotebook, Self.genesis1KJV.inDefaultNotebook])
        }
    }

    @Test("모든 번역본을 모으는 목록은 KJV · 개역개정 초안을 함께 올리고, 번역본을 고른 목록은 그 번역본만 — 모르는 번역본은 어디에도 오르지 않는다")
    func inventoryAcrossTranslations() async throws {
        try await withWriter { writer, _ in
            _ = try await writer.saveDraft(Self.draft(chapter: Self.genesis1, verse: 1, ink: importInk(1)))
            _ = try await writer.saveDraft(Self.draft(chapter: Self.genesis1KJV, verse: 1, ink: importInk(2)))
            _ = try await writer.saveDraft(Self.draft(chapter: Self.genesis1KJV, verse: 2, ink: importInk(3)))
            _ = try await writer.saveDraft(Self.unknownTranslationDraft(verse: 3, ink: importInk(4)))
            let repository = EmptyChapterRepository()
            let query = VerseDraftRecoveryQuery(reader: writer, repository: repository)

            let all = try await query.inventoryAcrossTranslations(in: .localOnly, environment: Self.owned)
            #expect(all.comparedWithStore)
            #expect(all.unreadPages.isEmpty)
            #expect(Set(all.entries.map { "\($0.draft.key.translation)~\($0.draft.key.verse)" }) == ["NKRV~1", "KJV~1", "KJV~2"])
            #expect(all.entries.allSatisfy { $0.reason == .beforeConnection })
            // 영어 장은 영어 장으로 저장소와 견준다.
            #expect(await repository.loadedChapters.contains(Self.genesis1KJV))

            let korean = try await query.inventory(in: .localOnly, environment: Self.owned)
            #expect(korean.entries.map(\.draft.key.translation) == ["NKRV"])
            let english = try await query.inventory(in: .localOnly, environment: Self.owned, translation: .KJV)
            #expect(english.entries.map(\.draft.key.verse).sorted() == [1, 2])
            #expect(english.entries.allSatisfy { $0.draft.key.translation == "KJV" })

            #expect(await query.beforeConnectionCountAcrossTranslations(environment: Self.owned) == 3)
            #expect(await query.beforeConnectionCount(environment: Self.owned) == 1)
        }
    }

    @Test("KJV 초안을 가져오면 KJV 장으로 쓰고, 모르는 번역본의 초안은 쓰지 않고 건너뛴다")
    func importerRoutesByTranslation() async throws {
        try await withWriter { writer, _ in
            let english = Self.draft(chapter: Self.genesis1KJV, verse: 1, ink: importInk(1))
            let unknown = Self.unknownTranslationDraft(verse: 2, ink: importInk(2))
            _ = try await writer.saveDraft(english)
            _ = try await writer.saveDraft(unknown)
            let spy = ImportSpy()
            let importer = VerseDraftImporter(
                reader: writer, repository: EmptyChapterRepository(), writer: spy, marker: writer, now: { Date(timeIntervalSince1970: 5_000) }
            )

            let request = VerseDraftImportRequest(key: english.key, scope: .localOnly, revision: 1, expectedCurrentFingerprint: nil)
            #expect(request.chapter == Self.genesis1KJV)
            #expect(try await importer.importDraft(request, environment: Self.owned) == .imported(previousKept: false, recorded: true))
            let calls = await spy.calls
            #expect(calls.map(\.chapter) == [Self.genesis1KJV])
            #expect(calls.first?.command.page == NotebookChapter(notebook: .default, chapter: Self.genesis1KJV))

            let skipped = VerseDraftImportRequest(key: unknown.key, scope: .localOnly, revision: 1, expectedCurrentFingerprint: nil)
            #expect(skipped.chapter == nil)
            #expect(try await importer.importDraft(skipped, environment: Self.owned) == .draftChanged)
            #expect(await spy.calls.count == 1)
        }
    }

    // MARK: - 가져오기의 저장소 쓰기

    @Test("KJV 장으로 가져온 필기는 KJV 행(권 이름 접두 · 열 nil)으로 들어가고, 같은 절의 개역개정 필기는 그대로다")
    func importWritesTheEnglishRow() async throws {
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let actor = SwiftDatabaseActor(modelContainer: container)
        let repository = SwiftDataDrawingRepository(actor: actor)
        let koreanRow = BibleDrawingRowID.issue()
        let koreanPage = Self.genesis1.inDefaultNotebook
        let koreanGeneration = try await repository.load(koreanPage).generation
        try await repository.apply(
            [.create(verse: 1, rowID: koreanRow, data: importInk(1), metadata: Self.metadata)], page: koreanPage, generation: koreanGeneration
        )
        let command = VerseDrawingImportCommand(
            verse: 1, rowID: .issue(), lineData: importInk(2), metadata: Self.metadata, expectedCurrentFingerprint: nil,
            page: NotebookChapter(notebook: .default, chapter: Self.genesis1KJV)
        )

        let outcome = try await repository.importVerse(command, generation: koreanGeneration)

        // 개역개정 행은 KJV 절의 지금 필기가 아니다 — 견줄 것이 없어 이전 기록으로 남길 것도 없다.
        #expect(outcome == .imported(previousKept: false))
        let rows = try ModelContext(container).fetch(FetchDescriptor<BibleDrawing>())
        #expect(rows.count == 2)
        let korean = try #require(rows.first { $0.rowKey == koreanRow.raw })
        #expect(korean.titleName == "1-01Genesis.txt")
        #expect(korean.isPresent == true)
        #expect(korean.lineData == importInk(1))
        let english = try #require(rows.first { $0.rowKey == command.rowID.raw })
        #expect(english.titleName == "KJV-1-01Genesis.txt")
        #expect(english.translation == nil)
        #expect(english.titleChapter == 1)
        #expect(english.verse == 1)
        #expect(english.isPresent == true)
        #expect(english.lineData == importInk(2))
    }
}
