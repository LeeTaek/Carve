//
//  DraftRecoveryImportTesting.swift
//  SettingsFeatureTest
//
//  설정 → 「확인이 필요한 필기」 의 견주기와 넣기 · 바꾸기 — 실제 보존 영역(임시 폴더)과 인메모리 저장소로 잇는다 (2026-09-29).
//

import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

import ComposableArchitecture

@testable import SettingsFeature

// MARK: - 대역

/// 열린 필사 화면에 보낸 알림을 적는다.
private final class RecordingChanges: LocalDrawingChangeClient, @unchecked Sendable {
    let posted = LockIsolated<[LocalDrawingChange]>([])

    func post(_ change: LocalDrawingChange) { posted.withValue { $0.append(change) } }
    func changes() -> AsyncStream<LocalDrawingChange> { AsyncStream { $0.finish() } }
}

/// 저장에 실패하는 쓰기.
private struct FailingImporter: DrawingVerseImporting {
    func importVerse(
        _ command: VerseDrawingImportCommand, chapter: BibleChapter, generation: DrawingStoreGeneration
    ) async throws -> VerseDrawingImportOutcome {
        throw DrawingRepositoryError.persistenceFailed("디스크가 가득 찼다")
    }
}

/// 실제 stroke 가 있는 필기 — 한 번만 만든다(`dataRepresentation()` 은 부를 때마다 다른 바이트를 낸다).
private let settingsInks: [Data] = (0..<4).map { offset in
    let points = (0..<6).map { index in
        PKStrokePoint(
            location: CGPoint(x: Double(index * 10 + offset), y: Double(offset)), timeOffset: Double(index) * 0.02,
            size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
        )
    }
    let stroke = PKStroke(
        ink: PKInk(.pen, color: .black),
        path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
    )
    return PKDrawing(strokes: [stroke]).dataRepresentation()
}

/// 이 파일이 막는 것(2026-09-29):
/// - 계정 연결 뒤 연결 전 필기를 **보기만 하고 넣을 수 없는 것**
/// - 저장을 마치기 전에 완료라고 알리거나, 실패했는데 필기가 바뀐 것처럼 보이는 것
/// - 지웠던 절에 묻지 않고 넣는 것, 취소했는데 넣는 것
/// - 견준 뒤 현재 필기가 바뀌었는데 그 위에 쓰는 것
/// - 동기화 저장소에 쓸 수 없는 환경(소유 근거 없음 · 로그아웃 · 연결 보류)에서 넣는 것
/// - 넣은 뒤 그 아래 열린 필사 화면이 모르는 것
@Suite("설정 — 확인이 필요한 필기 · 넣기")
@MainActor
struct DraftRecoveryImportTesting {
    private static let accountA = AccountScope(key: "acct-a")
    private static let chapter = BibleChapter(title: .genesis, chapter: 1)
    private static let metadata = DrawingLayoutMetadata(
        baseWritingWidth: 372, baseWritingHeight: 60, baseUnderlineAnchors: [0, 30], layoutSignature: "cl1-settings-import"
    )

    private struct Fixture {
        let writer: LocalPreservationWriter
        let repository: SwiftDataDrawingRepository

        func seed(verse: Int = 1, ink: Data) async throws -> BibleDrawingRowID {
            let rowID = BibleDrawingRowID.issue()
            try await apply([.create(verse: verse, rowID: rowID, data: ink, metadata: DraftRecoveryImportTesting.metadata)])
            return rowID
        }

        func apply(_ mutations: [VerseDrawingMutation]) async throws {
            let generation = try await repository.load(chapter: DraftRecoveryImportTesting.chapter).generation
            try await repository.apply(mutations, chapter: DraftRecoveryImportTesting.chapter, generation: generation)
        }

        func current(verse: Int = 1) async throws -> VerseDrawingSnapshot? {
            try await repository.load(chapter: DraftRecoveryImportTesting.chapter).snapshots.representativesByVerse()[verse]
        }

        /// 로그인하지 않은 동안 쓴 필기.
        func saveLoggedOutDraft(verse: Int = 1, ink: Data) async throws -> VerseDraft {
            let draft = VerseDraft(
                key: VerseDraftKey(sessionID: "logged-out", chapter: DraftRecoveryImportTesting.chapter, verse: verse), revision: 1,
                rowID: BibleDrawingRowID(raw: "draft-row-\(verse)"), lineData: ink, drawingVersion: 3,
                layoutMetadataData: try DraftRecoveryImportTesting.metadata.encodedBlob(), base: .empty, baseFingerprint: nil,
                account: .localOnly, knownEpochs: [], storeOwnership: nil, eraseGeneration: 0, savedAt: Date(timeIntervalSince1970: 1_000)
            )
            _ = try await writer.saveDraft(draft)
            return draft
        }
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = LocalPreservationWriter(
            area: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        )
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = SwiftDataDrawingRepository(actor: SwiftDatabaseActor(modelContainer: container))
        try await body(Fixture(writer: writer, repository: repository))
    }

    /// 지금 계정으로 소유가 확인된 환경 — 동기화 저장소에 써도 된다.
    private nonisolated static func owned(_ scope: AccountScope = accountA) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope), serverWork: AccountServerWorkToken(scope: scope, generation: 1), knowledge: EraseEpochKnowledge(),
            storeOwnership: scope
        )
    }

    private func makeStore(
        _ fixture: Fixture,
        environment: DrawingEditEnvironment = owned(),
        importer: (any DrawingVerseImporting)? = nil,
        changes: RecordingChanges = RecordingChanges()
    ) -> TestStoreOf<DraftRecoveryFeature> {
        let store = TestStore(initialState: .initialState) {
            DraftRecoveryFeature()
        } withDependencies: {
            $0.verseDraftRecoveryReader = fixture.writer
            $0.verseDraftUnreadableCleaner = nil
            $0.drawingRepository = fixture.repository
            $0.drawingVerseImporter = importer ?? fixture.repository
            $0.verseDraftImportMarker = fixture.writer
            $0.localDrawingChanges = changes
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(environment)
            $0.date = .constant(Date(timeIntervalSince1970: 5_000))
        }
        store.exhaustivity = .off
        return store
    }

    /// 목록을 읽고 로그인하지 않은 동안의 묶음을 펼쳐 첫 필기를 견준다.
    private func compareFirstLoggedOutItem(_ store: TestStoreOf<DraftRecoveryFeature>) async throws -> DraftRecoveryFeature.Item {
        await store.send(.view(.onAppear))
        await store.receive(\.loaded)
        let item = try #require(store.state.buckets.first { $0.scope == .localOnly }?.pendingItems.first)
        await store.send(.view(.open(.localOnly)))
        await store.send(.view(.compare(item)))
        await store.receive(\.currentLoaded)
        return item
    }

    // MARK: - 넣기 · 바꾸기

    @Test("연결 전 필기를 견주고 바꾸면 저장을 마친 뒤에만 완료를 알리고, 목록에서 빠지며, 열린 필사 화면에 알린다")
    func replacesAfterComparing() async throws {
        try await withFixture { fixture in
            _ = try await fixture.seed(ink: settingsInks[1])
            _ = try await fixture.saveLoggedOutDraft(ink: settingsInks[2])
            let changes = RecordingChanges()
            let store = makeStore(fixture, changes: changes)

            let item = try await compareFirstLoggedOutItem(store)
            #expect(item.reason == .beforeConnection)
            #expect(store.state.pendingCount == 1)
            #expect(store.state.importBlock == nil)
            let check = try #require(store.state.comparison?.check)
            #expect(check.action == .replace)
            #expect(check.caution == nil)

            await store.send(.view(.importTapped))
            #expect(store.state.importingItemID == item.id)
            // 저장을 마치기 전에는 완료를 말하지 않는다.
            #expect(store.state.importMessage == nil)
            await store.receive(\.imported)

            #expect(store.state.importingItemID == nil)
            #expect(store.state.importMessage == DraftRecoveryFeature.ImportMessage(
                text: DraftRecoveryCopy.imported(item.place, previousKept: true), needsAttention: false
            ))
            #expect(store.state.comparison == nil)
            await store.receive(\.loaded)
            // 넣은 필기는 이미 반영된 것이라 목록에서 빠진다.
            #expect(store.state.pendingCount == 0)
            // 그 아래 열린 필사 화면이 그 장을 다시 읽게 알렸다.
            #expect(changes.posted.value == [LocalDrawingChange(chapter: Self.chapter, date: Date(timeIntervalSince1970: 5_000))])
            #expect(try await fixture.current()?.lineData == settingsInks[2])
            // 남겨 둔 필기는 지우지 않고 가져온 기록을 남긴다.
            #expect(try await fixture.writer.drafts(in: .localOnly).first?.imported?.account == Self.accountA)
        }
    }

    @Test("이 필기를 쓴 뒤 그 절이 지워졌으면 먼저 묻고, 취소하면 쓰지 않으며, 확인하면 넣는다")
    func clearedVerseAsksFirst() async throws {
        try await withFixture { fixture in
            let row = try await fixture.seed(ink: settingsInks[1])
            try await fixture.apply([.clear(verse: 1, rowID: row)])
            _ = try await fixture.saveLoggedOutDraft(ink: settingsInks[2])
            let store = makeStore(fixture)

            _ = try await compareFirstLoggedOutItem(store)
            let check = try #require(store.state.comparison?.check)
            #expect(check.action == .insert)
            #expect(check.caution == .verseClearedAfterDraft)

            await store.send(.view(.importTapped))
            #expect(store.state.pendingCaution == .verseClearedAfterDraft)
            #expect(store.state.importingItemID == nil)
            await store.send(.view(.cautionCancelled))
            #expect(store.state.pendingCaution == nil)
            #expect(try await fixture.current()?.lineData == nil)

            await store.send(.view(.importTapped))
            await store.send(.view(.cautionConfirmed))
            await store.receive(\.imported)
            #expect(store.state.importMessage?.text.contains("넣었어요") == true)
            #expect(try await fixture.current()?.lineData == settingsInks[2])
        }
    }

    @Test("견준 뒤 현재 필기가 바뀌었으면 쓰지 않고, 알린 뒤 다시 견준다")
    func changedCurrentVerseIsComparedAgain() async throws {
        try await withFixture { fixture in
            let row = try await fixture.seed(ink: settingsInks[1])
            _ = try await fixture.saveLoggedOutDraft(ink: settingsInks[2])
            let store = makeStore(fixture)
            _ = try await compareFirstLoggedOutItem(store)

            // 견주는 사이 다른 기기의 필기가 도착했다.
            try await fixture.apply([.replace(verse: 1, rowID: row, data: settingsInks[3], metadata: Self.metadata)])
            let arrived = try await fixture.current()?.contentFingerprint

            await store.send(.view(.importTapped))
            await store.receive(\.imported)
            #expect(store.state.importMessage == DraftRecoveryFeature.ImportMessage(text: DraftRecoveryCopy.currentChanged, needsAttention: true))
            await store.receive(\.currentLoaded)
            #expect(store.state.comparison?.check?.currentFingerprint == arrived)
            // 아무것도 쓰지 않았다.
            #expect(try await fixture.current()?.lineData == settingsInks[3])
            #expect(try await fixture.writer.drafts(in: .localOnly).first?.imported == nil)
        }
    }

    @Test("저장에 실패하면 완료라 하지 않고, 현재 필사와 남겨 둔 필기가 그대로라고 알린다")
    func failedImportKeepsBothSides() async throws {
        try await withFixture { fixture in
            _ = try await fixture.seed(ink: settingsInks[1])
            _ = try await fixture.saveLoggedOutDraft(ink: settingsInks[2])
            let changes = RecordingChanges()
            let store = makeStore(fixture, importer: FailingImporter(), changes: changes)
            _ = try await compareFirstLoggedOutItem(store)

            await store.send(.view(.importTapped))
            await store.receive(\.imported)

            #expect(store.state.importMessage == DraftRecoveryFeature.ImportMessage(text: DraftRecoveryCopy.importFailed, needsAttention: true))
            #expect(store.state.comparison != nil)
            #expect(changes.posted.value.isEmpty)
            #expect(try await fixture.current()?.lineData == settingsInks[1])
            #expect(try await fixture.writer.drafts(in: .localOnly).first?.imported == nil)
        }
    }

    // MARK: - 넣을 수 없는 환경

    @Test("이 iPad의 필사가 지금 계정의 것인지 확인하지 못했으면 까닭을 보이고 넣지 않는다 — 견주기는 된다")
    func unownedEnvironmentDoesNotImport() async throws {
        try await withFixture { fixture in
            _ = try await fixture.seed(ink: settingsInks[1])
            _ = try await fixture.saveLoggedOutDraft(ink: settingsInks[2])
            var unowned = Self.owned()
            unowned.storeOwnership = nil
            let store = makeStore(fixture, environment: unowned)

            _ = try await compareFirstLoggedOutItem(store)
            #expect(store.state.importBlock == .ownershipUnverified)
            #expect(store.state.comparison?.check?.action == .replace)

            await store.send(.view(.importTapped))
            #expect(store.state.importingItemID == nil)
            #expect(try await fixture.current()?.lineData == settingsInks[1])
            #expect(DraftRecoveryCopy.importBlocked(.ownershipUnverified).contains("넣을 수 없어요"))
        }
    }

    // MARK: - 보관만 하는 예전 필기

    @Test("저장을 마친 뒤 이어 고친 예전 필기는 확인이 필요한 수에 넣지 않고 따로 접어 둔다 — 펼치면 견줄 수 있다")
    func archivedItemsAreFoldedApart() async throws {
        try await withFixture { fixture in
            let row = try await fixture.seed(ink: settingsInks[1])
            let sent = try #require(try await fixture.current()?.contentFingerprint)
            let earlier = VerseDraft(
                key: VerseDraftKey(sessionID: "earlier", chapter: Self.chapter, verse: 1), revision: 1, rowID: row, lineData: settingsInks[1],
                drawingVersion: 3, layoutMetadataData: try Self.metadata.encodedBlob(), base: .empty, baseFingerprint: nil,
                account: .confirmed(AccountServerWorkToken(scope: Self.accountA, generation: 1)), knownEpochs: [], storeOwnership: Self.accountA,
                eraseGeneration: 0, savedAt: Date(timeIntervalSince1970: 1_000), storeState: .stored, sentFingerprints: [sent]
            )
            _ = try await fixture.writer.saveDraft(earlier)
            // 다음 세션에서 그 절을 이어 고쳤다.
            try await fixture.apply([.replace(verse: 1, rowID: row, data: settingsInks[2], metadata: Self.metadata)])
            let store = makeStore(fixture)

            await store.send(.view(.onAppear))
            await store.receive(\.loaded)
            let bucket = try #require(store.state.buckets.first { $0.scope == Self.accountA })
            #expect(bucket.pendingItems.isEmpty)
            #expect(bucket.archivedItems.map(\.reason) == [.savedEarlier])
            #expect(store.state.pendingCount == 0)
            #expect(store.state.archivedCount == 1)

            await store.send(.view(.toggleArchived(Self.accountA))) { $0.archivedOpened = [Self.accountA] }
            let item = try #require(bucket.archivedItems.first)
            await store.send(.view(.compare(item)))
            await store.receive(\.currentLoaded)
            #expect(store.state.comparison?.check?.action == .replace)
            await store.send(.view(.closeComparison)) { $0.comparison = nil }
        }
    }
}
