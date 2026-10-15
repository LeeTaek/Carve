//
//  CarveDetailFeature+Background.swift
//  CarveFeature
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics

import ComposableArchitecture

/// 백그라운드 배치 — 홈으로 나간 사이 시스템이 다시 배치한 화면의 실측을 믿지 않는다.
///
/// iPadOS 18 은 앱이 백그라운드에 들어가면 앱 전환기 스냅샷을 찍으며 화면을 compact 폭(iPad mini 세로 414pt)으로 한 번 다시 배치했다가
/// 원래 폭으로 되돌린다. 그 사이 필사 컬럼이 폭 207 → 372 로 두 번 다시 지어지는데, 마지막 행 frame 이 컬럼 중심만큼(−372, −3768.5)
/// 어긋난 채 들어왔다. 돌아온 뒤에는 배치가 바뀌지 않아 행이 다시 보고하지 않으므로 그 값이 남았고,
/// `columnOrigin` (0, 0) 으로 잉크가 372pt 왼쪽에 다시 합성되고 Δ 안전망이 새 획을 막았다(2026-10-15 18.6 시뮬레이터, 26.2 는 이 배치가 없다).
///
/// 그래서 백그라운드 동안 온 실측 · 폭은 **반영하지 않고 미룬다** — 측정 · 레이아웃 · 캔버스는 나가기 전 그대로다.
/// 다시 활성이 되면 미룬 폭을 평소 폭 변경처럼 적용하고, 실측이 왔었으면 컬럼을 새로 지어(`columnMeasureGeneration`)
/// 지금 배치를 모든 행이 다시 보고하게 한다. 같은 배치면 값이 같아 레이아웃 · 합성이 다시 일어나지 않는다.
extension CarveDetailFeature {
    /// 역할: 백그라운드 동안 온 컬럼 실측 · 폭을 미뤄 둔다.
    /// 입력 · 출력: 상태 · 들어온 필사 컬럼 폭(행 실측이면 nil) → 효과 없음.
    /// 부작용: 없음 — 측정 · 레이아웃 · 캔버스를 건드리지 않는다.
    func deferBackgroundMeasurement(state: inout State, writingWidth: CGFloat? = nil) -> Effect<Action> {
        state.hasBackgroundMeasurement = true
        if let writingWidth { state.deferredWritingWidth = writingWidth }
        return .none
    }

    /// 역할: 다시 활성이 됐다 — 미룬 폭을 적용하고, 백그라운드 동안 실측이 왔으면 컬럼을 새로 재게 한다.
    /// 입력 · 출력: 상태 → 폭이 바뀌어 다시 지은 레이아웃을 캔버스에 넘기는 효과(바뀐 것이 없으면 없음).
    /// 부작용: 없음 — 컬럼 재측정은 뷰가 `columnMeasureGeneration` 을 보고 한다.
    func resumeFromBackground(state: inout State) -> Effect<Action> {
        guard state.isInBackground else { return .none }
        state.isInBackground = false
        guard state.hasBackgroundMeasurement else { return .none }
        state.hasBackgroundMeasurement = false
        state.columnMeasureGeneration += 1
        guard let width = state.deferredWritingWidth else { return .none }
        state.deferredWritingWidth = nil
        // 폭은 컨테이너가 준 값이라 믿는다 — 평소 폭 변경(`layoutHostingChanged`)과 같은 길이다.
        if state.chapterLayout.setWritingWidth(width) {
            rebuildLayoutIfNeeded(state: &state)
        }
        return forwardLayoutToSingleCanvas(state: &state)
    }

    /// 역할: 필사 화면이 나타나며(`appeared`) 부를 본문 읽기가 백그라운드 배치 때문인가 — 이미 보고 있는 장이면 다시 읽지 않는다.
    /// 입력 · 출력: 상태 → 건너뛸 읽기면 true.
    /// 부작용: 없음.
    ///
    /// 분할 화면이 compact 로 접혔다 펴지며 필사 화면이 사라졌다 다시 나타나면 `onAppear` 가 본문을 다시 읽는다.
    /// 그대로 두면 측정과 캔버스가 처음부터 다시 시작해 돌아왔을 때 잉크가 비었다가 다시 그려진다.
    /// 장이 바뀌었으면 행의 장과 지금 장이 달라 그대로 읽는다. 장 이동 · 딥링크는 `fetchSentence` 를 직접 보내 이 판정을 지나지 않는다.
    static func isRedundantBackgroundFetch(_ state: State) -> Bool {
        guard state.isInBackground, let shown = state.sentenceWithDrawingState.first?.sentence.title else { return false }
        return shown == state.headerState.currentTitle
    }
}
