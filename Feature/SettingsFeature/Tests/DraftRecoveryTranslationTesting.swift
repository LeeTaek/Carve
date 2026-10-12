//
//  DraftRecoveryTranslationTesting.swift
//  SettingsFeatureTest
//
//  설정 → 「확인이 필요한 필기」 의 번역본 — 모든 번역본의 초안을 한 목록으로 보이고, 고른 초안은 그 번역본의 필사에 넣는다(영어 현지화 결정 1 · 11).
//  실제 보존 영역(임시 폴더)과 인메모리 저장소로 잇는다.
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
private final class TranslationChangeRecorder: LocalDrawingChangeClient {
    let posted = LockIsolated<[LocalDrawingChange]>([])

    func post(_ change: LocalDrawingChange) { posted.withValue { $0.append(change) } }
    func changes() -> AsyncStream<LocalDrawingChange> { AsyncStream { $0.finish() } }
}

/// 실제 stroke 가 있는 필기 — 한 번만 만든다(`dataRepresentation()` 은 부를 때마다 다른 바이트를 낸다).
private let translationInks: [Data] = (0..<4).map { offset in
    let points = (0..<6).map { index in
        PKStrokePoint(
            location: CGPoint(x: Double(index * 12 + offset), y: Double(offset * 2)), timeOffset: Double(index) * 0.02,
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
/// - KJV · BSB 로 쓴 초안이 목록에 오르지 않는 것(개역개정만 조회)
/// - 같은 절의 개역개정 · KJV 초안이 한 줄로 겹치거나, 어느 번역본의 것인지 보이지 않는 것
/// - KJV 초안을 개역개정 필사와 견주거나 개역개정 필사에 넣는 것
@Suite("설정 — 확인이 필요한 필기 · 번역본")
@MainActor
struct DraftRecoveryTranslationTesting {
    private nonisolated static let accountA = AccountScope(key: "acct-a")
    private nonisolated static let korean = BibleChapter(title: .genesis, chapter: 1)
    private nonisolated static let english = BibleChapter(title: .genesis, chapter: 1, translation: .KJV)
    private nonisolated static let metadata = DrawingLayoutMetadata(
        baseWritingWidth: 372, baseWritingHeight: 60, baseUnderlineAnchors: [0, 30], layoutSignature: "cl1-settings-translation"
    )

    private struct Fixture {
        let writer: LocalPreservationWriter
        let repository: SwiftDataDrawingRepository

        /// 그 장(번역본 포함)의 1절에 필기를 둔다.
        func seed(_ chapter: BibleChapter, ink: Data) async throws {
            let generation = try await repository.load(chapter: chapter).generation
            let mutation = VerseDrawingMutation.create(
                verse: 1, rowID: BibleDrawingRowID.issue(), data: ink, metadata: DraftRecoveryTranslationTesting.metadata
            )
            try await repository.apply([mutation], chapter: chapter, generation: generation)
        }

        /// 그 장(번역본 포함) 1절의 지금 필기.
        func current(_ chapter: BibleChapter) async throws -> Data? {
            try await repository.load(chapter: chapter).snapshots.representativesByVerse()[1]?.lineData
        }

        /// 로그인하지 않은 동안 그 장(번역본 포함)의 1절에 쓴 필기.
        func saveLoggedOutDraft(_ chapter: BibleChapter, ink: Data) async throws {
            let draft = VerseDraft(
                key: VerseDraftKey(sessionID: "logged-out", chapter: chapter, verse: 1), revision: 1,
                rowID: BibleDrawingRowID(raw: "draft-row-\(chapter.translation.rawValue)"), lineData: ink, drawingVersion: 3,
                layoutMetadataData: try DraftRecoveryTranslationTesting.metadata.encodedBlob(), base: .empty, baseFingerprint: nil,
                account: .localOnly, knownEpochs: [], storeOwnership: nil, eraseGeneration: 0, savedAt: Date(timeIntervalSince1970: 1_000)
            )
            _ = try await writer.saveDraft(draft)
        }
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-translation-\(UUID().uuidString)", isDirectory: true)
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
    private nonisolated static func owned() -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(accountA), serverWork: AccountServerWorkToken(scope: accountA, generation: 1),
            knowledge: EraseEpochKnowledge(), storeOwnership: accountA
        )
    }

    private func makeStore(_ fixture: Fixture, changes: TranslationChangeRecorder) -> TestStoreOf<DraftRecoveryFeature> {
        let store = TestStore(initialState: .initialState) {
            DraftRecoveryFeature()
        } withDependencies: {
            $0.verseDraftRecoveryReader = fixture.writer
            $0.verseDraftUnreadableCleaner = nil
            $0.drawingRepository = fixture.repository
            $0.drawingVerseImporter = fixture.repository
            $0.verseDraftImportMarker = fixture.writer
            $0.localDrawingChanges = changes
            $0.drawingEditEnvironment = StubDrawingEditEnvironment(Self.owned())
            $0.date = .constant(Date(timeIntervalSince1970: 5_000))
        }
        store.exhaustivity = .off
        return store
    }

    @Test("같은 절의 개역개정 · KJV 초안이 따로 한 줄씩 오르고, 줄마다 번역본 약칭과 그 번역본 장을 든다")
    func listsDraftsOfEveryTranslation() async throws {
        try await withFixture { fixture in
            // Given: 로그인하지 않은 동안 창세기 1장 1절을 개역개정 · KJV 로 각각 썼다
            try await fixture.saveLoggedOutDraft(Self.korean, ink: translationInks[0])
            try await fixture.saveLoggedOutDraft(Self.english, ink: translationInks[2])
            let store = makeStore(fixture, changes: TranslationChangeRecorder())

            // When
            await store.send(.view(.onAppear))
            await store.receive(\.loaded)

            // Then: 두 줄 모두 확인이 필요한 필기다 — 같은 절이라도 번역본마다 다른 줄이다
            let bucket = try #require(store.state.buckets.first { $0.scope == .localOnly })
            #expect(bucket.pendingItems.count == 2)
            #expect(Set(bucket.pendingItems.map(\.id)).count == 2)
            let english = try #require(bucket.pendingItems.first { $0.chapter.translation == .KJV })
            let korean = try #require(bucket.pendingItems.first { $0.chapter.translation == .NKRV })
            #expect(english.chapter == Self.english)
            #expect(korean.chapter == Self.korean)
            #expect(english.place == "창세기 1장 1절 · KJV")
            #expect(korean.place == "창세기 1장 1절 · 개역개정")
            #expect(english.ink == translationInks[2])
            #expect(store.state.pendingCount == 2)
        }
    }

    @Test("KJV 초안은 KJV 필사와 견주고, 넣으면 KJV 필사에만 들어가며 열린 KJV 장에 알린다 — 개역개정 필사는 그대로다")
    func importsKJVDraftIntoKJVRow() async throws {
        try await withFixture { fixture in
            // Given: 같은 창세기 1장 1절에 개역개정 · KJV 필사가 따로 있고, 로그인하지 않은 동안 KJV 로 다시 썼다
            try await fixture.seed(Self.korean, ink: translationInks[3])
            try await fixture.seed(Self.english, ink: translationInks[1])
            try await fixture.saveLoggedOutDraft(Self.english, ink: translationInks[2])
            let changes = TranslationChangeRecorder()
            let store = makeStore(fixture, changes: changes)
            await store.send(.view(.onAppear))
            await store.receive(\.loaded)
            let item = try #require(store.state.buckets.first { $0.scope == .localOnly }?.pendingItems.first)
            #expect(item.chapter == Self.english)
            #expect(item.reason == .beforeConnection)

            // When: 견준다
            await store.send(.view(.open(.localOnly)))
            await store.send(.view(.compare(item)))
            await store.receive(\.currentLoaded)

            // Then: 비교의 한쪽은 KJV 필사다(개역개정 필사가 아니다)
            #expect(store.state.comparison?.currentInk == translationInks[1])
            #expect(store.state.comparison?.check?.action == .replace)

            // When: 넣는다
            await store.send(.view(.importTapped))
            await store.receive(\.imported)

            // Then: KJV 필사만 바뀌고, 열린 KJV 장에 알렸다
            #expect(store.state.importMessage == DraftRecoveryFeature.ImportMessage(
                text: DraftRecoveryCopy.imported(item.place, previousKept: true), needsAttention: false
            ))
            #expect(try await fixture.current(Self.english) == translationInks[2])
            #expect(try await fixture.current(Self.korean) == translationInks[3])
            #expect(changes.posted.value == [LocalDrawingChange(chapter: Self.english, date: Date(timeIntervalSince1970: 5_000))])
            await store.receive(\.loaded)
            #expect(store.state.pendingCount == 0)
        }
    }
}
