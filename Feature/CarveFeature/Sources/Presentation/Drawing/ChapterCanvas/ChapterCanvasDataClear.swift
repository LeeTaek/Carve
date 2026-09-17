//
//  ChapterCanvasDataClear.swift
//  CarveFeature
//
//  설정의 「모든 필사 데이터 삭제」 뒤처리. 일반 저장 경로(§8-3 큐)를 **버리는** 유일한 자리라
//  지우기(`ChapterCanvasEraseFeature`)와 같은 이유로 파일을 나눠 둔다.
//

import Foundation

import ComposableArchitecture

extension ChapterCanvasFeature {
    /// 밖에서 필사 데이터가 전부 지워졌을 때의 정리 (설정 → 「모든 필사 데이터 삭제」).
    ///
    /// **미저장분과 진행 중인 편집을 버린다.** 이 명령들이 가리키는 행은 DB 에서 사라졌고, 그대로 두면
    /// 다음 저장이 방금 지운 잉크를 새 행으로 되살린다 (`create` 는 upsert, §8-6). 화면도 옛 잉크를 들고 있으므로
    /// 그 상태에서 획을 하나 더 그으면 **캔버스에 남아 있던 획 전체가** 다시 저장된다 (§8-2 는 절별 완전한 집합을 쓴다).
    ///
    /// 레이아웃은 그대로 두고 DB 에서 다시 합성하기만 한다 — 본문은 지워지지 않았으므로 다시 잴 것이 없다.
    /// 다시 읽기가 실패하면 합성하지 않고 입력을 닫아 둔다. 화면은 안내와 「다시 시도」(`retryLoad`)를 띄운다.
    ///
    /// **들어오는 길이 셋이다.** 설정의 삭제 알림(`drawingDataCleared`), 저장소가 세대로 거절한 저장(`staleStoreGeneration`),
    /// 기준과 다른 세대의 조회 결과. 뒤의 둘은 알림보다 먼저 올 수 있고, 알림이 뒤따라 와도 같은 정리를 한 번 더 할 뿐이다.
    /// 이미 요청돼 도는 저장은 멈출 수 없다 — 그 저장이 삭제 뒤에 실행되면 저장소가 세대로 거절한다 (`DrawingStoreGeneration`).
    func clearAfterExternalDelete(state: inout State) -> Effect<Action> {
        state.pendingMutations = [:]
        state.inFlightBatch = [:]
        state.inFlightMutations = []
        state.inFlightChapter = nil
        state.editQueue = []
        state.isPreparingEdit = false
        state.saveStatus = .idle
        state.consecutiveSaveFailures = 0
        // `editRevision` 자체는 되돌리지 않는다 — 늦게 도착하는 편집의 revision 비교가 이 값을 기준으로 한다.
        // 대신 지금을 기록해, 그 뒤에 새로 쓴 것이 있을 때만 "이 기기에 저장됨" 을 보인다.
        state.editRevisionAtClear = state.editRevision
        state.retiredSession = nil
        // 활성 행도 사라졌다 — 다음 편집은 새 행(create)으로 가야 한다.
        state.activeRowIDs = [:]
        // ★ 기준(내용과 세대)을 **둘 다** 내려놓는다. 다음 조회가 성공해야 다시 합성하고 입력을 연다.
        //   이전 구현은 내용을 `[]` 로 두어, 다시 읽기가 실패하면 빈 내용으로 합성해 입력을 열었다. 세대가 없으니
        //   그 뒤의 필기는 저장을 시작하지 못하고 안내도 없이 큐에 쌓였다 — 앱을 닫으면 사라진다.
        //   세대를 남겨 두면 다음 조회를 또 "사이에 지워졌다" 로 본다.
        state.loadedDrawings = nil
        state.storeGeneration = nil
        // 지운 잉크를 화면에서 바로 내린다. 다시 읽기 전에는 합성된 내용이 없으므로 입력도 닫힌다(`isComposed`).
        // 다시 읽기가 실패해도 지운 필사가 보인 채 남지 않는다.
        state.renderedData = nil
        state.renderedRevision += 1
        state.renderedLayout = nil
        state.ownership = nil
        state.layoutMismatchVerses = []
        state.legacyVerses = []
        state.undecodableVerses = []
        state.legacyInkBounds = nil
        state.lastDirtyBounds = nil
        state.lastEditedVerse = nil
        state.baselineData = nil
        state.$canUndo.withLock { $0 = false }
        state.$canRedo.withLock { $0 = false }
        // 진행 중이던 지우기(보관 후 초기화)의 대상 행도 없다.
        state.eraseTask = nil
        state.eraseAlert = nil
        state.verseMenu = nil
        return startReload(state: &state)
    }
}
