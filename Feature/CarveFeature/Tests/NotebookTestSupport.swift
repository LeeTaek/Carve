//
//  NotebookTestSupport.swift
//  CarveFeatureTest
//
//  2.2 「회차별 필사책」 시험의 공용 준비물 — 필사책 · page, page 마다 행을 두는 저장소 대역, 필사책 목록 대역, 초안 대역, 본문 스텁.
//  시험 대역은 저장 프로퍼티를 `let` · `LockIsolated` 로 두어 Sendable 을 컴파일러가 확인한다(룰북 testing.md).
//

@testable import CarveFeature
import CoreGraphics
import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import ComposableArchitecture

extension BibleChapter {
    /// 기본 필사책(2.2 이전의 모든 필사)의 page — 필사책을 나르기 전부터 있던 시험의 뜻 그대로다. 다른 필사책은 `NotebookChapter` 를 직접 짓는다.
    var inDefaultNotebook: NotebookChapter {
        NotebookChapter(notebook: .default, chapter: self)
    }
}

/// 필사책 시험의 필사책 · 장 · 행.
enum NotebookFixture {
    /// 두 번째로 만든 필사책.
    static let second = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-000000000002")!)
    /// 세 번째로 만든 필사책.
    static let third = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-000000000003")!)
    static let psalm = BibleChapter(title: .psalms, chapter: 23)
    static let psalmKJV = BibleChapter(title: .psalms, chapter: 23, translation: .KJV)
    /// 기본 필사책의 시편 23편(개역개정).
    static let firstPage = psalm.inDefaultNotebook
    /// 두 번째 필사책의 같은 장.
    static let secondPage = NotebookChapter(notebook: second, chapter: psalm)
    static let now = Date(timeIntervalSince1970: 1_000)
    static let rowInFirst = BibleDrawingRowID(raw: "row-first")
    static let rowInSecond = BibleDrawingRowID(raw: "row-second")
    /// 본문 스텁(`NotebookSixVerseText`)의 절 수.
    static let verseCount = 6

    /// 절 2 에 새 행을 만드는 편집 결과.
    static func createResult(_ tag: String, rowID: BibleDrawingRowID) -> DrawingEditResult {
        DrawingEditResult(
            ownership: OwnershipSnapshot(map: [:], layoutSignature: CanvasTestSupport.layout.signature),
            mutations: [.create(verse: 2, rowID: rowID, data: Data("create-\(tag)".utf8), metadata: CanvasTestSupport.metadata())],
            issuedRowIDs: [2: rowID]
        )
    }

    /// 실제 획 하나가 든 잉크 — `seed` 마다 내용이 다르다(같은 내용은 이전 필사 목록에서 하나로 묶인다).
    static func ink(seed: UInt32) -> Data {
        PKDrawing(strokes: [
            OwnershipTestSupport.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 40, y: 5), seed: seed, creationTime: TimeInterval(seed) * 1_000)
        ]).dataRepresentation()
    }

    /// 그 page 의 절 행 전부를 한 줄씩 잰 배치 — 레이아웃이 완성된다.
    static func geometry(_ page: NotebookChapter) -> [SentencesWithDrawingFeature.State.ID: VerseRowGeometry] {
        Dictionary(uniqueKeysWithValues: (1...verseCount).map {
            (SentencesWithDrawingFeature.State.rowID(page: page, verse: $0), VerseRowGeometry(underlineOffsets: [30]))
        })
    }

    /// 저장소에 넣을 행 하나.
    struct SeedRow {
        let page: NotebookChapter
        var verse = 1
        let key: String
        let seed: UInt32
        var isPresent = true
        let updatedAt: TimeInterval
    }

    /// 앱 스키마의 인메모리 저장소에 행을 넣는다. @Model 은 컨테이너를 연 뒤에 만든다(iOS 17). 공유 actor 를 깨우지 않도록 자기 컨테이너를 연다.
    static func makeDatabase(_ seeds: [SeedRow]) throws -> (ModelContainer, SwiftDatabaseActor) {
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        for seed in seeds {
            let row = BibleDrawing(
                page: seed.page, verse: seed.verse, lineData: ink(seed: seed.seed),
                updateDate: Date(timeIntervalSince1970: seed.updatedAt), rowUUID: seed.key
            )
            row.isPresent = seed.isPresent
            context.insert(row)
        }
        try context.save()
        return (container, SwiftDatabaseActor(modelContainer: container))
    }
}

/// page 마다 행을 따로 두는 필사 저장소 대역 — 저장(`apply`)한 명령을 그 page 의 행으로 남기고, 조회(`load`)는 그 page 의 행만 돌려준다.
///
/// 필사 화면은 page 요구만 불러야 한다 — 옛 `chapter:` 요구가 불리면 `legacyCalls` 에 남기고 실패한다. 저장 실패 · 붙잡기는 필요한 시험만 켠다.
final class PageStoreRepository: DrawingRepository {
    struct LegacyRequirement: Error {}

    /// page 마다 저장된 행(저장 순서).
    let stored = LockIsolated<[NotebookChapter: [VerseDrawingSnapshot]]>([:])
    /// 조회한 page(순서대로).
    let loadedPages = LockIsolated<[NotebookChapter]>([])
    /// 저장을 시도한 page(순서대로) — 실패한 시도도 남는다.
    let appliedPages = LockIsolated<[NotebookChapter]>([])
    /// 보관(지우기)한 page.
    let archivedPages = LockIsolated<[NotebookChapter]>([])
    /// 옛 `chapter:` 요구가 불린 횟수 — 0 이어야 한다.
    let legacyCalls = LockIsolated(0)
    /// 남은 저장 실패 수.
    let applyFailures = LockIsolated(0)
    private let holdApply = LockIsolated(false)
    private let applyGate = LockIsolated<AsyncStream<Void>.Continuation?>(nil)
    private let holdArchive = LockIsolated(false)
    private let archiveGate = LockIsolated<AsyncStream<Void>.Continuation?>(nil)

    /// 다음 저장을 `releaseApply()` 까지 붙잡는다.
    func holdNextApply() { holdApply.setValue(true) }
    /// 붙잡은 저장이 기다리는 중인가 — 풀기 전에 이것을 기다린다(풀기가 먼저면 저장이 영영 붙잡힌다).
    var isHoldingApply: Bool { applyGate.value != nil }
    func releaseApply() { applyGate.withValue { $0?.yield(); $0?.finish(); $0 = nil } }
    /// 다음 보관을 `releaseArchive()` 까지 붙잡는다.
    func holdNextArchive() { holdArchive.setValue(true) }
    var isHoldingArchive: Bool { archiveGate.value != nil }
    func releaseArchive() { archiveGate.withValue { $0?.yield(); $0?.finish(); $0 = nil } }

    /// 그 page 에 저장된 행 키.
    func storedRowIDs(_ page: NotebookChapter) -> [BibleDrawingRowID] {
        (stored.value[page] ?? []).map(\.rowID)
    }

    func load(_ page: NotebookChapter) async throws -> DrawingChapterLoad {
        loadedPages.withValue { $0.append(page) }
        return DrawingChapterLoad(snapshots: stored.value[page] ?? [], generation: DrawingStoreGeneration(raw: 0))
    }

    func apply(_ mutations: [VerseDrawingMutation], page: NotebookChapter, generation: DrawingStoreGeneration) async throws {
        await Self.waitIfHeld(holdApply, gate: applyGate)
        appliedPages.withValue { $0.append(page) }
        let fails = applyFailures.withValue { remaining -> Bool in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        if fails { throw DrawingRepositoryError.persistenceFailed("offline") }
        stored.withValue { pages in
            var rows = pages[page] ?? []
            for mutation in mutations {
                let snapshot = Self.snapshot(of: mutation, in: page)
                if let index = rows.firstIndex(where: { $0.rowID == snapshot.rowID }) {
                    rows[index] = snapshot
                } else {
                    rows.append(snapshot)
                }
            }
            pages[page] = rows
        }
    }

    func archiveAndReset(_ command: VerseDrawingArchiveCommand, page: NotebookChapter) async throws -> VerseDrawingArchiveOutcome {
        await Self.waitIfHeld(holdArchive, gate: archiveGate)
        archivedPages.withValue { $0.append(page) }
        return .archived
    }

    // 옛 `chapter:` 요구 — 필사 화면은 부르지 않는다(L2 뒤의 새 코드는 옛 API 를 부르지 않는다).

    func load(chapter: BibleChapter) async throws -> DrawingChapterLoad {
        legacyCalls.withValue { $0 += 1 }
        throw LegacyRequirement()
    }

    func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter, generation: DrawingStoreGeneration) async throws {
        legacyCalls.withValue { $0 += 1 }
        throw LegacyRequirement()
    }

    func archiveAndReset(_ command: VerseDrawingArchiveCommand, chapter: BibleChapter) async throws -> VerseDrawingArchiveOutcome {
        legacyCalls.withValue { $0 += 1 }
        throw LegacyRequirement()
    }

    /// 저장 명령이 저장소에 남기는 행 — 그 page 의 번역본 · 필사책을 든다.
    private static func snapshot(of mutation: VerseDrawingMutation, in page: NotebookChapter) -> VerseDrawingSnapshot {
        switch mutation {
        case let .create(verse, rowID, data, metadata), let .replace(verse, rowID, data, metadata):
            VerseDrawingSnapshot(
                verse: verse, rowID: rowID, isPresent: true, updateDate: nil, lineData: data, drawingVersion: 3, metadata: metadata,
                translation: page.chapter.translation, notebook: page.notebook
            )
        case let .clear(verse, rowID):
            VerseDrawingSnapshot(
                verse: verse, rowID: rowID, isPresent: true, updateDate: nil, lineData: nil, drawingVersion: 3, metadata: nil,
                translation: page.chapter.translation, notebook: page.notebook
            )
        }
    }

    private static func waitIfHeld(_ hold: LockIsolated<Bool>, gate: LockIsolated<AsyncStream<Void>.Continuation?>) async {
        guard hold.withValue({ value -> Bool in defer { value = false }; return value }) else { return }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        gate.setValue(continuation)
        for await _ in stream { break }
    }
}

/// 필사책 목록 대역 — 목록을 바꿀 수 있고 읽은 횟수를 센다. 쓰기는 필사책 바꾸기 시험이 보지 않는다.
final class NotebookListStub: NotebookRepository {
    let listed = LockIsolated<[NotebookID]>([.default])
    let reads = LockIsolated(0)

    func notebooks() async throws -> [NotebookSnapshot] {
        reads.withValue { $0 += 1 }
        return listed.value.map {
            NotebookSnapshot(
                id: $0, name: nil, status: .active, createdAt: nil, completedAt: nil, writtenVerseCount: 0, hasMetadata: !$0.isDefault
            )
        }
    }

    func create(id: NotebookID, name: String, now: Date) async throws {}

    func rename(_ id: NotebookID, to name: String, now: Date) async throws {}

    func setCompleted(_ id: NotebookID, _ completed: Bool, now: Date) async throws {}

    func delete(_ id: NotebookID) async throws {}
}

/// 초안을 page 로 읽는 초안 저장소 대역 — 읽기는 늘 빈 목록이고, 어느 page 를 읽었는지 남긴다. 옛 요구가 불리면 센다.
final class PageDraftStore: VerseDraftStore {
    let requested = LockIsolated<[NotebookChapter]>([])
    let legacyCalls = LockIsolated(0)
    let generation: UInt64

    init(generation: UInt64) {
        self.generation = generation
    }

    func saveDraft(_ draft: VerseDraft, superseding: [VerseDraftRef]) async throws -> LocalPreservationWriter.WriteOutcome {
        .written
    }

    func drafts(in scope: AccountScope, page: NotebookChapter) async throws -> [VerseDraft] {
        requested.withValue { $0.append(page) }
        return []
    }

    func drafts(in scope: AccountScope, chapter: BibleChapter, translation: Translation) async throws -> [VerseDraft] {
        legacyCalls.withValue { $0 += 1 }
        return []
    }

    func removeDraft(_ key: VerseDraftKey, scope: AccountScope, ifRevision revision: Int) async throws {}

    func markDraftStored(_ key: VerseDraftKey, scope: AccountScope, throughRevision revision: Int, contentFingerprint: String?) async throws {}

    func currentGeneration() async -> UInt64? { generation }
}

/// 어느 번역본이든 6절을 돌려주는 본문 스텁.
struct NotebookSixVerseText: BibleTextClient {
    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        (1...NotebookFixture.verseCount).map { BibleVerse(title: chapter, verse: $0, sentence: "\(chapter.translation.rawValue) \($0)") }
    }
}

/// 본문을 읽지 못하는 스텁 — 본문 읽기 뒤 캔버스 조회로 이어지지 않게 한다.
struct NotebookUnreadableText: BibleTextClient {
    struct Unreadable: Error {}

    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        throw Unreadable()
    }
}

/// 효과가 끝나기를 기다린다. 제한 시간 안에 조건이 참이 되지 않으면 실패로 기록한다.
@MainActor
func eventually(
    timeout: Duration = .seconds(5),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while try await !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("조건이 제한 시간 안에 참이 되지 않았다", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// 이 시험만의 UserDefaults · 메모리 저장소로 돌린다 — 지금 필사책 · 지금 장 키(기기마다)와 전체 삭제 세대(`DrawingDataRevision`)가
/// 다른 시험과 섞이지 않는다.
@MainActor
func withIsolatedDefaults(_ operation: () async throws -> Void) async throws {
    let suite = "NotebookTesting.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try await withDependencies {
        $0.defaultAppStorage = defaults
        $0.defaultInMemoryStorage = InMemoryStorage()
    } operation: {
        try await operation()
    }
}
