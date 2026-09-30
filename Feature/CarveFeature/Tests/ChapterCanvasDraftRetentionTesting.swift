//
//  ChapterCanvasDraftRetentionTesting.swift
//  CarveFeatureTest
//
//  절 초안의 보존 — 로컬 저장만으로 지우지 않고, 읽지 못하면 그 위에 새 초안을 덮지 않는다 (정책 §12-6 구현 순서 ②, ACC-1 F29).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 저장소(`BibleDrawing`) 저장만으로 마지막 로컬 사본인 초안을 지우는 것 — 전송 전에 계정이 바뀌면 미러링이 그 행을 지우고
///   원래 계정으로 돌아와도 되살리지 않는다(ACC-1 F29)
/// - 역할이 끝난 초안(저장소에 넣은 revision)을 다시 겹쳐 그 뒤 들어온 저장소 내용을 가리는 것
/// - 저장소에 넣은 초안이, 그 절을 지우기 · 복원으로 되돌린 뒤 다른 세션에서 기준이 같다는 이유로 되살아나는 것(A → B → A)
/// - 초안을 읽지 못했는데 저장소 내용만으로 열어, 보이지 않던 초안을 같은 키 · 더 새 revision 으로 덮는 것
@Suite("절 초안 — 로컬 저장은 보존이 아니다")
@MainActor
struct ChapterCanvasDraftRetentionTesting: DraftTestSamples {
    @Test("저장소 저장을 마친 이 세션의 초안은 다시 읽어도 겹치지 않는다 — 그 뒤 저장소 내용을 가리지 않되, 초안은 남긴다")
    func storedOwnDraftIsNotOverlaidButKept() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let inputs = LockIsolated<[[VerseDrawingSnapshot]]>([])
        let store = makeStore(
            spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts, composeInputs: inputs
        )
        await composeAndSubscribe(store, environment)
        await draw(store)
        await store.receive(\.saveFinished)

        // 저장소 대역은 저장을 반영하지 않는다 — 다시 읽으면 그 행이 없다(원격 덮어쓰기 · 전송 전 계정 전환과 같은 모습).
        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout))
        await store.receive(\.drawingsLoaded)

        let last = try #require(inputs.value.last)
        #expect(!last.contains { $0.verse == 2 })
        #expect(drafts.stored(in: accountA).map(\.lineData) == [Data("create-a".utf8)])
        #expect(drafts.removed.value.isEmpty)
        await end(store, environment)
    }

    /// ACC-1 시나리오 3 을 단위로 옮긴 것 — 저장은 됐지만 전송 전에 계정이 A → B → A 로 바뀌어 그 행이 지워졌다(F29).
    /// 저장소에 넣었던 행이 사라진 것은 다른 기기의 삭제와도 구분되지 않는다 — 되살릴 수 있게 보이되, 다시 올릴지는 사용자가 정한다(④).
    @Test("계정이 A → B → A 로 돌아왔을 때 저장소에서 그 행이 사라졌으면 남은 초안을 다시 보인다 — 보이기만 하고 저장소에 다시 올리지 않는다")
    func draftSurvivesAccountRoundTrip() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        await draw(store)
        await store.receive(\.saveFinished)
        // 저장소 저장과 초안 저장을 둘 다 마치면 초안에 표식이 남는다.
        while drafts.stored(in: accountA).first?.storeState != .stored { await Task.yield() }

        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)
        // B 세션에는 A 의 초안이 보이지 않는다.
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 } == false)

        environment.change(to: confirmed(accountA, 3))
        await store.receive(\.editEnvironmentChanged)
        await store.receive(\.drawingsLoaded)

        // 저장소에 넣었던 행이 사라졌다 — 되살릴 수 있게 보이되, 근거가 A 의 소유 근거여도 이어 쓰지 않고 보이기만 한다.
        let place = DraftVerse(chapter: CanvasTestSupport.chapter, verse: 2)
        let kept = try #require(drafts.stored(in: accountA).first)
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 && $0.lineData == Data("create-a".utf8) } == true)
        #expect(store.state.drafts.adopted[place] == kept.ref)
        #expect(store.state.drafts.inherited[place] == kept.provenance)
        #expect(!store.state.writesStore(verse: 2))
        #expect(drafts.stored(in: accountA).count == 1)
        await end(store, environment)
    }

    /// 기준 지문만 보면 "빈 절에 X 를 썼다 → 지웠다(빈 절)" 가 "빈 절 기준의 X 초안" 과 구분되지 않는다. 저장소에 넣은 초안의 표식으로 가린다.
    @Test("저장소에 넣은 초안은 그 절을 지운 뒤 다른 세션이 불러와도 되살아나지 않는다 — 초안은 남는다")
    func storedDraftDoesNotResurrectAfterErase() async throws {
        let spy = RepositorySpy()
        let drafts = RecordingDraftStore()
        let firstEnvironment = ControlledEditEnvironment(confirmed(accountA, 1))
        let first = makeStore(spy: spy, results: [CanvasTestSupport.createResult("x")], environment: firstEnvironment, drafts: drafts)
        await composeAndSubscribe(first, firstEnvironment)
        await draw(first, "x")
        await first.receive(\.saveFinished)
        await end(first, firstEnvironment)
        #expect(drafts.stored(in: accountA).first?.storeState == .stored)

        // 다시 실행한 앱에서 그 절을 지웠다 — 활성 행은 비고 보관 행이 X 를 든다.
        spy.snapshots = { _ in [
            VerseDrawingSnapshot(verse: 2, rowID: CanvasTestSupport.newRow, isPresent: true, updateDate: Date(timeIntervalSince1970: 2_000),
                                 lineData: nil, drawingVersion: 3, metadata: nil),
            VerseDrawingSnapshot(verse: 2, rowID: BibleDrawingRowID(raw: "archive"), isPresent: false,
                                 updateDate: Date(timeIntervalSince1970: 1_500), lineData: Data("create-x".utf8), drawingVersion: 3,
                                 metadata: CanvasTestSupport.metadata())
        ] }
        let secondEnvironment = ControlledEditEnvironment(confirmed(accountA, 2))
        let second = makeStore(spy: spy, results: [], environment: secondEnvironment, drafts: drafts)
        await composeAndSubscribe(second, secondEnvironment)

        let place = DraftVerse(chapter: CanvasTestSupport.chapter, verse: 2)
        #expect(second.state.drafts.adopted[place] == nil)
        #expect(second.state.loadedDrawings?.first { $0.rowID == CanvasTestSupport.newRow }?.lineData == nil)
        #expect(drafts.stored(in: accountA).count == 1)
        await end(second, secondEnvironment)
    }

    /// 같은 세션의 재조회 실패는 마지막으로 알던 내용으로 이미 복구했다. 그 실패가 세션을 새로 연 뒤의 다시 읽기를 막는 실패로 되살아나면 안 된다.
    @Test("합성된 장에 남은 재조회 실패는 세션을 새로 열 때 비운다 — 새 세션의 다시 읽기 동안 막힘 안내를 띄우지 않는다")
    func staleReloadFailureIsClearedOnSessionClose() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1))
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: RecordingDraftStore())
        await composeAndSubscribe(store, environment)
        spy.loadFailures.setValue(["offline"])
        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout))
        await store.receive(\.drawingsLoaded)
        #expect(store.state.loadFailure != nil)
        #expect(store.state.blockingLoadFailure == nil)
        #expect(store.state.isInputEnabled)

        spy.holdNextLoadCall()
        environment.change(to: confirmed(accountB, 2))
        await store.receive(\.editEnvironmentChanged)
        #expect(store.state.loadedDrawings == nil)
        #expect(store.state.blockingLoadFailure == nil)

        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)
        #expect(store.state.isInputEnabled)
        await end(store, environment)
    }

    @Test("초안을 읽은 삭제 세대가 조회 환경과 다르면 열지 않고 막으며, 다시 시도해 세대가 맞으면 연다")
    func draftGenerationMismatchBlocksLoad() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        drafts.generation.setValue(1)
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: drafts)

        await store.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3))
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
        while environment.subscriberCount == 0 { await Task.yield() }
        #expect(store.state.blockingLoadFailure?.source == .drafts)
        #expect(!store.state.isComposed)

        drafts.generation.setValue(0)
        await store.send(.retryLoad)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.isInputEnabled)
        await end(store, environment)
    }

    // MARK: - 초안을 읽지 못함

    @Test("처음 불러올 때 초안을 읽지 못하면 합성하지 않고 입력을 막은 채 안내를 띄우며, 다시 시도가 성공한 뒤에만 연다")
    func draftReadFailureBlocksFirstLoad() async throws {
        let spy = spyWithVerseOne()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        let earlier = previousDraft()
        drafts.seed(earlier)
        drafts.readFailures.setValue(1)
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: drafts)

        await store.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3))
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
        while environment.subscriberCount == 0 { await Task.yield() }

        let failure = try #require(store.state.blockingLoadFailure)
        #expect(failure.source == .drafts)
        #expect(LoadFailureNoticeView.message(for: failure) == LoadFailureNoticeView.draftsMessage)
        #expect(!store.state.isComposed)
        #expect(!ChapterCanvasView.Display(store.state).isInputEnabled)

        await store.send(.retryLoad)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.blockingLoadFailure == nil)
        #expect(store.state.isInputEnabled)
        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("earlier".utf8))
        #expect(drafts.saves.value.isEmpty)
        #expect(drafts.stored(in: accountA) == [earlier])
        await end(store, environment)
    }

    /// 재조회 실패는 마지막으로 알던 내용으로 합성해 입력을 여는 출구가 있다. 초안을 읽지 못한 것은 그 출구를 쓰지 않는다 — 보이지 않는 초안이
    /// 있는지 알 수 없다.
    @Test("다시 읽을 때 초안을 읽지 못하면 합성된 장이어도 마지막으로 알던 내용으로 열지 않고, 막은 채 다시 시도를 기다린다")
    func draftReadFailureBlocksReload() async throws {
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
        let composedBefore = inputs.value.count

        drafts.readFailures.setValue(1)
        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout))
        await store.receive(\.drawingsLoaded)

        #expect(store.state.isComposed)
        #expect(store.state.blockingLoadFailure?.source == .drafts)
        #expect(!store.state.isInputEnabled)
        // 새 레이아웃으로 다시 합성하지 않았다 — 마지막으로 알던 내용으로 여는 출구를 쓰지 않았다.
        #expect(inputs.value.count == composedBefore)
        #expect(store.state.renderedLayout == CanvasTestSupport.layout)

        await store.send(.retryLoad)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.isInputEnabled)
        #expect(store.state.renderedLayout == CanvasTestSupport.otherLayout)
        let last = try #require(inputs.value.last)
        #expect(last.contains { $0.verse == 2 && $0.lineData == Data("create-a".utf8) })
        #expect(drafts.saves.value.count == 1)
        await end(store, environment)
    }

    /// 한 세션은 장을 오가도 같다 — 그 장에 남긴 이 세션의 초안은 다시 불러와야 보인다. 읽지 못한 채 열면 같은 키(세션 · 절)의 새 초안이
    /// 보이지 않던 초안을 덮는다. 초안 전용 세션에서는 그것이 유일한 사본이다.
    @Test("장을 떠났다 돌아올 때 초안을 읽지 못하면 그 장의 초안을 덮지 않고, 다시 시도가 성공하면 그 초안을 보인다")
    func draftReadFailureOnRevisitDoesNotOverwrite() async throws {
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let drafts = RecordingDraftStore()
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: drafts)
        await composeAndSubscribe(store, environment)
        await draw(store)
        await store.receive(\.draftsSaved)

        let next = BibleChapter(title: .jonah, chapter: 3)
        await store.send(.load(chapter: next, expectedVerseCount: 3))
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))
        #expect(store.state.isInputEnabled)

        drafts.readFailures.setValue(1)
        await store.send(.load(chapter: CanvasTestSupport.chapter, expectedVerseCount: 3))
        await store.receive(\.drawingsLoaded)
        await store.send(.layoutCompleted(CanvasTestSupport.layout))

        #expect(!store.state.isInputEnabled)
        #expect(store.state.blockingLoadFailure?.source == .drafts)
        #expect(drafts.saves.value.count == 1)

        await store.send(.retryLoad)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.isInputEnabled)
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 && $0.lineData == Data("create-a".utf8) } == true)
        #expect(drafts.saves.value.count == 1)
        await end(store, environment)
    }
}
