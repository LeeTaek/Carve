//
//  ChapterCanvasArrivalTesting.swift
//  CarveFeatureTest
//
//  늦게 도착한 필사를 열린 장에 반영한다 — 2.0.0 필수 범위 (2026-09-21 후속 리뷰 P0-3, 사용자 결정).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 시험이 정한 때에 import 성공을 알리는 도착 신호.
final class ControlledArrivals: CloudImportArrivalClient, @unchecked Sendable {
    private let continuations = LockIsolated<[AsyncStream<Date>.Continuation]>([])

    var subscriberCount: Int { continuations.value.count }

    func arrivals() -> AsyncStream<Date> {
        let (stream, continuation) = AsyncStream<Date>.makeStream()
        continuations.withValue { $0.append(continuation) }
        return stream
    }

    /// import 가 성공으로 끝났다 — 시험의 조회 시각(1_000)보다 늦다.
    func arrive(at seconds: TimeInterval = 2_000) {
        continuations.value.forEach { $0.yield(Date(timeIntervalSince1970: seconds)) }
    }

    func finish() {
        continuations.value.forEach { $0.finish() }
    }
}

/// 이 파일이 막는 것(사용자 결정 2026-09-21 — "2.0.0 필수 범위: 늦은 import 의 열린 장 반영. 미편집 장은 자동 갱신, 편집한 장은 보존 후 사용자 확인"):
/// - 재설치 뒤 「먼저 시작하기」 로 들어간 열린 장에 늦게 도착한 필사가 **다시 켜기 전까지 나타나지 않는 것**
/// - 편집한 장(펜을 뗀 뒤 포함)을 도착한 필사로 **자동으로 바꾸는 것** — 펜을 대고 있는지만 보면 이렇게 된다
/// - 획을 긋는 중 · 미보고 획 · 초안 저장 중에 다시 합성해 **긋던 필기를 잃는 것**
/// - 다시 읽지 못했을 때 화면 · 초안을 잃거나 다시 시도할 길이 없는 것
/// - 「확인하기」 뒤 기준이 달라진 내 초안을 **조용히 숨기는 것**(「남은 필기」 로 잇지 않음)
@Suite("늦게 도착한 필사 — 열린 장 반영")
@MainActor
struct ChapterCanvasArrivalTesting: DraftTestSamples {

    private func makeArrivalStore(
        spy: RepositorySpy,
        results: [DrawingEditResult] = [],
        environment: ControlledEditEnvironment,
        drafts: RecordingDraftStore,
        arrivals: ControlledArrivals
    ) -> TestStoreOf<ChapterCanvasFeature> {
        let store = makeStore(spy: spy, results: results, environment: environment, drafts: drafts)
        store.dependencies.cloudImportArrivals = arrivals
        return store
    }

    /// 합성하고 환경 · 도착 구독이 걸릴 때까지 기다린다.
    private func open(_ store: TestStoreOf<ChapterCanvasFeature>, _ environment: ControlledEditEnvironment, _ arrivals: ControlledArrivals) async {
        await composeAndSubscribe(store, environment)
        while arrivals.subscriberCount == 0 { await Task.yield() }
    }

    private func close(_ store: TestStoreOf<ChapterCanvasFeature>, _ environment: ControlledEditEnvironment, _ arrivals: ControlledArrivals) async {
        arrivals.finish()
        await end(store, environment)
    }

    /// 다른 기기의 필사가 들어와 1절 행(rowA)의 내용이 바뀌었다.
    private func importArrives(on spy: RepositorySpy, verseOne ink: UInt8 = 7) {
        spy.snapshots = { _ in
            [VerseDrawingSnapshot(verse: 1, rowID: CanvasTestSupport.rowA, isPresent: true, updateDate: Date(timeIntervalSince1970: 1_500),
                                  lineData: Data([ink]), drawingVersion: 1, metadata: nil)]
        }
    }

    private func verseOne(_ store: TestStoreOf<ChapterCanvasFeature>) -> Data? {
        store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData
    }

    // MARK: - 편집하지 않은 장 — 자동 반영

    @Test("편집하지 않은 장은 도착한 필사를 다시 읽어 자동으로 반영하고, 안내를 띄우지 않는다")
    func untouchedChapterReloadsAutomatically() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let store = makeArrivalStore(spy: spy, environment: environment, drafts: RecordingDraftStore(), arrivals: arrivals)
        await open(store, environment, arrivals)
        #expect(verseOne(store) == Data([1]))

        importArrives(on: spy)
        arrivals.arrive()
        await store.receive(\.importArrived)
        await store.receive(\.arrivalChecked)
        await store.receive(\.drawingsLoaded)

        #expect(verseOne(store) == Data([7]))
        #expect(store.state.arrival.notice == nil)
        #expect(store.state.arrival.phase == .idle)
        #expect(store.state.isInputEnabled)
        await close(store, environment, arrivals)
    }

    @Test("도착했어도 이 장이 바뀌지 않았으면 다시 읽지도 알리지도 않는다")
    func unchangedChapterIsLeftAlone() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let store = makeArrivalStore(spy: spy, environment: environment, drafts: RecordingDraftStore(), arrivals: arrivals)
        await open(store, environment, arrivals)
        let loads = spy.loadedChapters.value.count

        arrivals.arrive()
        await store.receive(\.importArrived)
        await store.receive(\.arrivalChecked)

        // 확인 조회 한 번뿐 — 합성을 다시 하지 않는다.
        #expect(spy.loadedChapters.value.count == loads + 1)
        #expect(store.state.arrival.notice == nil)
        #expect(store.state.arrival.phase == .idle)
        #expect(!store.state.isReloading)
        await close(store, environment, arrivals)
    }

    @Test("이 조회를 시작하기 전에 끝난 import 는 이미 들어 있다 — 다시 보지 않는다")
    func arrivalBeforeTheLoadIsIgnored() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let store = makeArrivalStore(spy: spy, environment: environment, drafts: RecordingDraftStore(), arrivals: arrivals)
        await open(store, environment, arrivals)
        let loads = spy.loadedChapters.value.count

        arrivals.arrive(at: 500)
        await store.receive(\.importArrived)

        #expect(store.state.arrival.phase == .idle)
        #expect(spy.loadedChapters.value.count == loads)
        await close(store, environment, arrivals)
    }

    // MARK: - 편집한 장 — 바꾸지 않고 알린다

    @Test("편집하고 펜을 뗀 장은 도착한 필사로 바꾸지 않고 「다른 필사가 도착했어요 · 확인하기」 를 띄운다")
    func editedChapterIsNotReplaced() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let store = makeArrivalStore(
            spy: spy, results: [CanvasTestSupport.createResult("mine")], environment: environment, drafts: RecordingDraftStore(), arrivals: arrivals
        )
        await open(store, environment, arrivals)
        await draw(store, "mine")
        await store.receive(\.draftsSaved)
        #expect(!store.state.isEditing)
        let bases = store.state.drafts.bases

        importArrives(on: spy)
        arrivals.arrive()
        await store.receive(\.importArrived)
        await store.receive(\.arrivalChecked)

        #expect(store.state.arrival.notice == .arrived)
        #expect(store.state.arrival.notice?.actionTitle == "확인하기")
        // 화면 · 세션은 그대로다 — 다시 읽지 않았다.
        #expect(verseOne(store) == Data([1]))
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 && $0.lineData == Data("create-mine".utf8) } == true)
        #expect(store.state.drafts.bases == bases)
        #expect(!store.state.isReloading)
        await close(store, environment, arrivals)
    }

    @Test("앞선 세션의 초안이 겹쳐 보이는 장도 자동으로 바꾸지 않는다 — 그 초안을 조용히 감추지 않는다")
    func chapterShowingAnEarlierDraftIsNotReplaced() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let drafts = RecordingDraftStore()
        drafts.seed(previousDraft(verse: 2, ink: "earlier"))
        let store = makeArrivalStore(spy: spy, environment: environment, drafts: drafts, arrivals: arrivals)
        await open(store, environment, arrivals)
        #expect(store.state.drafts.adopted[DraftVerse(chapter: CanvasTestSupport.chapter, verse: 2)] != nil)

        importArrives(on: spy)
        arrivals.arrive()
        await store.receive(\.importArrived)
        await store.receive(\.arrivalChecked)

        #expect(store.state.arrival.notice == .arrived)
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 && $0.lineData == Data("earlier".utf8) } == true)
        await close(store, environment, arrivals)
    }

    // MARK: - 보류 — 획 · 미보고 획 · 초안 저장

    @Test("획을 긋는 중에 도착하면 보류하고, 획이 끝나 초안으로 남은 뒤 이어 간다 — 그 획으로 편집한 장이 됐으니 알린다")
    func arrivalDuringAStrokeWaitsForTheStroke() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let drafts = RecordingDraftStore()
        let store = makeArrivalStore(
            spy: spy, results: [CanvasTestSupport.createResult("stroke")], environment: environment, drafts: drafts, arrivals: arrivals
        )
        await open(store, environment, arrivals)
        let loads = spy.loadedChapters.value.count

        await store.send(.editBegan)
        importArrives(on: spy)
        arrivals.arrive()
        await store.receive(\.importArrived)
        // 긋는 중 — 확인 조회도 다시 읽기도 하지 않는다.
        #expect(store.state.arrival.phase == .waiting(.check))
        #expect(!store.state.isSettledForReload)
        #expect(spy.loadedChapters.value.count == loads)

        await store.send(.editEnded(CanvasTestSupport.edit("stroke")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)
        await store.receive(\.arrivalChecked)

        #expect(drafts.stored(in: accountA).contains { $0.lineData == Data("create-stroke".utf8) })
        #expect(store.state.arrival.notice == .arrived)
        #expect(verseOne(store) == Data([1]))
        await close(store, environment, arrivals)
    }

    @Test("초안을 쓰는 중에 도착하면 초안이 남을 때까지 기다린다")
    func arrivalWhileSavingADraftWaits() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let drafts = RecordingDraftStore()
        let store = makeArrivalStore(
            spy: spy, results: [CanvasTestSupport.createResult("held")], environment: environment, drafts: drafts, arrivals: arrivals
        )
        await open(store, environment, arrivals)
        await editWithHeldDraft(store, drafts, tag: "held")
        #expect(store.state.isSavingDrafts)

        importArrives(on: spy)
        arrivals.arrive()
        await store.receive(\.importArrived)
        #expect(store.state.arrival.phase == .waiting(.check))

        drafts.release()
        await store.receive(\.draftsSaved)
        await store.receive(\.arrivalChecked)
        #expect(store.state.arrival.notice == .arrived)
        await close(store, environment, arrivals)
    }

    @Test("캔버스가 있으면 먼저 인계를 받는다 — 뷰에만 있던 미보고 획이 들어와 편집한 장이 되면 자동으로 바꾸지 않는다")
    func unreportedStrokeIsHandedOffFirst() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let store = makeArrivalStore(
            spy: spy, results: [CanvasTestSupport.createResult("late")], environment: environment, drafts: RecordingDraftStore(), arrivals: arrivals
        )
        await open(store, environment, arrivals)
        await attachCanvas(store)
        let token = store.state.handoffToken

        importArrives(on: spy)
        arrivals.arrive()
        await store.receive(\.importArrived)
        // 편집하지 않은 장으로 보이지만, 뷰의 디바운스 안에 획이 있을 수 있다 — 인계를 요청하고 기다린다.
        #expect(store.state.handoffToken == token + 1)
        #expect(store.state.arrival.phase == .handingOff(.check, token: token + 1))
        #expect(!store.state.isReloading)

        // 뷰가 미보고 획을 보고한다(`ChapterCanvasController.completeHandoff` — 편집이 인계 완료보다 먼저 온다). 그 획이 초안으로 남아 조용해져도
        // 인계가 끝나기 전에는 확인하지 않는다.
        await store.send(.editEnded(CanvasTestSupport.edit("late")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.draftsSaved)
        #expect(store.state.isSettledForReload)
        #expect(store.state.arrival.phase == .handingOff(.check, token: token + 1))

        await store.send(.editHandoffCompleted(token: token + 1))
        await store.receive(\.arrivalChecked)

        #expect(store.state.arrival.notice == .arrived)
        #expect(verseOne(store) == Data([1]))
        await close(store, environment, arrivals)
    }

    // MARK: - 다시 읽지 못함

    @Test("다시 읽지 못하면 지금 화면을 그대로 두고 「다시 시도」 를 띄우며, 다시 시도가 성공하면 반영한다")
    func failedReloadKeepsTheScreenAndOffersRetry() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let store = makeArrivalStore(spy: spy, environment: environment, drafts: RecordingDraftStore(), arrivals: arrivals)
        await open(store, environment, arrivals)

        // 확인 조회는 성공하고 다시 읽기만 실패하게 한다 — 두 조회를 차례로 붙잡아 실패를 두 번째에만 건다.
        importArrives(on: spy)
        spy.holdNextLoadCall()
        arrivals.arrive()
        await store.receive(\.importArrived)
        while spy.loadGate.value == nil { await Task.yield() }
        spy.holdNextLoadCall()
        spy.releaseLoad()
        await store.receive(\.arrivalChecked)
        while spy.loadGate.value == nil { await Task.yield() }
        spy.loadFailures.setValue(["reload boom"])
        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)
        #expect(store.state.arrival.notice == .reloadFailed(.check))
        #expect(store.state.arrival.notice?.actionTitle == "다시 시도")
        #expect(verseOne(store) == Data([1]))
        #expect(store.state.isInputEnabled)

        await store.send(.arrivalNoticeTapped)
        await store.receive(\.arrivalChecked)
        await store.receive(\.drawingsLoaded)
        #expect(verseOne(store) == Data([7]))
        #expect(store.state.arrival.notice == nil)
        await close(store, environment, arrivals)
    }
}

// MARK: - 「확인하기」

extension ChapterCanvasArrivalTesting {
    /// 사용자 결정 — "‘확인하기’는 최신 저장소와 초안을 비교해 기존 복구 규칙으로 보여주되, 기준이 달라진 내 초안을 조용히 숨기지 않고 「남은
    /// 필기」로 연결한다. 자동 병합이나 새 복구 기능은 없다."
    @Test("확인하기는 지금 필기를 보존한 뒤 새 세션으로 다시 읽는다 — 도착한 필사를 보이고, 기준이 달라진 내 초안은 지우지 않고 「남은 필기」 로 잇는다")
    func confirmReloadsAndLinksHiddenDrafts() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let drafts = RecordingDraftStore()
        let store = makeArrivalStore(spy: spy, results: [replaceVerseOne("mine")], environment: environment, drafts: drafts, arrivals: arrivals)
        await open(store, environment, arrivals)
        await draw(store, "mine")
        await store.receive(\.draftsSaved)
        let mine = try #require(drafts.stored(in: accountA).first)
        let closingSession = store.state.drafts.sessionID
        #expect(verseOne(store) == Data("mine".utf8))

        importArrives(on: spy)
        arrivals.arrive()
        await store.receive(\.importArrived)
        await store.receive(\.arrivalChecked)
        #expect(store.state.arrival.notice == .arrived)

        await store.send(.arrivalNoticeTapped)
        await store.receive(\.drawingsLoaded)

        // 도착한 필사가 보이고, 이 세션은 닫혔다(새 세션).
        #expect(verseOne(store) == Data([7]))
        #expect(store.state.drafts.sessionID == nil)
        #expect(store.state.drafts.sessionID != closingSession)
        // 내 초안은 지우지 않았고, 조용히 숨기지 않고 「남은 필기」 로 잇는다.
        #expect(drafts.stored(in: accountA) == [mine])
        #expect(store.state.drafts.hiddenCounts == [1: 1])
        #expect(store.state.arrival.notice == .draftsHidden(count: 1))
        #expect(store.state.arrival.notice?.actionTitle == "남은 필기 보기")
        #expect(store.state.isInputEnabled)

        await store.send(.arrivalNoticeTapped)
        await store.receive(.delegate(.draftRecoveryRequested))
        #expect(store.state.arrival.notice == nil)
        await close(store, environment, arrivals)
    }

    @Test("확인하기 뒤에도 기준이 그대로인 내 초안은 이어 보인다 — 알릴 것이 없다")
    func confirmKeepsDraftsWhoseBaseIsUnchanged() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let drafts = RecordingDraftStore()
        let store = makeArrivalStore(
            spy: spy, results: [CanvasTestSupport.createResult("verse-two")], environment: environment, drafts: drafts, arrivals: arrivals
        )
        await open(store, environment, arrivals)
        await draw(store, "verse-two")
        await store.receive(\.draftsSaved)

        importArrives(on: spy)
        arrivals.arrive()
        await store.receive(\.importArrived)
        await store.receive(\.arrivalChecked)
        await store.send(.arrivalNoticeTapped)
        await store.receive(\.drawingsLoaded)

        // 1절은 도착한 필사, 2절은 기준(빈 절)이 그대로라 내 초안이 이어 보인다.
        #expect(verseOne(store) == Data([7]))
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 && $0.lineData == Data("create-verse-two".utf8) } == true)
        #expect(store.state.arrival.notice == nil)
        await close(store, environment, arrivals)
    }

    @Test("확인하기의 다시 읽기가 실패하면 세션도 화면도 그대로 두고 「다시 시도」 를 띄운다")
    func failedConfirmKeepsTheSession() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let drafts = RecordingDraftStore()
        let store = makeArrivalStore(spy: spy, results: [replaceVerseOne("mine")], environment: environment, drafts: drafts, arrivals: arrivals)
        await open(store, environment, arrivals)
        await draw(store, "mine")
        await store.receive(\.draftsSaved)
        let session = store.state.drafts.sessionID
        let bases = store.state.drafts.bases

        importArrives(on: spy)
        arrivals.arrive()
        await store.receive(\.importArrived)
        await store.receive(\.arrivalChecked)

        spy.loadFailures.setValue(["confirm boom"])
        await store.send(.arrivalNoticeTapped)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.arrival.notice == .reloadFailed(.confirm))
        #expect(store.state.drafts.sessionID == session)
        #expect(store.state.drafts.bases == bases)
        #expect(verseOne(store) == Data("mine".utf8))
        #expect(store.state.isInputEnabled)
        await close(store, environment, arrivals)
    }
}

// MARK: - 필수 조건 (next-session 인계 · 2026-09-21 후속 리뷰 P0-3)

extension ChapterCanvasArrivalTesting {
    @Test("다시 합성해도 되는가는 획을 긋는 중(미보고 획 포함)도 본다 — 긋는 동안 온 재조회 결과는 획이 끝난 뒤 합성한다")
    func settledForReloadWaitsForTheStroke() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let store = makeArrivalStore(spy: spy, environment: environment, drafts: RecordingDraftStore(), arrivals: arrivals)
        await open(store, environment, arrivals)
        #expect(store.state.isSettledForReload)

        // 도착한 필사를 자동으로 다시 읽는 사이 획이 시작됐다(입력이 닫히기 직전의 한 틈).
        importArrives(on: spy)
        spy.holdNextLoadCall()
        arrivals.arrive()
        await store.receive(\.importArrived)
        // 확인 조회가 붙잡혔다 — 풀고 다시 읽기를 붙잡는다.
        while spy.loadGate.value == nil { await Task.yield() }
        spy.holdNextLoadCall()
        spy.releaseLoad()
        await store.receive(\.arrivalChecked)
        #expect(store.state.isReloading)
        while spy.loadGate.value == nil { await Task.yield() }
        await store.send(.editBegan)
        #expect(!store.state.isSettledForReload)
        let rendered = store.state.renderedRevision
        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)
        // 긋는 중에는 합성하지 않는다 — 긋던 획이 사라지지 않게. 다시 읽기는 획이 끝난 뒤로 미룬다.
        #expect(store.state.renderedRevision == rendered)
        #expect(store.state.reloadWhenSettled)
        #expect(store.state.isReloading)

        await store.send(.editCancelled)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.renderedRevision > rendered)
        #expect(verseOne(store) == Data([7]))
        #expect(!store.state.isReloading)
        #expect(store.state.arrival.phase == .idle)
        await close(store, environment, arrivals)
    }

    @Test("도착 반영으로 다시 읽어도 편집한 절의 기준 · 이어 보인 초안 · 보이기만 하는 출처가 그대로다")
    func reloadKeepsBasesAdoptedAndInherited() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let arrivals = ControlledArrivals()
        let drafts = RecordingDraftStore()
        let store = makeArrivalStore(
            spy: spy, results: [CanvasTestSupport.createResult("other-chapter")], environment: environment, drafts: drafts, arrivals: arrivals
        )
        // 앞 장(CanvasTestSupport.chapter)에서 2절을 편집한 뒤 다음 장으로 간다 — 그 절의 기준은 이 세션에 남는다.
        await open(store, environment, arrivals)
        await draw(store, "other-chapter")
        await store.receive(\.draftsSaved)
        let edited = DraftVerse(chapter: CanvasTestSupport.chapter, verse: 2)
        let editedBase = try #require(store.state.drafts.bases[edited])

        let next = BibleChapter(title: .jonah, chapter: 3)
        // 다음 장 1절에는 확인 전(힌트 A)에 쓴 보이기만 하는 초안이 겹쳐 보인다.
        var shown = previousDraft(verse: 1, ink: "shown-only", account: .unverified(hint: accountA))
        shown.key = VerseDraftKey(sessionID: shown.key.sessionID, chapter: next, verse: 1)
        drafts.seed(shown)
        spy.snapshots = { chapter in chapter == next ? [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA)] : [] }
        await store.send(.load(chapter: next, expectedVerseCount: 3))
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout))
        let shownPlace = DraftVerse(chapter: next, verse: 1)
        let adopted = try #require(store.state.drafts.adopted[shownPlace])
        let inherited = try #require(store.state.drafts.inherited[shownPlace])

        // 이 장은 초안이 겹쳐 보여 자동으로 바꾸지 않는다 — 확인 조회만 하고 기준 · 이어받기 · 출처를 건드리지 않는다.
        spy.snapshots = { chapter in
            chapter == next
                ? [CanvasTestSupport.snapshot(verse: 1, rowID: CanvasTestSupport.rowA),
                   VerseDrawingSnapshot(verse: 3, rowID: BibleDrawingRowID(raw: "row-remote"), isPresent: true, updateDate: nil,
                                        lineData: Data([5]), drawingVersion: 1, metadata: nil)]
                : []
        }
        arrivals.arrive()
        await store.receive(\.importArrived)
        await store.receive(\.arrivalChecked)
        #expect(store.state.arrival.notice == .arrived)
        #expect(store.state.drafts.bases[edited] == editedBase)
        #expect(store.state.drafts.adopted[shownPlace] == adopted)
        #expect(store.state.drafts.inherited[shownPlace] == inherited)
        await close(store, environment, arrivals)
    }
}
