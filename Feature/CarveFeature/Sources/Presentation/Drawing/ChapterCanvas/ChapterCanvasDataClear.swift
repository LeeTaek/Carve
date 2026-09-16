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
    func clearAfterExternalDelete(state: inout State) -> Effect<Action> {
        state.pendingMutations = [:]
        state.inFlightBatch = [:]
        state.inFlightMutations = []
        state.inFlightChapter = nil
        state.editQueue = []
        state.isPreparingEdit = false
        state.saveStatus = .idle
        state.retiredSession = nil
        // 활성 행도 사라졌다 — 다음 편집은 새 행(create)으로 가야 한다.
        state.activeRowIDs = [:]
        state.loadedDrawings = []
        state.baselineData = nil
        // 진행 중이던 지우기(보관 후 초기화)의 대상 행도 없다.
        state.eraseTask = nil
        state.eraseAlert = nil
        state.verseMenu = nil
        return startReload(state: &state)
    }
}
