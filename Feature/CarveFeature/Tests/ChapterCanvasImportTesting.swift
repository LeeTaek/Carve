//
//  ChapterCanvasImportTesting.swift
//  CarveFeatureTest
//
//  필사 화면과 「확인이 필요한 필기」 의 가져오기 — 절 메뉴 수 · 설정에서 넣은 필기의 반영 (2026-09-29).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 시험이 정한 때에 「설정에서 넣었다」 를 알리는 신호.
final class ControlledLocalChanges: LocalDrawingChangeClient, @unchecked Sendable {
    private let continuations = LockIsolated<[AsyncStream<LocalDrawingChange>.Continuation]>([])

    var subscriberCount: Int { continuations.value.count }

    func post(_ change: LocalDrawingChange) {
        continuations.value.forEach { $0.yield(change) }
    }

    func changes() -> AsyncStream<LocalDrawingChange> {
        let (stream, continuation) = AsyncStream<LocalDrawingChange>.makeStream()
        continuations.withValue { $0.append(continuation) }
        return stream
    }

    func finish() {
        continuations.value.forEach { $0.finish() }
    }
}

/// 이 파일이 막는 것(2026-09-29):
/// - 연결 전 필기를 캔버스에 **자동으로 겹쳐** 지금 계정의 필기처럼 보이는 것 — 사용자가 견주고 골라야 들어간다
/// - 절 메뉴의 「확인이 필요한 필기 N」 이 설정 화면의 목록과 다른 수를 말하는 것(연결 전 필기를 빼거나, 예전 수정본을 넣거나)
/// - 설정에서 넣은 필기가 그 아래 열린 장에 **다시 켜기 전까지 보이지 않는 것**, 편집한 장에서 한 번 더 확인을 묻는 것
@Suite("필사 화면 — 확인이 필요한 필기와 가져오기")
@MainActor
struct ChapterCanvasImportTesting: DraftTestSamples {

    private struct Area {
        let root: URL
        let writer: LocalPreservationWriter
    }

    private func makeArea() -> Area {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-import-\(UUID().uuidString)", isDirectory: true)
        return Area(root: root, writer: LocalPreservationWriter(
            area: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        ))
    }

    private func representative(_ store: TestStoreOf<ChapterCanvasFeature>, verse: Int = 1) -> VerseDrawingSnapshot? {
        store.state.loadedDrawings?.representativesByVerse()[verse]
    }

    private func openWithLocalChanges(
        _ store: TestStoreOf<ChapterCanvasFeature>, _ environment: ControlledEditEnvironment, _ changes: ControlledLocalChanges
    ) async {
        await composeAndSubscribe(store, environment)
        while changes.subscriberCount == 0 { await Task.yield() }
    }

    /// 설정이 1절에 새 행으로 넣었다 — 옛 행은 그 내용 그대로 대표에서 내려온다(`DrawingVerseImporting`).
    private func importIntoVerseOne(on spy: RepositorySpy, previous: Data, previousVersion: Int?, previousMetadata: DrawingLayoutMetadata?) {
        spy.snapshots = { _ in [
            VerseDrawingSnapshot(verse: 1, rowID: CanvasTestSupport.rowA, isPresent: false, updateDate: Date(timeIntervalSince1970: 500),
                                 lineData: previous, drawingVersion: previousVersion, metadata: previousMetadata),
            VerseDrawingSnapshot(verse: 1, rowID: BibleDrawingRowID(raw: "row-imported"), isPresent: true,
                                 updateDate: Date(timeIntervalSince1970: 3_000), lineData: Data([9]), drawingVersion: 3,
                                 metadata: CanvasTestSupport.metadata())
        ] }
    }

    // MARK: - 절 메뉴의 수

    @Test("연결 전 필기는 캔버스에 겹치지 않고 절 메뉴의 「확인이 필요한 필기」 수에만 든다 — 설정 목록과 같은 절이다")
    func beforeConnectionDraftsAreCountedNotShown() async throws {
        let area = makeArea()
        defer { try? FileManager.default.removeItem(at: area.root) }
        let spy = spyWithVerseOne()
        _ = try await area.writer.saveDraft(previousDraft(session: "logged-out", verse: 1, ink: "logged-out", account: .localOnly))
        _ = try await area.writer.saveDraft(previousDraft(session: "no-hint", verse: 2, ink: "no-hint", account: .unverified(hint: nil)))
        // 다른 계정을 참고하던 필기 — 지금 계정에서는 열어 보지 않는다(P0-1).
        _ = try await area.writer.saveDraft(previousDraft(session: "hint-b", verse: 3, ink: "hint-b", account: .unverified(hint: accountB)))
        let current = confirmed(accountA, 1)
        let environment = ControlledEditEnvironment(current)
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: area.writer)
        await composeAndSubscribe(store, environment)

        // 캔버스는 지금 계정의 저장소 그대로다 — 연결 전 필기를 겹치지 않는다.
        #expect(representative(store)?.lineData == Data([1]))
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 } == false)
        #expect(store.state.drafts.hiddenCounts == [1: 1, 2: 1])

        // 설정의 목록 — 같은 파일 · 같은 저장소로 조회하면 같은 절이 「iCloud 연결 전에 쓴 필기」 로 오른다.
        let query = VerseDraftRecoveryQuery(reader: area.writer, repository: spy)
        let listed = try await query.inventory(in: .localOnly, environment: current).entries
            + query.inventory(in: .unverified, environment: current).entries
        #expect(listed.map(\.draft.key.verse).sorted() == [1, 2])
        #expect(listed.allSatisfy { $0.reason == .beforeConnection })
        await end(store, environment)
    }

    @Test("저장을 마친 뒤 이어 고친 내 예전 수정본은 절 메뉴 수에 들지 않는다 — 목록에서는 보관만 하는 예전 필기다")
    func savedEarlierRevisionIsNotCounted() async throws {
        let area = makeArea()
        defer { try? FileManager.default.removeItem(at: area.root) }
        let spy = spyWithVerseOne()
        var earlier = previousDraft(session: "earlier", verse: 1, ink: "earlier", baseFingerprint: "vc1-older")
        earlier.storeState = .stored
        earlier.sentFingerprints = [try #require(earlier.contentFingerprint)]
        _ = try await area.writer.saveDraft(earlier)
        let current = confirmed(accountA, 1)
        let environment = ControlledEditEnvironment(current)
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: area.writer)
        await composeAndSubscribe(store, environment)

        #expect(representative(store)?.lineData == Data([1]))
        #expect(store.state.drafts.hiddenCounts.isEmpty)
        let listed = try await VerseDraftRecoveryQuery(reader: area.writer, repository: spy).inventory(in: accountA, environment: current).entries
        #expect(listed.map(\.reason) == [.savedEarlier])
        await end(store, environment)
    }

    // MARK: - 설정에서 넣은 필기

    @Test("설정에서 넣은 필기는 그 장이 열려 있으면 다시 읽어 곧바로 보인다 — 편집하지 않은 장은 안내 없이")
    func localImportReloadsTheOpenChapter() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let changes = ControlledLocalChanges()
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: RecordingDraftStore())
        store.dependencies.localDrawingChanges = changes
        await openWithLocalChanges(store, environment, changes)
        #expect(representative(store)?.lineData == Data([1]))

        importIntoVerseOne(on: spy, previous: Data([1]), previousVersion: 1, previousMetadata: nil)
        changes.post(LocalDrawingChange(chapter: CanvasTestSupport.chapter, date: Date(timeIntervalSince1970: 2_000)))
        await store.receive(\.localDrawingChanged)
        await store.receive(\.arrivalChecked)
        await store.receive(\.drawingsLoaded)

        #expect(representative(store)?.lineData == Data([9]))
        #expect(store.state.arrival.notice == nil)
        #expect(store.state.arrival.phase == .idle)
        #expect(store.state.isInputEnabled)
        changes.finish()
        await end(store, environment)
    }

    @Test("편집한 장이어도 설정에서 넣은 필기는 다시 묻지 않고, 지금 필기를 보존한 뒤 다시 읽는다")
    func localImportIntoAnEditedChapterConfirmsWithoutAsking() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let changes = ControlledLocalChanges()
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [replaceVerseOne("mine")], environment: environment, drafts: drafts)
        store.dependencies.localDrawingChanges = changes
        await openWithLocalChanges(store, environment, changes)
        await draw(store, "mine")
        await store.receive(\.draftsSaved)
        await store.receive(\.saveFinished)

        // 설정이 1절에 넣었다 — 내가 저장한 필기는 옛 행 그대로 이전 필사 기록으로 남는다.
        importIntoVerseOne(on: spy, previous: Data("mine".utf8), previousVersion: 3, previousMetadata: CanvasTestSupport.metadata())
        changes.post(LocalDrawingChange(chapter: CanvasTestSupport.chapter, date: Date(timeIntervalSince1970: 2_000)))
        await store.receive(\.localDrawingChanged)
        await store.receive(\.arrivalChecked)
        // 「다른 필사가 도착했어요 · 확인하기」 를 묻지 않는다 — 사용자가 이 장에 넣으라고 골랐다.
        #expect(store.state.arrival.notice == .confirming)
        await store.receive(\.drawingsLoaded)

        #expect(representative(store)?.lineData == Data([9]))
        #expect(store.state.arrival.notice == nil)
        // 내 필기는 이전 필사 기록에 그대로 있어 확인할 것이 없다.
        #expect(store.state.drafts.hiddenCounts.isEmpty)
        #expect(store.state.isInputEnabled)
        changes.finish()
        await end(store, environment)
    }

    @Test("다른 장에 넣었으면 열린 장은 아무것도 하지 않는다 — 그 장을 열 때 저장소를 읽는다")
    func localImportIntoAnotherChapterIsIgnored() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let changes = ControlledLocalChanges()
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: RecordingDraftStore())
        store.dependencies.localDrawingChanges = changes
        await openWithLocalChanges(store, environment, changes)
        let loadsBefore = spy.loadedChapters.value.count

        changes.post(LocalDrawingChange(chapter: BibleChapter(title: .genesis, chapter: 1), date: Date(timeIntervalSince1970: 2_000)))
        await store.receive(\.localDrawingChanged)

        #expect(store.state.arrival.phase == .idle)
        #expect(spy.loadedChapters.value.count == loadsBefore)
        changes.finish()
        await end(store, environment)
    }
}
