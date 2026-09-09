//
//  ChapterCanvasEraseFeature.swift
//  CarveFeature
//
//  Created by Claude on 9/9/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  UI-2 — 절 롱탭 메뉴의 "지우기"(보관 후 초기화). `ChapterCanvasFeature` 의 일부이지만,
//  일반 획 저장(§8-3 큐)과 **다른 경로**라는 것이 이 기능의 요점이라 파일을 나눠 둔다.
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 진행 중인 "지우기"(보관 후 초기화) 작업 (UI-2).
///
/// **일반 획 저장 큐(`pendingMutations`)를 쓰지 않는다.** 그 큐는 rowID 당 한 칸이고 `coalesce` 의 `default` 가
/// 나중 명령을 택하므로, 보관 명령을 넣으면 이어진 획 하나에 덮여 사라진다 (§8-3). 대신 이 작업이 큐와
/// **순서를 맞춘다** — flush 로 큐를 비운 뒤(`flushing`) 보관 트랜잭션을 돌리고(`archiving`), 그동안 입력을 잠근다.
struct VerseEraseTask: Equatable, Sendable {
    let verse: Int
    /// 이 작업이 속한 장. 장이 바뀌면 활성 행 문맥이 사라지므로 접는다.
    let chapter: BibleChapter
    /// 이 작업이 **한 번만** 발급한 보관 행 rowID. 재시도에도 같은 값을 써서 보관 행이 늘지 않게 한다.
    let archiveRowID: BibleDrawingRowID
    var phase: Phase

    enum Phase: Equatable, Sendable {
        /// 미저장분·진행 중 편집을 정리하는 중 (§8-5 flush). DB 가 "방금까지 쓴 내용" 이 되어야 그것을 보관한다.
        case flushing
        /// 보관+초기화 트랜잭션이 도는 중.
        case archiving
        /// 실패했다. **잠금은 풀고**(원래 필기 유지) 재시도 안내만 띄운 상태 — `archiveRowID` 는 재시도용으로 남는다.
        case failed
    }
}

// MARK: - 지우기 = 보관 후 초기화 (UI-2)

/// 지우기는 **삭제가 아니다.** 현재 필사를 보관 행으로 남기고 활성 행만 비운다. 아무것도 지우지 않는다.
///
/// ```
/// 롱프레스 메뉴 "지우기" → 확인창(권·장·절)
///   → flushing:  미저장분·진행 중 편집을 먼저 저장한다 (§8-5). 이때부터 입력이 잠긴다
///   → archiving: repository.archiveAndReset — 보관 행 생성 + 활성 행 비움을 한 트랜잭션으로
///   → 재합성:    DB 에서 다시 합성해 캔버스를 갱신한다
/// 실패 → 잠금 해제 + 필기 유지 + 재시도 안내 (보관 rowID 는 재사용)
/// ```
///
/// **저장 큐를 쓰지 않는 이유 (§8-3).** `pendingMutations` 는 rowID 당 한 칸이고 `coalesce` 의 `default` 가 나중
/// 명령을 택한다. 보관 명령을 거기 넣으면 이어진 획 하나에 덮여 사라진다. 그래서 별도 작업으로 두고, 대신 큐와
/// **순서를 맞춘다** — 큐가 빈 뒤에만(`isFullyPersisted`) 보관을 시작하고, 보관 중에는 저장·재조회를 시작하지 않는다.
///
/// **대표 행 보장 (§8-7).** 저장소의 `.clear` 는 기존 행의 `isPresent` 를 바꾸지 않으므로 대표 규칙만으로는
/// 보관 행이 다시 대표가 될 수 있다. `archiveAndReset` 이 보관 행 `isPresent = false` · 빈 활성 행 `isPresent = true` 를
/// 직접 기록해 그것을 막는다.
///
/// **undo 는 이 장 전체가 초기화된다 (§9-5).** 캔버스는 장 하나를 한 `PKDrawing` 으로 들고 있고, 한 절의 획만
/// 빼려면 재합성밖에 없다. 재합성은 `renderedRevision` 을 올려 `ChapterCanvasController` 가 undo 스택을 비운다.
/// **의도한 결과다** — 지우기를 undo 로 되돌리면 획이 비워진 활성 행에 다시 저장되어, 보관본과 활성 내용이
/// 동시에 존재하는 상태가 된다. 지우기의 되돌리기는 "이전 필사 내용 보기" 에서 보관본을 고르는 것이다.
/// 확인창에도 그렇게 적는다 — 조용히 날리지 않는다. 다만 **보관할 것이 없었을 때는 재합성하지 않으므로**
/// undo 스택도 그대로 남는다.
extension ChapterCanvasFeature {
    /// 확인창을 거친 지우기의 시작. 보관 rowID 를 **여기서 한 번만** 발급한다.
    func beginErase(state: inout State, verse: Int) -> Effect<Action> {
        guard state.isComposed, state.eraseTask == nil else { return .none }
        state.eraseTask = VerseEraseTask(
            verse: verse,
            chapter: state.chapter,
            archiveRowID: BibleDrawingRowID(raw: uuid().uuidString),
            phase: .flushing
        )
        // 큐가 이미 비어 있으면 `settleIfNeeded` 가 곧바로 보관으로 넘어간다.
        return startSaveIfPossible(state: &state, allowRetry: true)
    }

    /// 실패한 지우기를 **같은 보관 rowID** 로 다시 시도한다 — 재시도가 보관 행을 늘리지 않는 지점이다.
    func retryErase(state: inout State) -> Effect<Action> {
        guard var task = state.eraseTask, task.phase == .failed else { return .none }
        task.phase = .flushing
        state.eraseTask = task
        return startSaveIfPossible(state: &state, allowRetry: true)
    }

    /// flush 가 끝난 뒤의 보관 트랜잭션.
    func startArchive(state: inout State) -> Effect<Action> {
        guard var task = state.eraseTask, task.phase == .flushing else { return .none }
        guard task.chapter == state.chapter else {
            // 장이 바뀌었다 — 이 작업의 활성 행 문맥이 없다. 조용히 접는다 (장 전환은 `beginLoad` 에서도 접는다).
            state.eraseTask = nil
            return .none
        }
        task.phase = .archiving
        state.eraseTask = task

        guard let activeRowID = state.activeRowIDs[task.verse] else {
            // 그 절에는 행이 하나도 없다 — 보관할 것도, 비울 것도 없다. flush 를 마친 뒤의 판정이므로 미저장 획도 없다.
            return .send(.eraseFinished(outcome: .alreadyEmpty, failure: nil))
        }
        let command = VerseDrawingArchiveCommand(
            verse: task.verse, activeRowID: activeRowID, archiveRowID: task.archiveRowID
        )
        let chapter = task.chapter
        return .run { [repository] send in
            do {
                let outcome = try await repository.archiveAndReset(command, chapter: chapter)
                await send(.eraseFinished(outcome: outcome, failure: nil))
            } catch let error as DrawingRepositoryError {
                await send(.eraseFinished(outcome: nil, failure: error))
            } catch {
                await send(.eraseFinished(outcome: nil, failure: .persistenceFailed("\(error)")))
            }
        }
    }

    func finishErase(
        state: inout State,
        outcome: VerseDrawingArchiveOutcome?,
        failure: DrawingRepositoryError?
    ) -> Effect<Action> {
        guard state.eraseTask?.phase == .archiving else { return .none }
        if let failure {
            Log.error("단일 Canvas 지우기 실패 — 필기를 그대로 두고 재시도 안내", "\(failure)")
            return failErase(state: &state)
        }
        let task = state.eraseTask
        state.eraseTask = nil
        guard outcome == .archived else {
            // 이미 비어 있었다. 화면 내용이 달라지지 않으므로 재합성하지 않는다 — 이 장의 undo 스택도 건드리지 않는다 (§9-5).
            Log.debug("단일 Canvas 지우기 — 이미 비어 있어 보관본을 만들지 않았다", "verse=\(task?.verse ?? -1)")
            return settleIfNeeded(state: &state)
        }
        // 캔버스를 DB 에서 다시 합성한다. 이 장의 undo 스택이 비워지는 것은 의도한 결과다 (위 확장 주석).
        return reloadAfterSettling(state: &state)
    }

    /// 실패 처리 — **잠금을 풀고**(`.failed` 는 `isErasing` 이 아니다) 원래 필기를 유지한 채 재시도를 안내한다.
    /// 보관 rowID 는 작업에 남겨 두어 재시도가 같은 값을 쓴다.
    func failErase(state: inout State) -> Effect<Action> {
        guard var task = state.eraseTask else { return .none }
        task.phase = .failed
        state.eraseTask = task
        state.eraseAlert = Self.eraseFailureAlert(chapter: task.chapter, verse: task.verse)
        return .none
    }

    /// 확인창. 권·장·절을 함께 보여 주고, 이 장의 undo 가 초기화된다는 것도 함께 알린다 (§9-5 — 조용히 날리지 않는다).
    static func confirmEraseAlert(chapter: BibleChapter, verse: Int) -> AlertState<Action.EraseAlert> {
        AlertState {
            TextState("\(chapter.title.koreanTitle()) \(chapter.chapter)장 \(verse)절 필사 지우기")
        } actions: {
            ButtonState(role: .cancel) { TextState("취소") }
            ButtonState(action: .confirm(verse: verse)) { TextState("지우기") }
        } message: {
            TextState("""
            이 절의 필사를 지울까요? 현재 필사는 이전 필사 기록에 남습니다.
            이 장의 되돌리기 기록은 초기화됩니다.
            """)
        }
    }

    static func eraseFailureAlert(chapter: BibleChapter, verse: Int) -> AlertState<Action.EraseAlert> {
        AlertState {
            TextState("필사를 지우지 못했습니다")
        } actions: {
            ButtonState(role: .cancel) { TextState("닫기") }
            ButtonState(action: .retry) { TextState("다시 시도") }
        } message: {
            TextState("\(chapter.title.koreanTitle()) \(chapter.chapter)장 \(verse)절의 필사는 그대로 있습니다. 다시 시도해 주세요.")
        }
    }
}
