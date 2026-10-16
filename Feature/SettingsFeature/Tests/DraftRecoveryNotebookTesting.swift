//
//  DraftRecoveryNotebookTesting.swift
//  SettingsFeatureTest
//
//  설정 → 「확인이 필요한 필기」 의 필사책(2.2 회차별 필사책) — 필사책마다 따로 한 줄씩 보이고, 기본이 아닌 필사책은 자리 앞에 필사책 이름을
//  붙이며, 견주기 · 넣기는 그 필사책의 page 로 간다. 실제 보존 영역(임시 폴더)과 인메모리 저장소로 잇는다.
//

import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import ComposableArchitecture

@testable import SettingsFeature

// MARK: - 대역

/// 열린 필사 화면에 보낸 알림을 적는다. 저장 프로퍼티가 `let` 과 `LockIsolated` 뿐이라 Sendable 을 컴파일러가 확인한다.
private final class NotebookChangeRecorder: LocalDrawingChangeClient {
    let posted = LockIsolated<[LocalDrawingChange]>([])

    func post(_ change: LocalDrawingChange) { posted.withValue { $0.append(change) } }
    func changes() -> AsyncStream<LocalDrawingChange> { AsyncStream { $0.finish() } }
}

/// 정해 둔 필사책 목록을 돌려주고 읽은 횟수를 센다. `fails` 면 읽지 못한다. 이 화면은 필사책을 만들거나 바꾸지 않는다.
private struct NotebookListStub: NotebookRepository {
    struct CannotRead: Error {}
    let snapshots: [NotebookSnapshot]
    var fails = false
    let reads = LockIsolated(0)

    func notebooks() async throws -> [NotebookSnapshot] {
        reads.withValue { $0 += 1 }
        if fails { throw CannotRead() }
        return snapshots
    }

    func create(id: NotebookID, name: String, now: Date) async throws { Issue.record("확인이 필요한 필기 화면이 필사책을 만들었다") }
    func rename(_ id: NotebookID, to name: String, now: Date) async throws { Issue.record("확인이 필요한 필기 화면이 필사책 이름을 바꿨다") }
    func setCompleted(_ id: NotebookID, _ completed: Bool, now: Date) async throws { Issue.record("확인이 필요한 필기 화면이 완료를 표시했다") }
    func delete(_ id: NotebookID) async throws { Issue.record("확인이 필요한 필기 화면이 필사책을 지웠다") }
}

/// 실제 stroke 가 있는 필기 — 한 번만 만든다(`dataRepresentation()` 은 부를 때마다 다른 바이트를 낸다).
private let notebookInks: [Data] = (0..<4).map { offset in
    let points = (0..<6).map { index in
        PKStrokePoint(
            location: CGPoint(x: Double(index * 14 + offset), y: Double(offset * 3)), timeOffset: Double(index) * 0.02,
            size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
        )
    }
    let stroke = PKStroke(
        ink: PKInk(.pen, color: .black),
        path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
    )
    return PKDrawing(strokes: [stroke]).dataRepresentation()
}

/// 이 파일이 막는 것:
/// - 두 필사책에 같은 절의 초안이 있을 때 한 줄로 겹치거나(같은 id), 어느 필사책의 것인지 보이지 않는 것
/// - 지운 필사책 · 이름 없는 필사책의 초안을 숨기거나 기본 필사책의 것처럼 보이는 것(혼재 버전 규칙 ⑥)
/// - 다른 필사책의 초안을 기본 필사책 필사와 견주거나 기본 필사책에 넣는 것, 넣은 뒤 그 필사책이 아닌 장에 알리는 것
@Suite("설정 — 확인이 필요한 필기 · 필사책")
@MainActor
struct DraftRecoveryNotebookTesting {
    /// 문구를 꺼내는 언어 — 시험 언어(스킴 ko-KR)와 같은 한국어. 리듀서는 고른 언어가 없어 이 언어로 자리 · 결과 한 줄을 만든다.
    private nonisolated static let koreanLocale = Locale(identifier: "ko_KR")
    private nonisolated static let englishLocale = Locale(identifier: "en")
    private nonisolated static let accountA = AccountScope(key: "acct-a")
    private nonisolated static let genesis = BibleChapter(title: .genesis, chapter: 1)
    /// 이름을 붙인 필사책 「아침 필사」.
    private nonisolated static let morning = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-000000000002")!)
    /// 필사책 정보에 이름이 없는 필사책(정보보다 필기가 먼저 왔다).
    private nonisolated static let unnamed = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-000000000003")!)
    /// 목록에 없는 필사책 — 다른 기기에서 지운 필사책의 필기가 이 iPad 에 남았다.
    private nonisolated static let deleted = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-000000000004")!)
    private nonisolated static let metadata = DrawingLayoutMetadata(
        baseWritingWidth: 372, baseWritingHeight: 60, baseUnderlineAnchors: [0, 30], layoutSignature: "cl1-settings-notebook"
    )

    /// 그 필사책 안의 장 — 기본은 창세기 1장(개역개정).
    private nonisolated static func page(_ notebook: NotebookID, _ chapter: BibleChapter = genesis) -> NotebookChapter {
        NotebookChapter(notebook: notebook, chapter: chapter)
    }

    /// 책장 목록 — 기본(이름을 바꾼 적 없음) · 「아침 필사」 · 이름 없는 필사책. 지운 필사책은 목록에 없다.
    private static func shelf() -> [NotebookSnapshot] {
        [
            NotebookSnapshot(id: .default, name: nil, status: .active, createdAt: nil, completedAt: nil, writtenVerseCount: 0, hasMetadata: false),
            NotebookSnapshot(
                id: morning, name: "아침 필사", status: .active, createdAt: Date(timeIntervalSince1970: 100), completedAt: nil,
                writtenVerseCount: 0, hasMetadata: true
            ),
            NotebookSnapshot(id: unnamed, name: nil, status: .active, createdAt: nil, completedAt: nil, writtenVerseCount: 1, hasMetadata: false)
        ]
    }

    private struct Fixture {
        let area: PreservationArea
        let writer: LocalPreservationWriter
        let repository: SwiftDataDrawingRepository

        /// 그 page 의 1절에 필기를 둔다.
        func seed(_ page: NotebookChapter, ink: Data) async throws {
            let generation = try await repository.load(page).generation
            let mutation = VerseDrawingMutation.create(
                verse: 1, rowID: BibleDrawingRowID.issue(), data: ink, metadata: DraftRecoveryNotebookTesting.metadata
            )
            try await repository.apply([mutation], page: page, generation: generation)
        }

        /// 그 page 1절의 지금 필기.
        func current(_ page: NotebookChapter) async throws -> Data? {
            try await repository.load(page).snapshots.representativesByVerse()[1]?.lineData
        }

        /// 로그인하지 않은 동안 그 page 의 1절에 쓴 필기.
        func saveLoggedOutDraft(_ page: NotebookChapter, ink: Data) async throws {
            let draft = VerseDraft(
                key: VerseDraftKey(sessionID: "logged-out", page: page, verse: 1), revision: 1,
                rowID: BibleDrawingRowID(raw: "draft-row-\(page.notebook.rawValue)"), lineData: ink, drawingVersion: 3,
                layoutMetadataData: try DraftRecoveryNotebookTesting.metadata.encodedBlob(), base: .empty, baseFingerprint: nil,
                account: .localOnly, knownEpochs: [], storeOwnership: nil, eraseGeneration: 0, savedAt: Date(timeIntervalSince1970: 1_000)
            )
            _ = try await writer.saveDraft(draft)
        }

        /// 그 필사책의 초안 파일을 읽지 못하게 만든다 — 파일 이름(어느 page 인지)은 그대로라 요약에는 들고, 대조하지 못한 장으로 남는다.
        /// - Returns: 망가뜨린 파일 수.
        func corruptDrafts(of notebook: NotebookID) throws -> Int {
            let directory = area.draftsDirectory
            let paths = (try? FileManager.default.subpathsOfDirectory(atPath: directory.path)) ?? []
            let targets = paths.filter { URL(fileURLWithPath: $0).lastPathComponent.contains(notebook.rawValue) }
            for path in targets {
                try Data("{ 잘린".utf8).write(to: directory.appendingPathComponent(path))
            }
            return targets.count
        }
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-notebook-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let area = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
        let writer = LocalPreservationWriter(
            area: area,
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        )
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = SwiftDataDrawingRepository(actor: SwiftDatabaseActor(modelContainer: container))
        try await body(Fixture(area: area, writer: writer, repository: repository))
    }

    /// 지금 계정으로 소유가 확인된 환경 — 동기화 저장소에 써도 되고, 로그인하지 않은 동안의 필기를 가져올 수 있다.
    private nonisolated static func owned() -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(accountA), serverWork: AccountServerWorkToken(scope: accountA, generation: 1),
            knowledge: EraseEpochKnowledge(), storeOwnership: accountA
        )
    }

    private func makeStore(
        _ fixture: Fixture,
        notebooks: NotebookListStub,
        changes: NotebookChangeRecorder = NotebookChangeRecorder()
    ) -> TestStoreOf<DraftRecoveryFeature> {
        let store = TestStore(initialState: .initialState) {
            DraftRecoveryFeature()
        } withDependencies: {
            $0.verseDraftRecoveryReader = fixture.writer
            $0.verseDraftUnreadableCleaner = nil
            $0.drawingRepository = fixture.repository
            $0.drawingVerseImporter = fixture.repository
            $0.verseDraftImportMarker = fixture.writer
            $0.localDrawingChanges = changes
            $0.notebookRepository = notebooks
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(Self.owned())
            $0.date = .constant(Date(timeIntervalSince1970: 5_000))
        }
        store.exhaustivity = .off
        return store
    }

    /// 목록을 읽고 로그인하지 않은 동안의 묶음을 돌려준다.
    private func loadLoggedOutBucket(_ store: TestStoreOf<DraftRecoveryFeature>) async throws -> DraftRecoveryFeature.Bucket {
        await store.send(.view(.onAppear))
        await store.receive(\.loaded)
        return try #require(store.state.buckets.first { $0.scope == .localOnly })
    }

    // MARK: - 필사책마다 한 줄

    @Test("같은 절이라도 필사책마다 따로 한 줄씩 오른다 — 기본 필사책은 장 이름만, 그 밖은 앞에 필사책 이름(이름이 없거나 지운 필사책은 「이름 없는 필사책」)")
    func listsEachNotebookSeparately() async throws {
        try await withFixture { fixture in
            // Given: 로그인하지 않은 동안 창세기 1장 1절을 기본 · 「아침 필사」 · 이름 없는 필사책 · 지운 필사책에 각각 썼다
            try await fixture.saveLoggedOutDraft(Self.page(.default), ink: notebookInks[0])
            try await fixture.saveLoggedOutDraft(Self.page(Self.morning), ink: notebookInks[1])
            try await fixture.saveLoggedOutDraft(Self.page(Self.unnamed), ink: notebookInks[2])
            try await fixture.saveLoggedOutDraft(Self.page(Self.deleted), ink: notebookInks[3])
            let notebooks = NotebookListStub(snapshots: Self.shelf())
            let store = makeStore(fixture, notebooks: notebooks)

            // When
            let bucket = try await loadLoggedOutBucket(store)

            // Then: 네 줄 모두 확인이 필요한 필기다 — 같은 절이라도 필사책마다 다른 줄(다른 id)이고, 줄마다 그 필사책의 page 를 든다
            #expect(bucket.pendingItems.count == 4)
            #expect(Set(bucket.pendingItems.map(\.id)).count == 4)
            #expect(Set(bucket.pendingItems.map(\.page)) == [
                Self.page(.default), Self.page(Self.morning), Self.page(Self.unnamed), Self.page(Self.deleted)
            ])
            let places = Dictionary(bucket.pendingItems.map { ($0.page.notebook, $0.place) }, uniquingKeysWith: { first, _ in first })
            #expect(places[.default] == "창세기 1장 1절")
            #expect(places[Self.morning] == "아침 필사 · 창세기 1장 1절")
            #expect(places[Self.unnamed] == "이름 없는 필사책 · 창세기 1장 1절")
            // 지운 필사책의 필기도 숨기거나 기본 필사책에 합치지 않는다(혼재 버전 규칙 ⑥).
            #expect(places[Self.deleted] == "이름 없는 필사책 · 창세기 1장 1절")
            #expect(bucket.pendingItems.first { $0.page.notebook == Self.morning }?.ink == notebookInks[1])
            #expect(store.state.pendingCount == 4)
            // 필사책 이름은 조회마다 한 번만 읽는다.
            #expect(notebooks.reads.value == 1)
        }
    }

    @Test("기본 필사책의 필기만 있으면 필사책 이름을 읽지 않고 장 이름만 보인다 — 2.1 과 같다")
    func defaultNotebookOnlySkipsNames() async throws {
        try await withFixture { fixture in
            try await fixture.saveLoggedOutDraft(Self.page(.default), ink: notebookInks[0])
            let notebooks = NotebookListStub(snapshots: Self.shelf())
            let store = makeStore(fixture, notebooks: notebooks)

            let bucket = try await loadLoggedOutBucket(store)

            let item = try #require(bucket.pendingItems.first)
            #expect(item.place == "창세기 1장 1절")
            #expect(item.page == Self.page(.default))
            #expect(item.chapter == Self.genesis)
            #expect(notebooks.reads.value == 0)
        }
    }

    @Test("필사책 이름을 읽지 못해도 목록은 보인다 — 기본이 아닌 필사책은 「이름 없는 필사책」 으로 보이고 숨기지 않는다")
    func unreadableNamesStillListDrafts() async throws {
        try await withFixture { fixture in
            try await fixture.saveLoggedOutDraft(Self.page(Self.morning), ink: notebookInks[1])
            let store = makeStore(fixture, notebooks: NotebookListStub(snapshots: Self.shelf(), fails: true))

            let bucket = try await loadLoggedOutBucket(store)

            #expect(store.state.failure == nil)
            #expect(bucket.pendingItems.map(\.place) == ["이름 없는 필사책 · 창세기 1장 1절"])
            #expect(bucket.pendingItems.map(\.page) == [Self.page(Self.morning)])
        }
    }

    @Test("대조하지 못한 장도 기본이 아닌 필사책이면 앞에 필사책 이름을 붙인다 — 파일은 그대로다")
    func unreadChapterNamesItsNotebook() async throws {
        try await withFixture { fixture in
            // Given: 「아침 필사」 의 초안 파일을 읽지 못한다
            try await fixture.saveLoggedOutDraft(Self.page(Self.morning), ink: notebookInks[1])
            #expect(try fixture.corruptDrafts(of: Self.morning) == 1)
            let store = makeStore(fixture, notebooks: NotebookListStub(snapshots: Self.shelf()))

            // When
            let bucket = try await loadLoggedOutBucket(store)

            // Then: 그 장은 「아침 필사 · 창세기 1장」 으로 대조하지 못한 장에 남고, 줄은 만들지 않는다
            #expect(bucket.unreadChapters == ["아침 필사 · 창세기 1장"])
            #expect(bucket.items.isEmpty)
            #expect(bucket.draftCount == 1)
        }
    }

    // MARK: - 견주기 · 넣기는 그 page 로

    @Test("기본이 아닌 필사책의 필기는 그 필사책의 필사와 견주고, 넣으면 그 필사책에만 들어가며 열린 장에 그 page 로 알린다 — 기본 필사책 필사는 그대로다")
    func importsIntoItsNotebookPage() async throws {
        try await withFixture { fixture in
            // Given: 창세기 1장 1절에 기본 · 「아침 필사」 필사가 따로 있고, 로그인하지 않은 동안 「아침 필사」 로 다시 썼다
            try await fixture.seed(Self.page(.default), ink: notebookInks[3])
            try await fixture.seed(Self.page(Self.morning), ink: notebookInks[1])
            try await fixture.saveLoggedOutDraft(Self.page(Self.morning), ink: notebookInks[2])
            let changes = NotebookChangeRecorder()
            let store = makeStore(fixture, notebooks: NotebookListStub(snapshots: Self.shelf()), changes: changes)
            let bucket = try await loadLoggedOutBucket(store)
            let item = try #require(bucket.pendingItems.first)
            #expect(item.page == Self.page(Self.morning))
            #expect(item.reason == .beforeConnection)

            // When: 견준다
            await store.send(.view(.open(.localOnly)))
            await store.send(.view(.compare(item)))
            await store.receive(\.currentLoaded)

            // Then: 비교의 한쪽은 「아침 필사」 의 필사다(기본 필사책 필사가 아니다)
            #expect(store.state.comparison?.currentInk == notebookInks[1])
            #expect(store.state.comparison?.check?.action == .replace)

            // When: 넣는다
            await store.send(.view(.importTapped))
            await store.receive(\.imported)

            // Then: 「아침 필사」 의 필사만 바뀌고, 열린 장에는 그 page(필사책 + 장)로 알렸다
            #expect(store.state.importMessage == DraftRecoveryFeature.ImportMessage(
                text: DraftRecoveryCopy.imported("아침 필사 · 창세기 1장 1절", previousKept: true, locale: Self.koreanLocale), needsAttention: false
            ))
            #expect(try await fixture.current(Self.page(Self.morning)) == notebookInks[2])
            #expect(try await fixture.current(Self.page(.default)) == notebookInks[3])
            #expect(changes.posted.value == [LocalDrawingChange(page: Self.page(Self.morning), date: Date(timeIntervalSince1970: 5_000))])
            await store.receive(\.loaded)
            #expect(store.state.pendingCount == 0)
        }
    }

    // MARK: - 문구

    @Test("자리 문구 — 필사책 이름은 옮기지 않고, 이름이 없으면 화면 언어의 「이름 없는 필사책」, 기본 필사책은 이름을 붙이지 않는다")
    func notebookPlaceCopy() {
        let kjv = BibleChapter(title: .genesis, chapter: 1, translation: .KJV)
        let morningKey = VerseDraftKey(sessionID: "s", page: Self.page(Self.morning, kjv), verse: 3)
        let unnamedKey = VerseDraftKey(sessionID: "s", page: Self.page(Self.unnamed), verse: 3)
        let defaultKey = VerseDraftKey(sessionID: "s", page: Self.page(.default), verse: 3)
        let names = [Self.morning: "아침 필사"]
        let english = Self.englishLocale

        #expect(DraftRecoveryCopy.place(morningKey, notebookNames: names, locale: english) == "아침 필사 · Genesis 1:3 · KJV")
        #expect(DraftRecoveryCopy.place(unnamedKey, notebookNames: names, locale: english) == "Untitled Notebook · Genesis 1:3")
        #expect(DraftRecoveryCopy.place(defaultKey, notebookNames: names, locale: english) == "Genesis 1:3")
        #expect(DraftRecoveryCopy.chapterName(Self.page(Self.unnamed), notebookNames: [:], locale: english) == "Untitled Notebook · Genesis 1")
        #expect(DraftRecoveryCopy.chapterName(Self.page(.default), notebookNames: names, locale: english) == "Genesis 1")
        #expect(DraftRecoveryCopy.place(morningKey, notebookNames: names, locale: Self.koreanLocale) == "아침 필사 · 창세기 1장 3절 · KJV")
        // 공백뿐인 이름은 이름이 없는 것으로 본다.
        #expect(DraftRecoveryCopy.place(unnamedKey, notebookNames: [Self.unnamed: "  "], locale: Self.koreanLocale) == "이름 없는 필사책 · 창세기 1장 3절")
    }
}
