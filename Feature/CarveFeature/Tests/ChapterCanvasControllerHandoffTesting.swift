//
//  ChapterCanvasControllerHandoffTesting.swift
//  CarveFeatureTest
//
//  단일 Canvas 컨트롤러의 인계 — 미보고 편집을 지금 보고하고 끝났다고 알린다 (정책 §12-6 구현 순서 ②).
//

import PencilKit
import Testing
import UIKit

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 세션을 닫을 때 디바운스(0.3초) 안의 마지막 획을 받지 못한 채 닫는 것 — 시간을 재서 멎었다고 짐작하지 않는다
/// - 획을 긋는 중에 인계를 마쳐, PencilKit 이 아직 반영하지 않은 그 획을 빠뜨리는 것
/// - 인계 완료가 마지막 편집보다 먼저 도착하는 것
/// - 도구 사용이 끝났다는 알림을 놓쳐 인계가 끝없이 멈추는 것
/// - 캔버스가 화면에서 빠지며 마지막 획 · 받아 둔 인계를 보고하지 않는 것(컨트롤러가 먼저 사라져도)
@Suite("단일 Canvas 컨트롤러 — 인계")
@MainActor
struct ChapterCanvasControllerHandoffTesting {
    /// 컨트롤러가 사라진 뒤에도 사건을 모은다.
    @MainActor
    private final class EventLog {
        var events: [ChapterCanvasController.Event] = []

        var editEndedGenerations: [Int] {
            events.compactMap { if case .editEnded(let snapshot) = $0 { return snapshot.generation } else { return nil } }
        }
        var editEndedReasons: [EditReason] {
            events.compactMap { if case .editEnded(let snapshot) = $0 { return snapshot.reason } else { return nil } }
        }
        var cancelledCount: Int {
            events.filter { if case .editCancelled = $0 { return true } else { return false } }.count
        }
        var handoffTokens: [Int] {
            events.compactMap { if case .handoffCompleted(let token) = $0 { return token } else { return nil } }
        }
        var firstHandoffIndex: Int? {
            events.firstIndex { if case .handoffCompleted = $0 { return true } else { return false } }
        }
        var lastEditEndedIndex: Int? {
            events.lastIndex { if case .editEnded = $0 { return true } else { return false } }
        }
        var detachedIndex: Int? {
            events.firstIndex { if case .detached = $0 { return true } else { return false } }
        }
        var lastIndexBeforeDetach: Int? {
            events.lastIndex { if case .detached = $0 { return false } else { return true } }
        }
    }

    @MainActor
    private final class Harness {
        let controller = ChapterCanvasController()
        let log = EventLog()
        private var window: UIWindow?

        /// - Parameter windowed: 창에 붙인다 — 응답자 사슬에 undoManager 가 생긴다.
        init(windowed: Bool = false) {
            controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 1200)
            if windowed {
                let window = UIWindow(frame: controller.view.frame)
                window.rootViewController = controller
                window.isHidden = false
                self.window = window
            }
            controller.loadViewIfNeeded()
            controller.view.layoutIfNeeded()
            controller.onEvent = { [log] event in log.events.append(event) }
        }

        func close() {
            window?.isHidden = true
        }

        func apply(revision: Int, handoffToken: Int = 0, undoRequestVersion: Int = 0) {
            controller.apply(ChapterCanvasController.Configuration(
                renderedData: nil, renderedRevision: revision, isInputEnabled: true,
                tool: PKInkingTool(.pen), drawingPolicy: .anyInput, topInset: 0, bottomInset: 24,
                undoRequestVersion: undoRequestVersion, redoRequestVersion: 0, scrollRequest: nil, layout: nil, handoffToken: handoffToken
            ))
        }

        var events: [ChapterCanvasController.Event] { log.events }
    }

    private func stroke(y: CGFloat) -> PKStroke {
        OwnershipTestSupport.stroke(from: CGPoint(x: 10, y: y), to: CGPoint(x: 60, y: y), seed: UInt32(y), creationTime: Double(y))
    }

    @Test("인계를 요청받으면 미보고 획을 디바운스를 기다리지 않고 지금 보고한 뒤 끝났다고 알린다")
    func handoffReportsUnreportedEditImmediately() async throws {
        let harness = Harness()
        harness.apply(revision: 1)
        let canvas = harness.controller.canvas
        harness.controller.canvasViewDidBeginUsingTool(canvas)
        harness.controller.canvasViewDidEndUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 10)])
        harness.controller.canvasViewDrawingDidChange(canvas)

        harness.apply(revision: 1, handoffToken: 1)
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.log.editEndedGenerations == [1])
        #expect(harness.log.handoffTokens == [1])
        #expect((harness.log.lastEditEndedIndex ?? .max) < (harness.log.firstHandoffIndex ?? .min))
        // 디바운스 보고가 뒤늦게 한 번 더 나가지 않는다.
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.log.editEndedGenerations == [1])
    }

    @Test("획을 긋는 중에 인계를 요청받으면 그 획이 반영된 뒤에 보고하고 마친다")
    func handoffDuringStrokeWaitsForTheStroke() async throws {
        let harness = Harness()
        harness.apply(revision: 1)
        let canvas = harness.controller.canvas
        harness.controller.canvasViewDidBeginUsingTool(canvas)

        harness.apply(revision: 1, handoffToken: 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.log.handoffTokens.isEmpty)

        // 도구가 끝난 뒤 PencilKit 이 획을 반영한다(§7-5).
        harness.controller.canvasViewDidEndUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 20)])
        harness.controller.canvasViewDrawingDidChange(canvas)
        try await Task.sleep(for: .milliseconds(500))

        #expect(harness.log.editEndedGenerations == [1])
        #expect(harness.log.handoffTokens == [1])
        #expect((harness.log.lastEditEndedIndex ?? .max) < (harness.log.firstHandoffIndex ?? .min))
    }

    /// 비활성화 인계는 입력을 막지 않는다. 획이 끝나 반영을 기다리는 동안 새 획이 시작되면, 그 획 도중에 보고하지 않고 그 획이 끝난 뒤에 마친다.
    @Test("인계를 마치려고 기다리는 동안 새 획이 시작되면 기다림을 거두고, 그 획이 끝나 반영된 뒤에 마친다")
    func newStrokeDefersPendingHandoffCompletion() async throws {
        let harness = Harness()
        harness.apply(revision: 1)
        let canvas = harness.controller.canvas
        harness.controller.canvasViewDidBeginUsingTool(canvas)
        harness.apply(revision: 1, handoffToken: 1)
        harness.controller.canvasViewDidEndUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 50)])
        harness.controller.canvasViewDrawingDidChange(canvas)

        // 반영을 기다리는 0.3초 안에 다음 획이 시작된다.
        try await Task.sleep(for: .milliseconds(100))
        harness.controller.canvasViewDidBeginUsingTool(canvas)
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.log.handoffTokens.isEmpty)
        #expect(harness.log.editEndedGenerations.isEmpty)

        harness.controller.canvasViewDidEndUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 50), stroke(y: 60)])
        harness.controller.canvasViewDrawingDidChange(canvas)
        try await Task.sleep(for: .milliseconds(500))

        #expect(harness.log.editEndedGenerations == [1])
        #expect(harness.log.handoffTokens == [1])
        #expect((harness.log.lastEditEndedIndex ?? .max) < (harness.log.firstHandoffIndex ?? .min))
    }

    @Test("보고할 획이 없으면 열려 있을 수 있는 편집 구간을 닫고 끝났다고 알린다")
    func handoffWithoutChangesClosesTheEditSpan() async throws {
        let harness = Harness()
        harness.apply(revision: 1)

        harness.apply(revision: 1, handoffToken: 1)
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.log.editEndedGenerations.isEmpty)
        #expect(harness.log.cancelledCount == 1)
        #expect(harness.log.handoffTokens == [1])
    }

    /// 뷰가 바뀌어 새 캔버스가 만들어져도 그 캔버스는 보고할 편집이 없다. 빈 응답이 다른 캔버스의 편집 구간을 닫지 않게 받아 두기만 한다.
    @Test("새 캔버스는 첫 표시 상태의 인계 토큰에 응답하지 않고, 그 뒤의 요청에만 응답한다")
    func firstApplyAbsorbsHandoffToken() async throws {
        let harness = Harness()
        harness.apply(revision: 1, handoffToken: 5)
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.log.handoffTokens.isEmpty)
        #expect(harness.log.cancelledCount == 0)

        harness.apply(revision: 1, handoffToken: 6)
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.log.handoffTokens == [6])
    }

    /// Feature 는 캔버스가 있는 동안 응답이 늦어도 닫지 않고 다시 요청한다. 도구 사용이 끝났다는 알림을 놓쳤다면 그 재요청이 풀어 준다 —
    /// 그리기 인식기가 움직이고 있으면(긴 획) 계속 기다린다.
    @Test("다시 요청받았는데 그리기 인식기가 멎어 있으면 끝난 도구 사용으로 보고, 획이 반영될 시간을 둔 뒤 새 토큰으로 마친다")
    func repeatRequestEndsStaleToolUse() async throws {
        let harness = Harness()
        harness.apply(revision: 1)
        let canvas = harness.controller.canvas
        harness.controller.canvasViewDidBeginUsingTool(canvas)

        harness.apply(revision: 1, handoffToken: 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.log.handoffTokens.isEmpty)

        harness.apply(revision: 1, handoffToken: 2)
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.log.handoffTokens.isEmpty)
        try await Task.sleep(for: .milliseconds(400))

        #expect(harness.log.handoffTokens == [2])
        #expect(harness.log.cancelledCount == 1)
    }

    @Test("캔버스가 빠질 때 미보고 획을 먼저 보고하고 떨어졌다고 알린다 — 컨트롤러가 먼저 사라져도 보고를 잃지 않는다")
    func detachReportsUnreportedEditFirst() async throws {
        let log = EventLog()
        var instanceID: UUID?
        do {
            let controller = ChapterCanvasController()
            controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 1200)
            controller.loadViewIfNeeded()
            controller.onEvent = { [log] event in log.events.append(event) }
            controller.apply(ChapterCanvasController.Configuration(
                renderedData: nil, renderedRevision: 1, isInputEnabled: true,
                tool: PKInkingTool(.pen), drawingPolicy: .anyInput, topInset: 0, bottomInset: 24,
                undoRequestVersion: 0, redoRequestVersion: 0, scrollRequest: nil, layout: nil
            ))
            let canvas = controller.canvas
            controller.canvasViewDidBeginUsingTool(canvas)
            controller.canvasViewDidEndUsingTool(canvas)
            canvas.drawing = PKDrawing(strokes: [stroke(y: 30)])
            controller.canvasViewDrawingDidChange(canvas)
            instanceID = controller.instanceID
            controller.detach()
        }
        try await Task.sleep(for: .milliseconds(50))

        #expect(log.editEndedGenerations == [1])
        let detached = try #require(log.detachedIndex)
        #expect((log.lastEditEndedIndex ?? .max) < detached)
        #expect(log.events.last.map { if case .detached(let id) = $0 { return id == instanceID } else { return false } } == true)
        // 디바운스 보고가 뒤늦게 나가지 않는다.
        try await Task.sleep(for: .milliseconds(400))
        #expect(log.editEndedGenerations == [1])
    }

    @Test("인계를 기다리는 중에 캔버스가 빠지면 받아 둔 인계를 마친 뒤 떨어졌다고 알린다")
    func detachCompletesPendingHandoff() async throws {
        let harness = Harness()
        harness.apply(revision: 1)
        let canvas = harness.controller.canvas
        harness.controller.canvasViewDidBeginUsingTool(canvas)
        harness.apply(revision: 1, handoffToken: 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.log.handoffTokens.isEmpty)

        harness.controller.detach()
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.log.cancelledCount == 1)
        #expect(harness.log.handoffTokens == [1])
        let detached = try #require(harness.log.detachedIndex)
        #expect((harness.log.firstHandoffIndex ?? .max) < detached)
        #expect(detached == harness.events.count - 1)
    }

    /// 계정이 바뀌는 순간과 되돌리기 요청이 한 번의 뷰 갱신에 함께 올 수 있다. 인계를 먼저 마치면 되돌린 결과가 인계 뒤에 늦게 보고된다.
    @Test("같은 갱신에 온 되돌리기를 수행한 뒤에 인계를 마친다 — 되돌린 결과가 인계 완료보다 먼저 보고된다")
    func handoffCompletesAfterUndoInSameUpdate() async throws {
        let harness = Harness(windowed: true)
        defer { harness.close() }
        harness.apply(revision: 1)
        let canvas = harness.controller.canvas
        let undoManager = try #require(canvas.undoManager)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 40)])
        harness.controller.canvasViewDrawingDidChange(canvas)
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.log.editEndedGenerations == [1])
        undoManager.removeAllActions()
        undoManager.registerUndo(withTarget: canvas) { $0.drawing = PKDrawing() }
        try await Task.sleep(for: .milliseconds(20))
        #expect(undoManager.canUndo)

        harness.apply(revision: 1, handoffToken: 1, undoRequestVersion: 1)
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.log.editEndedReasons.last == .undo)
        #expect(harness.log.handoffTokens == [1])
        #expect((harness.log.lastEditEndedIndex ?? .max) < (harness.log.firstHandoffIndex ?? .min))
        #expect(canvas.drawing.strokes.isEmpty)
    }
}
