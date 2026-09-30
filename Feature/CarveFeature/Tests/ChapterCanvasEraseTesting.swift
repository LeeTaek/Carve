//
//  ChapterCanvasEraseTesting.swift
//  CarveFeatureTest
//
//  UI-2 — 절 롱탭 메뉴의 "지우기"(보관 후 초기화). 스텁·지원 타입은 ChapterCanvasFeatureTesting.swift 의 것을 쓴다.
//
//  고정하는 성질
//  1. 확인창에 권·장·절이 있고, 확인해야만 시작한다
//  2. **flush 가 먼저 돈다** — 저장 직전 획까지 DB 에 들어간 뒤에 보관한다 (설계 §8-5)
//  3. 보관은 저장 큐(§8-3)를 거치지 않는다 — 큐는 rowID 당 한 칸이라 넣으면 다음 획에 덮인다
//  4. 실패·재시도에서 **같은 보관 rowID** 를 쓴다 (보관 행이 늘지 않는다)
//  5. 진행 중에는 입력·중복 지우기가 막히고, 실패하면 잠금이 풀린다
//  6. 보관했을 때만 다시 합성한다 (재합성 = 이 장의 undo 초기화, §9-5)
//

import CoreGraphics
import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

@Suite("UI-2 — ChapterCanvasFeature · 지우기 (보관 후 초기화)")
@MainActor
struct ChapterCanvasEraseTesting {
    /// `CanvasTestSupport.composed(_:tag:)` 가 활성 행을 주는 절 (`activeRowIDs = [1: rowA]`).
    private static let verse = 1
    /// 절 1 의 필사 영역 안 (uniformLayout: v1 = y [0, 30)).
    private static let pointInVerse = CGPoint(x: 10, y: 15)
    /// `.incrementing` uuid 에서 load 가 UUID(0) 을 쓰므로 지우기가 발급하는 보관 rowID 는 UUID(1) 이다.
    private static let expectedArchiveRowID = BibleDrawingRowID(raw: UUID(1).uuidString)

    // MARK: 확인창

    @Test("롱탭 메뉴의 지우기는 권·장·절이 담긴 확인창을 띄우고, 확인해야만 보관을 시작한다")
    func requestPresentsConfirmationWithReference() async throws {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy)
        await CanvasTestSupport.compose(store)

        await store.send(.eraseRequested(at: Self.pointInVerse))
        let alert = try #require(store.state.eraseAlert)
        let title = String(state: alert.title)
        #expect(title.contains(CanvasTestSupport.chapter.title.koreanTitle()))
        #expect(title.contains("\(CanvasTestSupport.chapter.chapter)장"))
        #expect(title.contains("\(Self.verse)절"))
        let message = String(state: try #require(alert.message))
        #expect(message.contains("이 절의 필사를 지울까요? 현재 필사는 이전 필사 기록에 남습니다."))
        // 재렌더가 이 장의 undo 를 비우는 것을 조용히 넘기지 않는다 (§9-5).
        #expect(message.contains("되돌리기"))
        // 확인 전에는 아무것도 하지 않는다.
        #expect(spy.archived.value.isEmpty)
        #expect(store.state.eraseTask == nil)

        // 취소(확인창 닫힘)도 아무것도 하지 않는다.
        await store.send(.eraseAlert(.dismiss))
        #expect(spy.archived.value.isEmpty)

        // 캔버스 밖(세로로 벗어난 자리)은 확인창을 띄우지 않는다.
        await store.send(.eraseRequested(at: CGPoint(x: 10, y: 5_000)))
        #expect(store.state.eraseAlert == nil)
    }

    // MARK: flush 우선 (§8-5)

    @Test("저장 직전 획까지 저장한 뒤에 보관한다 — flush 로 막 생긴 활성 행을 보관 대상으로 삼는다")
    func flushRunsBeforeArchive() async throws {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(
            spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")])
        )
        await CanvasTestSupport.compose(store)

        // 절 2 는 DB 에 행이 없다. 방금 그은 획이 아직 저장 중이고, 그 저장이 이 절의 행을 처음 만든다.
        spy.holdNextApply()
        await store.send(.editEnded(CanvasTestSupport.edit("1")))
        await store.receive(\.mutationsPrepared)
        #expect(store.state.activeRowIDs[2] == CanvasTestSupport.newRow)

        // 그 절을 지운다 — 보관 대상은 "DB 에 있던 내용" 이 아니라 "방금까지 쓴 내용" 이어야 한다.
        await store.send(.eraseRequested(at: CGPoint(x: 10, y: 45)))
        await store.send(.eraseAlert(.presented(.confirm(verse: 2))))

        // 저장이 끝나기 전에는 보관하지 않는다 — 지금 보관하면 이 획이 빠진 내용을 보관하게 된다.
        #expect(spy.archived.value.isEmpty)
        #expect(store.state.eraseTask?.phase == .flushing)
        #expect(!store.state.isInputEnabled)

        spy.releaseApply()
        await store.receive(\.saveFinished)
        await store.receive(\.eraseFinished)
        await store.receive(\.drawingsLoaded)

        // 획 저장이 먼저 끝났고, 그 뒤에 그 획이 들어간 행을 보관했다.
        #expect(spy.applied.value.count == 1)
        #expect(spy.applied.value[0].mutations == [
            .create(verse: 2, rowID: CanvasTestSupport.newRow,
                    data: Data("create-1".utf8), metadata: CanvasTestSupport.metadata())
        ])
        #expect(spy.archived.value.count == 1)
        #expect(spy.archived.value[0].command.verse == 2)
        #expect(spy.archived.value[0].command.activeRowID == CanvasTestSupport.newRow)
        #expect(spy.archived.value[0].chapter == CanvasTestSupport.chapter)
    }

    // MARK: 저장 큐를 거치지 않는다 (§8-3)

    @Test("보관 명령은 저장 큐에 들어가지 않는다 — 보관 중 도착한 편집이 보관을 덮지 않는다")
    func archiveDoesNotGoThroughTheMutationQueue() async throws {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(
            spy: spy, results: LockIsolated([CanvasTestSupport.replaceResult("late", rowID: CanvasTestSupport.rowA)])
        )
        await CanvasTestSupport.compose(store)

        spy.holdNextArchiveCall()
        await store.send(.eraseRequested(at: Self.pointInVerse))
        await store.send(.eraseAlert(.presented(.confirm(verse: Self.verse))))
        #expect(store.state.eraseTask?.phase == .archiving)

        // 보관 트랜잭션이 도는 사이 늦게 도착한 편집. 받아들이면 그 절의 획을 활성 행에 다시 써 지우기를 되돌린다.
        await store.send(.editEnded(CanvasTestSupport.edit("late")))
        #expect(store.state.editQueue.isEmpty)
        #expect(store.state.pendingMutations.isEmpty)

        spy.releaseArchive()
        await store.receive(\.eraseFinished)
        await store.receive(\.drawingsLoaded)

        // 보관은 `apply` 가 아니라 `archiveAndReset` 으로만 갔고, 저장 큐에는 아무것도 남지 않았다.
        #expect(spy.applied.value.isEmpty)
        #expect(spy.archived.value.count == 1)
        #expect(store.state.pendingMutations.isEmpty)
    }

    // MARK: 실패와 재시도

    @Test("실패하면 잠금을 풀고 필기를 그대로 둔 채 재시도를 안내하며, 재시도는 같은 보관 rowID 를 쓴다")
    func failureUnlocksAndRetryReusesArchiveRowID() async throws {
        let spy = RepositorySpy()
        spy.archiveFailures.withValue { $0 = [.persistenceFailed("boom")] }
        let store = CanvasTestSupport.makeStore(spy: spy)
        await CanvasTestSupport.compose(store)
        let composedData = store.state.renderedData

        await store.send(.eraseRequested(at: Self.pointInVerse))
        await store.send(.eraseAlert(.presented(.confirm(verse: Self.verse))))
        await store.receive(\.eraseFinished)

        // 잠금 해제 — 필기는 화면에 그대로 있고 다시 그릴 수 있다.
        #expect(!store.state.isErasing)
        #expect(store.state.isInputEnabled)
        #expect(store.state.renderedData == composedData)
        #expect(store.state.eraseTask?.phase == .failed)
        let failureAlert = try #require(store.state.eraseAlert)
        #expect(String(state: failureAlert.title).contains("지우지 못했습니다"))
        // 실패한 보관은 다시 합성하지 않는다 — 조회는 최초 1회뿐이다.
        #expect(spy.loadedChapters.value.count == 1)

        await store.send(.eraseAlert(.presented(.retry)))
        await store.receive(\.eraseFinished)
        await store.receive(\.drawingsLoaded)

        #expect(spy.archived.value.count == 2)
        let rowIDs = spy.archived.value.map(\.command.archiveRowID)
        #expect(rowIDs[0] == Self.expectedArchiveRowID)
        // 여기가 핵심 — 재시도가 새 rowID 를 발급하면 보관 행이 둘로 늘어난다.
        #expect(rowIDs[0] == rowIDs[1])
        #expect(store.state.eraseTask == nil)
    }

    @Test("실패 안내를 닫으면 작업이 끝난다 — 다음 지우기는 새로 시작한다")
    func dismissingFailureAlertEndsTheTask() async throws {
        let spy = RepositorySpy()
        spy.archiveFailures.withValue { $0 = [.persistenceFailed("boom")] }
        let store = CanvasTestSupport.makeStore(spy: spy)
        await CanvasTestSupport.compose(store)

        await store.send(.eraseRequested(at: Self.pointInVerse))
        await store.send(.eraseAlert(.presented(.confirm(verse: Self.verse))))
        await store.receive(\.eraseFinished)
        #expect(store.state.eraseTask?.phase == .failed)

        await store.send(.eraseAlert(.dismiss))
        #expect(store.state.eraseTask == nil)
        // 새 지우기는 다시 확인창부터 시작한다.
        await store.send(.eraseRequested(at: Self.pointInVerse))
        #expect(store.state.eraseAlert != nil)
    }

    // MARK: 잠금 · 중복 방지 · 장 전환

    @Test("진행 중에는 입력이 잠기고 중복 지우기·히스토리 시트가 열리지 않으며, 장을 바꾸면 작업을 접는다")
    func inFlightEraseLocksInputAndIsCancelledByChapterChange() async throws {
        let spy = RepositorySpy()
        let store = CanvasTestSupport.makeStore(spy: spy)
        await CanvasTestSupport.compose(store)

        spy.holdNextArchiveCall()
        await store.send(.eraseRequested(at: Self.pointInVerse))
        await store.send(.eraseAlert(.presented(.confirm(verse: Self.verse))))

        #expect(store.state.isErasing)
        #expect(!store.state.isInputEnabled)
        #expect(!store.state.isDrawingInputEnabled)
        // 중복 지우기 요청은 확인창을 다시 띄우지 않는다.
        await store.send(.eraseRequested(at: Self.pointInVerse))
        #expect(store.state.eraseAlert == nil)
        // 히스토리 시트도 열리지 않는다 (같은 입력 게이트).
        await store.send(.historyRequested(at: Self.pointInVerse))

        spy.releaseArchive()
        await store.receive(\.eraseFinished)
        await store.receive(\.drawingsLoaded)
        #expect(store.state.isInputEnabled)

        // 장 전환은 진행 중 작업과 안내를 이월하지 않는다 (§14 이월 상태 감사).
        spy.archiveFailures.withValue { $0 = [.persistenceFailed("boom")] }
        await store.send(.eraseRequested(at: Self.pointInVerse))
        await store.send(.eraseAlert(.presented(.confirm(verse: Self.verse))))
        await store.receive(\.eraseFinished)
        #expect(store.state.eraseTask?.phase == .failed)

        await store.send(.load(chapter: BibleChapter(title: .jonah, chapter: 3), expectedVerseCount: 3))
        #expect(store.state.eraseTask == nil)
        #expect(store.state.eraseAlert == nil)
        await store.receive(\.drawingsLoaded)
    }

    // MARK: 재합성 = undo 초기화 (§9-5)

    @Test("보관했을 때만 다시 합성한다 — 이미 비어 있으면 재합성도 undo 초기화도 없다")
    func recomposesOnlyWhenSomethingWasArchived() async throws {
        let spy = RepositorySpy()
        spy.archiveOutcomes.withValue { $0 = [.alreadyEmpty] }
        let store = CanvasTestSupport.makeStore(spy: spy)
        await CanvasTestSupport.compose(store)
        let revisionBeforeEmptyErase = store.state.renderedRevision

        await store.send(.eraseRequested(at: Self.pointInVerse))
        await store.send(.eraseAlert(.presented(.confirm(verse: Self.verse))))
        await store.receive(\.eraseFinished)

        // 화면 내용이 달라지지 않았으므로 세대를 올리지 않는다 → 컨트롤러가 undo 스택을 비우지 않는다.
        #expect(store.state.renderedRevision == revisionBeforeEmptyErase)
        #expect(spy.loadedChapters.value.count == 1)
        #expect(store.state.eraseTask == nil)

        // 보관한 경우에는 다시 합성한다 — 그 절의 획만 빼는 부분 갱신 경로가 없기 때문이다.
        await store.send(.eraseRequested(at: Self.pointInVerse))
        await store.send(.eraseAlert(.presented(.confirm(verse: Self.verse))))
        await store.receive(\.eraseFinished)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.renderedRevision > revisionBeforeEmptyErase)
        #expect(spy.loadedChapters.value.count == 2)
        #expect(!store.state.isReloading)
    }
}
