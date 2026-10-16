//
//  NotebookDraftTesting.swift
//  DomainTest
//
//  필사책별 기기 안 초안 · 「확인이 필요한 필기」 · 가져오기 (2.2 「회차별 필사책」).
//  기본 필사책의 초안은 키 · 파일 이름 모두 2.2 이전 그대로이고, 그 밖의 필사책은 파일 이름 앞에 `nb_<토큰>~` 이 붙는다.
//  격리된 임시 보존 영역 · 인메모리 컨테이너로 돈다.
//

@testable import Domain
import Dependencies
import Foundation
import SwiftData
import Testing

/// 필사책별 초안 시험이 함께 쓰는 표본 · 보존 영역.
private enum NotebookDraftSample {
    static let notebookA = NotebookID.make(uuid: UUID(uuidString: "0F3A9C2E-7B41-4D6A-9E15-2C8B7D04A1F3")!)
    static let notebookB = NotebookID.make(uuid: UUID(uuidString: "5D1E8B20-3C47-4F9A-A6E2-90B1C7D3E4F5")!)
    static let genesis1 = BibleChapter(title: .genesis, chapter: 1)
    static let genesis1KJV = BibleChapter(title: .genesis, chapter: 1, translation: .KJV)
    static let account = AccountScope(key: "acct-a")

    static func page(_ notebook: NotebookID, _ chapter: BibleChapter) -> NotebookChapter {
        NotebookChapter(notebook: notebook, chapter: chapter)
    }

    // MARK: - 보존 영역

    struct Areas {
        let preservation: PreservationArea
        let eraseState: EraseStateArea
    }

    static func withWriter(_ body: (LocalPreservationWriter, Areas) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notebook-drafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let areas = Areas(
            preservation: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        )
        try await body(LocalPreservationWriter(area: areas.preservation, eraseState: areas.eraseState), areas)
    }

    static let metadata = DrawingLayoutMetadata(
        baseWritingWidth: 320, baseWritingHeight: 30, baseUnderlineAnchors: [0], layoutSignature: "cl1-notebook-draft"
    )

    /// 초안 하나. 잉크에는 좌표 정보가 붙는다 — 목록 · 가져오기가 놓을 자리를 안다. 기본 계정 근거는 연결 전(이 기기 전용) 필기다.
    static func draft(
        page: NotebookChapter, verse: Int, session: String = "s1", ink: Data, account: VerseEditAccountBasis = .localOnly
    ) -> VerseDraft {
        VerseDraft(
            key: VerseDraftKey(sessionID: session, page: page, verse: verse),
            revision: 1,
            rowID: BibleDrawingRowID(raw: "draft-row-\(page.notebook.rawValue)-\(verse)"),
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

    /// 지금 계정으로 소유가 확인된 환경 — 연결 전 묶음(`.localOnly`)을 열고, 동기화 저장소에 써도 된다.
    static var owned: DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(account), serverWork: AccountServerWorkToken(scope: account, generation: 1), knowledge: EraseEpochKnowledge(),
            storeOwnership: account
        )
    }

    /// 저장소의 대표 행 하나 — 초안과 같은 규칙으로 지문이 만들어진다.
    static func row(verse: Int, rowID: String, ink: Data) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: rowID), isPresent: true, updateDate: Date(timeIntervalSince1970: 500),
            lineData: ink, drawingVersion: 3, metadata: metadata
        )
    }
}

// MARK: - 대역

/// 필사책 안의 장 조회만 답하는 저장소 — 어느 page 를 읽었는지 남긴다. 쓰기가 오면 시험이 깨진다.
private actor NotebookPageRepository: DrawingRepository {
    private let pages: [NotebookChapter: [VerseDrawingSnapshot]]
    private let broken: Set<NotebookChapter>
    private(set) var loadedPages: [NotebookChapter] = []

    init(_ pages: [NotebookChapter: [VerseDrawingSnapshot]] = [:], broken: Set<NotebookChapter> = []) {
        self.pages = pages
        self.broken = broken
    }

    func load(_ page: NotebookChapter) async throws -> DrawingChapterLoad {
        loadedPages.append(page)
        if broken.contains(page) { throw DrawingRepositoryError.persistenceFailed("시험 — 이 장을 읽지 못한다") }
        return DrawingChapterLoad(snapshots: pages[page] ?? [], generation: DrawingStoreGeneration(raw: 0))
    }

    func apply(_ mutations: [VerseDrawingMutation], page: NotebookChapter, generation: DrawingStoreGeneration) async throws {
        Issue.record("목록 · 가져오기 판정이 편집 저장 경로로 썼다")
    }

    func archiveAndReset(_ command: VerseDrawingArchiveCommand, page: NotebookChapter) async throws -> VerseDrawingArchiveOutcome {
        Issue.record("목록 · 가져오기 판정이 편집 저장 경로로 썼다")
        return .alreadyEmpty
    }
}

/// 가져오기의 저장소 쓰기를 받아 적기만 하는 대역.
private actor NotebookImportSpy: DrawingVerseImporting {
    private(set) var commands: [VerseDrawingImportCommand] = []
    /// 쓰기가 놓일 장(번역본 포함) — 명령의 page 의 장이다.
    private(set) var chapters: [BibleChapter] = []

    func importVerse(_ command: VerseDrawingImportCommand, generation: DrawingStoreGeneration) async throws -> VerseDrawingImportOutcome {
        commands.append(command)
        chapters.append(command.page.chapter)
        return .imported(previousKept: false)
    }
}

/// 이 파일이 막는 것:
/// - 다른 필사책의 초안이 같은 장 · 절의 기본 필사책 초안으로 읽히거나 섞이는 것, 옛 초안(필사책 없음)을 기본 필사책이 아닌 것으로 읽는 것
/// - 요약이 필사책을 가르지 못해 「확인이 필요한 필기」 가 다른 필사책의 장을 기본 필사책의 장으로 대조하는 것
/// - 다른 필사책의 초안을 기본 필사책의 대표와 견주어 엉뚱하게 분류하는 것, 가져오기가 기본 필사책 행을 바꾸는 것
/// - 필사책 하나를 지우며 다른 필사책 · 기본 필사책의 초안까지 지우는 것
@Suite("필사책별 초안 — 키 · 요약 · 지우기")
struct NotebookDraftTesting {
    private typealias Sample = NotebookDraftSample

    // MARK: - 키 · 파일 이름

    @Test("필사책 A 의 초안은 nb_<토큰>~ 으로 시작하는 파일에 남고, 파일 이름 · JSON 모두 필사책까지 되살린다")
    func notebookDraftFileNameRoundTrips() async throws {
        try await Sample.withWriter { writer, areas in
            let pageA = Sample.page(Sample.notebookA, Sample.genesis1KJV)
            let saved = Sample.draft(page: pageA, verse: 1, ink: importInk(1))
            let fileName = "nb_\(Sample.notebookA.rawValue)~KJV~1-01Genesis.txt~1~1.json"
            #expect(saved.key.notebook == Sample.notebookA)
            #expect(saved.key.page == pageA)
            #expect(saved.key.bibleChapter == Sample.genesis1KJV)
            #expect(saved.key.fileName == fileName)
            #expect(try await writer.saveDraft(saved) == .written)

            let files = try FileManager.default.subpathsOfDirectory(atPath: areas.preservation.draftsDirectory.path)
            #expect(files.contains { $0.hasSuffix("/" + fileName) })
            #expect(VerseDraftKey.page(fromFileName: fileName) == pageA)
            #expect(VerseDraftKey.chapter(fromFileName: fileName) == Sample.genesis1KJV)
            #expect(VerseDraftKey.notebook(fromFileName: fileName) == Sample.notebookA)

            // JSON 도 필사책을 담는다.
            let decoded = try JSONDecoder().decode(VerseDraftKey.self, from: JSONEncoder().encode(saved.key))
            #expect(decoded == saved.key)
            #expect(try await writer.drafts(in: .localOnly, page: pageA).map(\.key) == [saved.key])
            #expect(try await writer.drafts(in: .localOnly).map(\.key.notebook) == [Sample.notebookA])
        }
    }

    @Test("같은 장 · 절이라도 필사책이 다르면 따로 읽힌다")
    func chapterDraftsArePerNotebook() async throws {
        try await Sample.withWriter { writer, _ in
            let pageDefault = Sample.page(.default, Sample.genesis1KJV)
            let pageA = Sample.page(Sample.notebookA, Sample.genesis1KJV)
            _ = try await writer.saveDraft(Sample.draft(page: pageDefault, verse: 1, ink: importInk(1)))
            _ = try await writer.saveDraft(Sample.draft(page: pageA, verse: 1, ink: importInk(2)))
            _ = try await writer.saveDraft(Sample.draft(page: Sample.page(Sample.notebookB, Sample.genesis1KJV), verse: 1, ink: importInk(3)))

            #expect(try await writer.drafts(in: .localOnly, page: pageDefault).map(\.lineData) == [importInk(1)])
            #expect(try await writer.drafts(in: .localOnly, page: pageA).map(\.lineData) == [importInk(2)])
            #expect(try await writer.drafts(in: .localOnly, page: Sample.page(Sample.notebookA, Sample.genesis1)).isEmpty)
        }
    }

    @Test("옛 파일 이름 · 필사책이 없는 옛 JSON 은 기본 필사책이다 — 형식이 틀린 접두는 초안으로 치지 않는다")
    func legacyNamesAndKeysAreDefaultNotebook() throws {
        #expect(VerseDraftKey.page(fromFileName: "KJV~1-01Genesis.txt~1~1.json") == Sample.page(.default, Sample.genesis1KJV))
        #expect(VerseDraftKey.page(fromFileName: "NKRV~1-01Genesis.txt~1~1.json") == Sample.page(.default, Sample.genesis1))
        #expect(VerseDraftKey.notebook(fromFileName: "NKRV~1-01Genesis.txt~1~1.json") == .default)
        #expect(VerseDraftKey(sessionID: "s1", page: Sample.page(.default, Sample.genesis1), verse: 1).fileName == "NKRV~1-01Genesis.txt~1~1.json")

        let token = Sample.notebookA.rawValue
        for malformed in [
            "nb_default~KJV~1-01Genesis.txt~1~1.json",
            "nb_\(token.uppercased())~KJV~1-01Genesis.txt~1~1.json",
            "nb_\(token.dropLast())~KJV~1-01Genesis.txt~1~1.json",
            "nb_\(token)KJV~1-01Genesis.txt~1~1.json",
            "nb_\(token)~1-01Genesis.txt~1~1.json"
        ] {
            #expect(VerseDraftKey.page(fromFileName: malformed) == nil, "\(malformed)")
            #expect(!VerseDraftKey.hasDraftFileShape(malformed), "\(malformed)")
        }
        // 모르는 번역본이어도 필사책 초안의 모양이다 — 장은 짓지 않지만 필사책은 안다(그 필사책을 지울 때 함께 지운다).
        let unknownTranslation = "nb_\(token)~ESV~1-01Genesis.txt~1~1"
        #expect(VerseDraftKey.hasDraftFileShape(unknownTranslation))
        #expect(VerseDraftKey.page(fromFileName: unknownTranslation) == nil)
        #expect(VerseDraftKey.notebook(fromFileName: unknownTranslation) == Sample.notebookA)

        // 2.2 이전 초안의 키 — `notebook` 이 없다.
        let legacy = #"{"chapter":1,"sessionID":"legacy","title":"1-01Genesis.txt","translation":"KJV","verse":3}"#
        let key = try JSONDecoder().decode(VerseDraftKey.self, from: Data(legacy.utf8))
        #expect(key == VerseDraftKey(sessionID: "legacy", page: Sample.page(.default, Sample.genesis1KJV), verse: 3))
        #expect(key.notebook == .default)
        // 형식이 틀린 필사책은 기본 필사책으로 바꿔 읽지 않는다.
        let broken = #"{"chapter":1,"notebook":"NOT-A-TOKEN","sessionID":"s","title":"1-01Genesis.txt","translation":"KJV","verse":3}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(VerseDraftKey.self, from: Data(broken.utf8)) }
    }

    @Test("묶음 요약은 필사책을 가른다 — page 목록은 기본 필사책 먼저, 기본 필사책 page 는 기본 필사책 초안의 장만")
    func summarySeparatesNotebooks() async throws {
        try await Sample.withWriter { writer, _ in
            _ = try await writer.saveDraft(Sample.draft(page: Sample.page(.default, Sample.genesis1KJV), verse: 1, ink: importInk(1)))
            _ = try await writer.saveDraft(Sample.draft(page: Sample.page(Sample.notebookA, Sample.genesis1KJV), verse: 1, ink: importInk(2)))
            _ = try await writer.saveDraft(Sample.draft(page: Sample.page(Sample.notebookA, Sample.genesis1), verse: 2, ink: importInk(3)))

            let summary = try await writer.draftSummary(in: .localOnly)
            #expect(summary.draftCount == 3)
            #expect(summary.draftCountByTranslation == [.KJV: 2, .NKRV: 1])
            #expect(summary.pages == [
                Sample.page(.default, Sample.genesis1KJV), Sample.page(Sample.notebookA, Sample.genesis1), Sample.page(Sample.notebookA, Sample.genesis1KJV)
            ])
            #expect(summary.pages.filter(\.notebook.isDefault).map(\.chapter) == [Sample.genesis1KJV])
        }
    }

    // MARK: - 필사책 지우기

    @Test("discardDrafts(notebook:) 는 모든 묶음에서 그 필사책의 초안 · 옆으로 옮긴 파일만 지운다 — 기본 필사책은 지우지 않는다")
    func discardRemovesOnlyThatNotebook() async throws {
        try await Sample.withWriter { writer, areas in
            let confirmed = VerseEditAccountBasis.confirmed(AccountServerWorkToken(scope: Sample.account, generation: 1))
            let pageDefault = Sample.page(.default, Sample.genesis1KJV)
            let pageA = Sample.page(Sample.notebookA, Sample.genesis1KJV)
            let pageB = Sample.page(Sample.notebookB, Sample.genesis1KJV)
            _ = try await writer.saveDraft(Sample.draft(page: pageDefault, verse: 1, ink: importInk(1)))
            _ = try await writer.saveDraft(Sample.draft(page: pageA, verse: 1, ink: importInk(2)))
            _ = try await writer.saveDraft(Sample.draft(page: pageA, verse: 2, ink: importInk(3), account: confirmed))
            _ = try await writer.saveDraft(Sample.draft(page: pageB, verse: 1, ink: importInk(4)))
            // 읽지 못해 옆으로 옮긴 파일 — A 의 것과 기본 필사책의 것.
            let session = areas.preservation.draftsDirectory
                .appendingPathComponent(AccountScope.localOnly.key, isDirectory: true).appendingPathComponent("s1", isDirectory: true)
            let asideA = session.appendingPathComponent("nb_\(Sample.notebookA.rawValue)~KJV~1-01Genesis.txt~1~9.unreadable-\(UUID().uuidString)")
            let asideDefault = session.appendingPathComponent("KJV~1-01Genesis.txt~1~9.unreadable-\(UUID().uuidString)")
            try Data("깨짐".utf8).write(to: asideA)
            try Data("깨짐".utf8).write(to: asideDefault)

            #expect(try await writer.discardDrafts(notebook: .default) == 0)
            #expect(try await writer.drafts(in: .localOnly, page: pageDefault).count == 1)

            #expect(try await writer.discardDrafts(notebook: Sample.notebookA) == 3)
            #expect(try await writer.drafts(in: .localOnly, page: pageA).isEmpty)
            #expect(try await writer.drafts(in: Sample.account, page: pageA).isEmpty)
            #expect(!FileManager.default.fileExists(atPath: asideA.path))
            #expect(FileManager.default.fileExists(atPath: asideDefault.path))
            #expect(try await writer.drafts(in: .localOnly, page: pageDefault).count == 1)
            #expect(try await writer.drafts(in: .localOnly, page: pageB).count == 1)
            let summary = try await writer.draftSummary(in: .localOnly)
            #expect(summary.pages == [pageDefault, pageB])
            #expect(summary.unreadableCount == 1)

            // 다시 불러도 지울 것이 없다.
            #expect(try await writer.discardDrafts(notebook: Sample.notebookA) == 0)
        }
    }

    @Test("필사책 지우기의 초안 버리기는 따로 넣지 않으면 앱이 넣은 보존 영역을 쓴다")
    func discarderFallsBackToTheWriter() async throws {
        try await Sample.withWriter { writer, _ in
            var values = DependencyValues()
            #expect(values.notebookDraftDiscarder == nil)
            values.localPreservationWriter = writer
            #expect(values.notebookDraftDiscarder is LocalPreservationWriter)
        }
    }
}

/// 필사책별 「확인이 필요한 필기」 · 가져오기 — 초안은 그 필사책의 대표와 견주고 그 필사책의 행으로 넣는다.
@Suite("필사책별 확인이 필요한 필기 · 가져오기")
struct NotebookDraftRecoveryTesting {
    private typealias Sample = NotebookDraftSample

    // MARK: - 확인이 필요한 필기

    @Test("복구 목록은 초안을 그 필사책의 대표와 견준다 — A 의 대표와 같은 A 초안은 오르지 않고, 기본 필사책의 같은 내용은 오른다")
    func inventoryComparesWithTheNotebookRepresentative() async throws {
        try await Sample.withWriter { writer, _ in
            let pageDefault = Sample.page(.default, Sample.genesis1KJV)
            let pageA = Sample.page(Sample.notebookA, Sample.genesis1KJV)
            let pageB = Sample.page(Sample.notebookB, Sample.genesis1KJV)
            let defaultDraft = Sample.draft(page: pageDefault, verse: 1, ink: importInk(1))
            _ = try await writer.saveDraft(defaultDraft)
            _ = try await writer.saveDraft(Sample.draft(page: pageA, verse: 1, ink: importInk(1)))
            _ = try await writer.saveDraft(Sample.draft(page: pageB, verse: 1, ink: importInk(2)))
            // A 의 1절에는 이미 같은 필기가 있다. 기본 필사책의 1절은 비었다. B 는 읽지 못한다.
            let representative = Sample.row(verse: 1, rowID: "row-a-1", ink: importInk(1))
            let repository = NotebookPageRepository([pageA: [representative]], broken: [pageB])
            let query = VerseDraftRecoveryQuery(reader: writer, repository: repository)

            let inventory = try await query.inventoryAcrossTranslations(in: .localOnly, environment: Sample.owned)

            #expect(inventory.comparedWithStore)
            #expect(inventory.entries.map(\.draft.key) == [defaultDraft.key])
            #expect(inventory.entries.map(\.reason) == [.beforeConnection])
            #expect(inventory.unreadPages == [pageB])
            #expect(inventory.unreadPages.map(\.chapter) == [Sample.genesis1KJV])
            #expect(Set(await repository.loadedPages) == [pageDefault, pageA, pageB])

            #expect(try await query.currentVerse(page: pageA, verse: 1) == representative)
            #expect(try await query.currentVerse(page: pageDefault, verse: 1) == nil)
            #expect(await query.beforeConnectionCountAcrossTranslations(environment: Sample.owned) == 1)
        }
    }

    // MARK: - 가져오기

    @Test("A 초안을 가져오면 A 의 대표와 견주고 A 의 page 로 쓴다 — 끝난 뒤 알릴 도착도 A 의 page 다")
    func importerRoutesToTheDraftNotebook() async throws {
        try await Sample.withWriter { writer, _ in
            let pageA = Sample.page(Sample.notebookA, Sample.genesis1KJV)
            let draftA = Sample.draft(page: pageA, verse: 1, ink: importInk(2))
            _ = try await writer.saveDraft(draftA)
            // 기본 필사책의 같은 절에는 다른 필기가 있다 — A 의 1절은 비었으므로 넣기다.
            let repository = NotebookPageRepository([Sample.page(.default, Sample.genesis1KJV): [Sample.row(verse: 1, rowID: "row-default-1", ink: importInk(1))]])
            let spy = NotebookImportSpy()
            let importer = VerseDraftImporter(
                reader: writer, repository: repository, writer: spy, marker: writer, now: { Date(timeIntervalSince1970: 5_000) }
            )

            let request = VerseDraftImportRequest(key: draftA.key, scope: .localOnly, revision: 1, expectedCurrentFingerprint: nil)
            #expect(request.page == pageA)
            #expect(try await importer.importDraft(request, environment: Sample.owned) == .imported(previousKept: false, recorded: true))
            #expect(await repository.loadedPages == [pageA])
            let commands = await spy.commands
            #expect(commands.map(\.page) == [pageA])
            #expect(await spy.chapters == [Sample.genesis1KJV])
            let recorded = try await writer.drafts(in: .localOnly, page: pageA).first?.imported
            #expect(recorded?.rowID == commands.first?.rowID)

            let arrival = LocalDrawingChange(page: pageA, date: Date(timeIntervalSince1970: 5_000))
            #expect(arrival.chapter == Sample.genesis1KJV)
            #expect(arrival != LocalDrawingChange(page: Sample.page(.default, Sample.genesis1KJV), date: Date(timeIntervalSince1970: 5_000)))
        }
    }

    @Test("A 로 가져온 필기는 A 의 행(nb_ 접두 · 열은 번역본대로)으로 들어가고, 같은 절의 기본 필사책 행은 그대로다")
    func importWritesTheNotebookRow() async throws {
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let actor = SwiftDatabaseActor(modelContainer: container)
        let repository = SwiftDataDrawingRepository(actor: actor)
        let defaultRow = BibleDrawingRowID.issue()
        let pageDefault = Sample.page(.default, Sample.genesis1)
        let generation = try await repository.load(pageDefault).generation
        try await repository.apply(
            [.create(verse: 1, rowID: defaultRow, data: importInk(1), metadata: Sample.metadata)], page: pageDefault, generation: generation
        )
        let pageA = Sample.page(Sample.notebookA, Sample.genesis1)
        let command = VerseDrawingImportCommand(
            verse: 1, rowID: .issue(), lineData: importInk(2), metadata: Sample.metadata, expectedCurrentFingerprint: nil, page: pageA
        )

        // A 의 1절은 비었다 — 기본 필사책 행은 A 의 지금 필기가 아니다.
        #expect(try await repository.importVerse(command, generation: generation) == .imported(previousKept: false))
        // A 에 한 번 더 가져오면 A 의 옛 행만 대표에서 내린다.
        let blob = try Sample.metadata.encodedBlob()
        let second = VerseDrawingImportCommand(
            verse: 1, rowID: .issue(), lineData: importInk(3), metadata: Sample.metadata,
            expectedCurrentFingerprint: VerseContentFingerprint.make(lineData: importInk(2), drawingVersion: 3, layoutMetadataBlob: blob),
            page: pageA
        )
        #expect(try await repository.importVerse(second, generation: generation) == .imported(previousKept: true))

        let rows = try ModelContext(container).fetch(FetchDescriptor<BibleDrawing>())
        #expect(rows.count == 3)
        let original = try #require(rows.first { $0.rowKey == defaultRow.raw })
        #expect(original.titleName == "1-01Genesis.txt")
        #expect(original.isPresent == true)
        #expect(original.lineData == importInk(1))
        let first = try #require(rows.first { $0.rowKey == command.rowID.raw })
        #expect(first.titleName == "nb_\(Sample.notebookA.rawValue)~1-01Genesis.txt")
        #expect(first.translation == .NKRV)
        #expect(first.isPresent == false)
        let latest = try #require(rows.first { $0.rowKey == second.rowID.raw })
        #expect(latest.titleName == "nb_\(Sample.notebookA.rawValue)~1-01Genesis.txt")
        #expect(latest.isPresent == true)
        #expect(latest.lineData == importInk(3))
    }
}
