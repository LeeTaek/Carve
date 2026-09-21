//
//  ChapterCanvasLassoTesting.swift
//  CarveFeatureTest
//
//  올가미 — 도구 전환(§4-1 · §4-2)과 편집 계약(§4-3 · §4-3-a). 설계: docs/lasso-design.md
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing
import UIKit

import ComposableArchitecture

@testable import CarveFeature

// MARK: - 도구 매핑 (§4-1 · §4-2)

@Suite("올가미 — 도구 매핑")
struct LassoToolMappingTesting {

    @Test("올가미는 잉크 · 지우개보다 우선하는 한 칸이다")
    func lassoOverridesInkAndEraser() {
        var ink = PencilPalatte.initialState
        ink.pencilType = .pen
        var eraser = PencilPalatte.initialState
        eraser.pencilType = .monoline

        #expect(ChapterCanvasView.tool(for: ink, isLasso: false) is PKInkingTool)
        #expect(ChapterCanvasView.tool(for: eraser, isLasso: false) is PKEraserTool)
        // 지우개 sentinel 이 켜져 있어도 올가미가 이긴다 — 판정이 이 함수 하나라 진실이 갈라지지 않는다.
        #expect(ChapterCanvasView.tool(for: ink, isLasso: true) is PKLassoTool)
        #expect(ChapterCanvasView.tool(for: eraser, isLasso: true) is PKLassoTool)
    }

    @Test("편집 이유는 도구에서 나오고, 히스토리가 있으면 그쪽이 우선한다")
    func editReasonFollowsTool() {
        #expect(ChapterCanvasController.editReason(for: PKInkingTool(.pen), history: nil) == .ink)
        #expect(ChapterCanvasController.editReason(for: PKEraserTool(.bitmap), history: nil) == .erase)
        #expect(ChapterCanvasController.editReason(for: PKLassoTool(), history: nil) == .lasso)
        // undo/redo 로 되돌린 이동은 올가미가 아니라 히스토리다.
        #expect(ChapterCanvasController.editReason(for: PKLassoTool(), history: .undo) == .undo)
        #expect(ChapterCanvasController.editReason(for: PKLassoTool(), history: .redo) == .redo)
    }
}

// MARK: - 편집 계약 (§4-3-a)

/// 올가미 **이동**은 `didBeginUsingTool` 없이 `drawingDidChange` 만 온다 (2026-09-16 실측 L-3).
/// 그대로 두면 이동하는 동안 `isEditing` 이 false 라, 보류돼야 할 레이아웃이 제스처 한가운데 적용된다.
@Suite("올가미 — 이동이 편집 구간을 연다 (§4-3-a)")
@MainActor
struct ChapterCanvasLassoEditContractTesting {

    @MainActor
    private final class Harness {
        let controller = ChapterCanvasController()
        var events: [ChapterCanvasController.Event] = []

        /// 초기 내용은 **표시 경로(`apply`)로** 넣는다. 캔버스에 직접 대입하면 PencilKit 이 그것도 편집으로 알려
        /// (설계 §10-3) 미보고 변경이 남고, 그러면 뒤이은 이동이 "그 이동의 첫 변경" 으로 보이지 않는다.
        init(tool: PKTool, data: Data? = nil) {
            controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 1200)
            controller.loadViewIfNeeded()
            controller.view.layoutIfNeeded()
            controller.onEvent = { [unowned self] event in self.events.append(event) }
            controller.apply(ChapterCanvasController.Configuration(
                renderedData: data, renderedRevision: 4, isInputEnabled: true,
                tool: tool, drawingPolicy: .anyInput, topInset: 0, bottomInset: 24,
                undoRequestVersion: 0, redoRequestVersion: 0, scrollRequest: nil, layout: nil
            ))
        }

        var beganCount: Int {
            events.filter { if case .editBegan = $0 { return true } else { return false } }.count
        }
        var endedReasons: [EditReason] {
            events.compactMap { if case .editEnded(let snapshot) = $0 { return snapshot.reason } else { return nil } }
        }
    }

    private func stroke(y: CGFloat, transform: CGAffineTransform = .identity) -> PKStroke {
        var made = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: y), to: CGPoint(x: 60, y: y), seed: 41, creationTime: 1_000
        )
        if transform != .identity {
            made = PKStroke(ink: made.ink, path: made.path, transform: transform, mask: made.mask, randomSeed: made.randomSeed)
        }
        return made
    }

    @Test("선택 뒤의 이동은 editBegan 을 한 번 합성하고 editEnded(.lasso) 로 닫는다")
    func lassoMoveOpensAndClosesEditSession() async throws {
        let harness = Harness(tool: PKLassoTool(), data: PKDrawing(strokes: [stroke(y: 10)]).dataRepresentation())
        let canvas = harness.controller.canvas
        #expect(!harness.controller.hasUnreportedChange)
        harness.events.removeAll()

        // 올가미 선택 — 도구 시작 · 종료가 오고 내용은 그대로다 (실측 L-3).
        harness.controller.canvasViewDidBeginUsingTool(canvas)
        harness.controller.canvasViewDidEndUsingTool(canvas)
        #expect(harness.beganCount == 1)

        // 이동 — 도구 시작 없이 drawing 만 바뀐다. 여기서 편집 구간이 열려야 한다.
        canvas.drawing = PKDrawing(strokes: [stroke(y: 10, transform: CGAffineTransform(translationX: 0, y: 65))])
        harness.controller.canvasViewDrawingDidChange(canvas)
        #expect(harness.beganCount == 2)

        // 같은 이동의 이어지는 변경에는 다시 열지 않는다.
        canvas.drawing = PKDrawing(strokes: [stroke(y: 10, transform: CGAffineTransform(translationX: 0, y: 70))])
        harness.controller.canvasViewDrawingDidChange(canvas)
        #expect(harness.beganCount == 2)

        try await Task.sleep(for: .milliseconds(450))
        #expect(harness.endedReasons == [.lasso])
    }

    @Test("펜 획에는 합성하지 않는다 — editBegan 이 두 번 나가지 않는다")
    func inkStrokeDoesNotSynthesizeEditBegan() async throws {
        let harness = Harness(tool: PKInkingTool(.pen))
        let canvas = harness.controller.canvas
        harness.events.removeAll()

        harness.controller.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 10)])
        harness.controller.canvasViewDrawingDidChange(canvas)
        harness.controller.canvasViewDidEndUsingTool(canvas)

        #expect(harness.beganCount == 1)
        try await Task.sleep(for: .milliseconds(450))
        #expect(harness.endedReasons == [.ink])
    }
}

// MARK: - 팔레트 (§4-1 · §4-8)

@MainActor
struct PencilPalatteLassoTesting {

    /// 팔레트 상태 하나를 격리된 저장소 위에서 만든다 — `.appStorage` 와 `.inMemory` 둘 다 테스트마다 새것이어야 한다.
    private func withPalette(_ body: (inout PencilPalatteFeature.State, PencilPalatteFeature) -> Void) throws {
        let suite = "PencilPalatteLassoTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        withDependencies {
            $0.defaultAppStorage = defaults
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = PencilPalatteFeature.State()
            body(&state, PencilPalatteFeature())
        }
    }

    @Test("올가미를 고르면 잉크 설정은 그대로 두고 도구만 바뀐다")
    func selectingLassoKeepsInkSettings() throws {
        try withPalette { state, reducer in
            state.isLassoAvailable = true
            _ = reducer.reduce(into: &state, action: .view(.setPencilType(.marker)))

            _ = reducer.reduce(into: &state, action: .view(.selectLasso))

            #expect(state.isLassoSelected)
            // 펜 칸으로 돌아왔을 때 마지막 잉크를 복원할 수 있어야 한다 — sentinel 을 건드리지 않는다.
            #expect(state.pencilConfig.pencilType == .marker)
            #expect(state.lastInkType == .marker)
        }
    }

    @Test("펜 · 지우개를 누르면 올가미에서 빠져나온다")
    func choosingPenOrEraserLeavesLasso() throws {
        try withPalette { state, reducer in
            state.isLassoAvailable = true

            _ = reducer.reduce(into: &state, action: .view(.selectLasso))
            _ = reducer.reduce(into: &state, action: .view(.setPencilType(.pen)))
            #expect(!state.isLassoSelected)

            _ = reducer.reduce(into: &state, action: .view(.selectLasso))
            _ = reducer.reduce(into: &state, action: .view(.setPencilType(.monoline)))
            #expect(!state.isLassoSelected)
            #expect(state.pencilConfig.pencilType == .monoline)
        }
    }

    @Test("롤백 경로(N-Canvas)에서는 올가미를 고를 수 없다 (§4-8)")
    func lassoIsUnavailableOnRollbackPath() throws {
        try withPalette { state, reducer in
            state.isLassoAvailable = false

            _ = reducer.reduce(into: &state, action: .view(.selectLasso))

            #expect(!state.isLassoSelected)
        }
    }
}
