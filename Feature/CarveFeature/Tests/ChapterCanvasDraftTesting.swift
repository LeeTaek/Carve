//
//  ChapterCanvasDraftTesting.swift
//  CarveFeatureTest
//
//  절 초안 — 편집마다 이 기기의 비동기화 영역에 남기고, 귀속할 근거가 없는 세션은 초안에만 쓴다 (정책 §12-6 구현 순서 ②).
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 초안 시험이 함께 쓰는 표본.
@MainActor
protocol DraftTestSamples: EditSessionTestHelpers {}

extension DraftTestSamples {
    /// 저장소 스파이가 주는 1절 행(`CanvasTestSupport.snapshot`)의 내용 지문.
    var storedVerseOneFingerprint: String {
        VerseContentFingerprint.make(lineData: Data([1]), drawingVersion: 1, layoutMetadataBlob: nil)
    }

    /// 앞선 세션이 1절에 남긴 초안.
    func previousDraft(
        session: String = "earlier-session",
        ink: String = "earlier",
        baseFingerprint: String? = nil,
        lineData: Data? = nil,
        drawingVersion: Int? = 3,
        withMetadata: Bool = true,
        account: VerseEditAccountBasis? = nil,
        storeOwnership: AccountScope? = nil,
        ownershipInjected: Bool? = nil
    ) -> VerseDraft {
        let base = baseFingerprint ?? storedVerseOneFingerprint
        let metadata = withMetadata ? try? CanvasTestSupport.metadata().encodedBlob() : nil
        return VerseDraft(
            key: VerseDraftKey(sessionID: session, chapter: CanvasTestSupport.chapter, verse: 1),
            revision: 3,
            rowID: CanvasTestSupport.rowA,
            lineData: lineData ?? Data(ink.utf8),
            drawingVersion: drawingVersion,
            layoutMetadataData: metadata,
            base: .legacy(rowID: CanvasTestSupport.rowA, contentFingerprint: base),
            baseFingerprint: base,
            account: account ?? .confirmed(AccountServerWorkToken(scope: accountA, generation: 0)),
            knownEpochs: [],
            storeOwnership: storeOwnership,
            eraseGeneration: 0,
            savedAt: Date(timeIntervalSince1970: 500),
            ownershipInjected: ownershipInjected
        )
    }

    /// 1절 행(rowA)을 고치는 편집 결과.
    func replaceVerseOne(_ tag: String) -> DrawingEditResult {
        DrawingEditResult(
            ownership: OwnershipSnapshot(map: [:], layoutSignature: CanvasTestSupport.layout.signature),
            mutations: [.replace(verse: 1, rowID: CanvasTestSupport.rowA, data: Data(tag.utf8), metadata: CanvasTestSupport.metadata())],
            issuedRowIDs: [:]
        )
    }

    func spyWithVerseOne() -> RepositorySpy {
        let spy = RepositorySpy()
        spy.snapshots = { _ in [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] }
        return spy
    }

    func draw(_ store: TestStoreOf<ChapterCanvasFeature>, _ tag: String = "a") async {
        await store.send(.editBegan)
        await store.send(.editEnded(CanvasTestSupport.edit(tag)))
        await store.receive(\.mutationsPrepared)
    }
}

/// 이 파일이 막는 것:
/// - 귀속할 근거가 없는 세션의 필기를 저장소(`BibleDrawing`)에 쓰는 것 — 동기화돼 다음에 확인되는 계정으로 올라간다(ACC-1 F30)
/// - 초안에만 있는 필기가 다시 읽기 · 재실행 뒤 화면에서 사라지는 것
/// - 그 사이 저장소 내용이 바뀐 옛 초안을 그 위에 겹쳐 새 내용을 본 척 가리는 것
/// - 초안을 남기지 못했는데 "이 기기에 저장됨" 이라고 말하는 것
@Suite("절 초안 — 보존만 하는 세션")
@MainActor
struct ChapterCanvasDraftTesting: DraftTestSamples {
    @Test("저장소 소유 근거가 없는 세션은 편집을 초안에만 남기고 저장소에 쓰지 않는다")
    func preserveOnlyEditGoesToDraftOnly() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        #expect(!store.state.persistsToStore)

        await draw(store)
        await store.receive(\.draftsSaved)

        #expect(spy.applied.value.isEmpty)
        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.localSaveIndicator == .saved)
        let saved = try #require(drafts.stored(in: accountA).first)
        #expect(saved.key.verse == 2)
        #expect(saved.rowID == CanvasTestSupport.newRow)
        #expect(saved.lineData == Data("create-a".utf8))
        // 행이 없던 절 — 기준은 빈 절이다. 세션의 계정 근거 · K · (없는) 소유 근거를 그대로 든다.
        #expect(saved.base == .empty)
        #expect(saved.baseFingerprint == nil)
        #expect(saved.account == .confirmed(AccountServerWorkToken(scope: accountA, generation: 1)))
        #expect(saved.knownEpochs == [])
        #expect(saved.storeOwnership == nil)
        // 화면의 근거에 겹쳐 있고, 저장소에 없는 행으로 기억한다.
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 && $0.lineData == Data("create-a".utf8) } == true)
        #expect(store.state.drafts.draftOnlyRowIDs.contains(CanvasTestSupport.newRow))
        await end(store, environment)
    }

    @Test("다시 합성해도 초안에만 있는 필기가 남는다 — 지금 세션의 초안을 다시 겹친다")
    func reloadKeepsDraftOnlyInk() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        let inputs = LockIsolated<[[VerseDrawingSnapshot]]>([])
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts, composeInputs: inputs
        )
        await composeAndSubscribe(store, environment)
        await draw(store)
        await store.receive(\.draftsSaved)

        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout))
        await store.receive(\.drawingsLoaded)

        let last = try #require(inputs.value.last)
        #expect(last.contains { $0.verse == 2 && $0.lineData == Data("create-a".utf8) })
        #expect(store.state.isInputEnabled)
        #expect(spy.applied.value.isEmpty)
        await end(store, environment)
    }

    @Test("새 세션은 기준이 그대로인 앞선 세션의 초안을 이어 보이고, 그 절을 편집하면 이어받아 지운다")
    func matchingEarlierDraftIsContinuedAndSuperseded() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        let earlier = previousDraft()
        drafts.seed(earlier)
        let store = makeStore(spy: spy, results: [replaceVerseOne("continued")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)

        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("earlier".utf8))
        #expect(store.state.drafts.adopted[DraftVerse(chapter: CanvasTestSupport.chapter, verse: 1)] == earlier.ref)

        await draw(store)
        await store.receive(\.draftsSaved)

        let remaining = drafts.stored(in: accountA)
        #expect(remaining.count == 1)
        #expect(remaining.first?.lineData == Data("continued".utf8))
        // 이어 쓴 초안은 앞선 초안의 기준(저장소 1절)을 든다 — 사이에 들어온 내용이 있었는지 나중에 가린다.
        #expect(remaining.first?.baseFingerprint == storedVerseOneFingerprint)
        // 보존만 하던 초안이다 — 이어 쓴 초안은 그 출처를 그대로 잇고, 그래서 원 초안을 대신한다.
        #expect(remaining.first?.provenance == earlier.provenance)
        #expect(drafts.removed.value == [earlier.key])
        #expect(store.state.drafts.adopted.isEmpty)
        await end(store, environment)
    }

    @Test("기준이 달라진 앞선 세션의 초안은 보이지 않고 남는다")
    func changedBaseDraftIsKeptHidden() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        let earlier = previousDraft(baseFingerprint: "vc1-before-remote")
        drafts.seed(earlier)
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)

        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data([1]))
        #expect(store.state.drafts.adopted.isEmpty)
        await end(store, environment)
        #expect(drafts.stored(in: accountA) == [earlier])
    }

    /// 로컬 저장은 보존이 아니다 — 전송 전에 계정이 바뀌면 미러링이 그 행을 지우고 되살리지 않는다(ACC-1 F29). 그때 이 초안이 유일한 사본이다.
    @Test("내용이 이미 저장소에 있는 앞선 세션의 초안은 겹치지 않되, 불러온 뒤에도 지우지 않는다")
    func settledDraftIsKeptOnLoad() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        let settled = previousDraft(lineData: Data([1]), drawingVersion: 1, withMetadata: false)
        drafts.seed(settled)
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)

        #expect(store.state.drafts.adopted.isEmpty)
        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data([1]))
        await end(store, environment)
        #expect(drafts.stored(in: accountA) == [settled])
        #expect(drafts.removed.value.isEmpty)
    }

    @Test("초안 저장소가 없으면 보존만 하는 세션의 편집을 실패로 알리고 큐에 남긴다")
    func missingDraftStoreFailsPreserveOnlyEdit() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: nil)
        await composeAndSubscribe(store, environment)

        await draw(store)

        #expect(store.state.localSaveIndicator == .failed(retryCount: 1))
        #expect(store.state.saveRetryCount == 1)
        #expect(!store.state.pendingMutations.isEmpty)
        #expect(spy.applied.value.isEmpty)
        await end(store, environment)
    }

    @Test("초안이 전체 삭제 세대에 걸려 거절되면 미저장분을 버리고 다시 읽는다")
    func eraseRejectedDraftClearsAndReloads() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        drafts.rejectNext.setValue(true)
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        let loadsBefore = spy.loadedChapters.value.count

        await draw(store)
        await store.receive(\.draftsSaved)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.pendingMutations.isEmpty)
        #expect(store.state.editRevisionAtClear == store.state.editRevision)
        #expect(spy.loadedChapters.value.count == loadsBefore + 1)
        #expect(drafts.saves.value.isEmpty)
        await end(store, environment)
    }

    // MARK: - 메뉴

    /// 지우기(보관 후 초기화) · 기록 복원은 저장소 행을 바꾼다. 초안에만 있는 필기를 두고 바꾸면 다시 읽을 때 지운 절이 돌아온다.
    @Test("저장소에 쓰지 않는 세션은 지우기 · 이전 필사 메뉴를 띄우지 않는다")
    func preserveOnlySessionHidesEraseAndHistory() async {
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let store = makeStore(spy: RepositorySpy(), results: [], environment: environment, drafts: RecordingDraftStore())
        await composeAndSubscribe(store, environment)
        var state = store.state
        state.loadedDrawings = [
            VerseDrawingSnapshot(verse: 1, rowID: CanvasTestSupport.rowA, isPresent: true, updateDate: Date(timeIntervalSince1970: 200),
                                 lineData: Self.inkData(), drawingVersion: 3, metadata: nil),
            VerseDrawingSnapshot(verse: 1, rowID: BibleDrawingRowID(raw: "row-archive"), isPresent: false,
                                 updateDate: Date(timeIntervalSince1970: 100), lineData: Self.inkData(), drawingVersion: 3, metadata: nil)
        ]
        let point = CGPoint(x: 10, y: 15)

        let hidden = ChapterCanvasFeature.menuAvailability(at: point, state: state)
        #expect(hidden.canFavorite)
        #expect(!hidden.canErase)
        #expect(!hidden.canViewHistory)

        // 소유가 확인된 유효 세션이면 띄운다.
        state.editEnvironment = confirmed(accountA, 1)
        state.sessionValidity = .valid
        let shown = ChapterCanvasFeature.menuAvailability(at: point, state: state)
        #expect(shown.canErase)
        #expect(shown.canViewHistory)
        await end(store, environment)
    }

    /// 실제 획이 하나 있는 `PKDrawing` 데이터 — 메뉴 가용성은 획 유무로 판정한다.
    private static func inkData() -> Data {
        let path = PKStrokePath(
            controlPoints: [PKStrokePoint(location: CGPoint(x: 5, y: 5), timeOffset: 0, size: CGSize(width: 2, height: 2),
                                          opacity: 1, force: 1, azimuth: 0, altitude: 0)],
            creationDate: Date(timeIntervalSince1970: 0)
        )
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
    }
}

/// 이 파일이 막는 것:
/// - 계정을 확인하는 동안 저장소에 쓰는 것, 또는 그 사이 편집을 저장소에 영영 쓰지 않는 것
/// - 확인이 오래 걸리는 동안 회전 · 복원 재합성이 입력을 잠근 채 멈추는 것
/// - 저장소 저장(로컬 확정)만으로 마지막 로컬 사본인 초안을 지우는 것(ACC-1 F29)
@Suite("절 초안 — 유효 세션 · 확인 대기")
@MainActor
struct ChapterCanvasDraftValiditySessionTesting: DraftTestSamples {
    /// 저장소 저장은 로컬 확정일 뿐이다. 전송 전에 계정이 바뀌면 그 행은 지워지고 되살아나지 않는다(ACC-1 F29) — 초안이 마지막 로컬 사본이다.
    @Test("유효한 세션은 초안을 남기고 저장소에도 쓰며, 저장소 저장을 마쳐도 초안을 지우지 않는다")
    func validSessionKeepsDraftAfterStoreSave() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        #expect(store.state.persistsToStore)

        await draw(store)
        await store.receive(\.saveFinished)
        await end(store, environment)

        #expect(spy.applied.value.count == 1)
        #expect(drafts.saves.value.count == 1)
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-a".utf8)])
        #expect(drafts.removed.value.isEmpty)
        #expect(store.state.pendingMutations.isEmpty)
        // 역할은 끝났다 — 다시 읽을 때 겹치지 않는다.
        #expect(store.state.drafts.storedRevisions[CanvasTestSupport.newRow] == 1)
    }

    @Test("확인 대기 중에는 초안만 남기고 미저장분을 붙잡아 두었다가, 같은 계정으로 확인되면 저장소에 쓴다")
    func awaitingHoldsDraftedPendingUntilConfirmed() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        environment.change(to: DrawingEditEnvironment(accountState: .unconfirmed(lastConfirmed: accountA), serverWork: nil,
                                                      knowledge: EraseEpochKnowledge()))
        await store.receive(\.editEnvironmentChanged)

        await draw(store)
        await store.receive(\.draftsSaved)
        #expect(spy.applied.value.isEmpty)
        #expect(store.state.pendingMutations.count == 1)
        // 이미 초안으로 이 기기에 남았다.
        #expect(store.state.localSaveIndicator == .saved)

        environment.change(to: confirmed(accountA, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.saveFinished)
        await end(store, environment)

        #expect(spy.applied.value.count == 1)
        #expect(store.state.pendingMutations.isEmpty)
        // 저장소에 쓴 뒤에도 초안은 남는다(ACC-1 F29).
        #expect(drafts.stored(in: accountA).count == 1)
    }

    /// 확인하는 동안 읽은 결과는 어느 계정의 것인지 모른다 — 섞지 않되, 세션을 닫아 방금 쓴 초안을 다른 묶음으로 가리지도 않는다.
    @Test("확인 대기 중에 회전하면 그때 읽은 결과는 버리고 마지막으로 알던 내용으로 합성해 입력을 열며, 확인되면 다시 읽는다")
    func awaitingWithDraftedPendingStillRecomposes() async {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        environment.change(to: DrawingEditEnvironment(accountState: .unconfirmed(lastConfirmed: accountA), serverWork: nil,
                                                      knowledge: EraseEpochKnowledge()))
        await store.receive(\.editEnvironmentChanged)
        await draw(store)
        await store.receive(\.draftsSaved)
        let loadsBefore = spy.loadedChapters.value.count

        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout))
        await store.receive(\.drawingsLoaded)

        #expect(spy.loadedChapters.value.count == loadsBefore + 1)
        #expect(store.state.sessionEnd == nil)
        #expect(store.state.editEnvironment == confirmed(accountA, 1))
        #expect(store.state.renderedLayout == CanvasTestSupport.otherLayout)
        #expect(store.state.isInputEnabled)
        #expect(store.state.pendingMutations.count == 1)
        #expect(store.state.reloadAfterAccountCheck)

        // 같은 계정으로 확인되면 붙잡아 둔 미저장분을 저장소에 쓰고 다시 읽는다.
        environment.change(to: confirmed(accountA, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.saveFinished)
        await store.receive(\.drawingsLoaded)
        #expect(spy.loadedChapters.value.count == loadsBefore + 2)
        #expect(spy.applied.value.count == 1)
        #expect(!store.state.reloadAfterAccountCheck)
        await end(store, environment)
    }
}
