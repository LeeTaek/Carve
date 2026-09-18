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
@Suite("단일 Canvas 컨트롤러 — 인계")
@MainActor
struct ChapterCanvasControllerHandoffTesting {
    @MainActor
    private final class Harness {
        let controller = ChapterCanvasController()
        var events: [ChapterCanvasController.Event] = []

        init() {
            controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 1200)
            controller.loadViewIfNeeded()
            controller.view.layoutIfNeeded()
            controller.onEvent = { [unowned self] event in self.events.append(event) }
        }

        func apply(revision: Int, handoffToken: Int = 0) {
            controller.apply(ChapterCanvasController.Configuration(
                renderedData: nil, renderedRevision: revision, isInputEnabled: true,
                tool: PKInkingTool(.pen), drawingPolicy: .anyInput, topInset: 0, bottomInset: 24,
                undoRequestVersion: 0, redoRequestVersion: 0, scrollRequest: nil, layout: nil, handoffToken: handoffToken
            ))
        }

        var editEndedGenerations: [Int] {
            events.compactMap { if case .editEnded(let snapshot) = $0 { return snapshot.generation } else { return nil } }
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

        #expect(harness.editEndedGenerations == [1])
        #expect(harness.handoffTokens == [1])
        #expect((harness.lastEditEndedIndex ?? .max) < (harness.firstHandoffIndex ?? .min))
        // 디바운스 보고가 뒤늦게 한 번 더 나가지 않는다.
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.editEndedGenerations == [1])
    }

    @Test("획을 긋는 중에 인계를 요청받으면 그 획이 반영된 뒤에 보고하고 마친다")
    func handoffDuringStrokeWaitsForTheStroke() async throws {
        let harness = Harness()
        harness.apply(revision: 1)
        let canvas = harness.controller.canvas
        harness.controller.canvasViewDidBeginUsingTool(canvas)

        harness.apply(revision: 1, handoffToken: 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.handoffTokens.isEmpty)

        // 도구가 끝난 뒤 PencilKit 이 획을 반영한다(§7-5).
        harness.controller.canvasViewDidEndUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 20)])
        harness.controller.canvasViewDrawingDidChange(canvas)
        try await Task.sleep(for: .milliseconds(500))

        #expect(harness.editEndedGenerations == [1])
        #expect(harness.handoffTokens == [1])
        #expect((harness.lastEditEndedIndex ?? .max) < (harness.firstHandoffIndex ?? .min))
    }

    @Test("보고할 획이 없으면 열려 있을 수 있는 편집 구간을 닫고 끝났다고 알린다")
    func handoffWithoutChangesClosesTheEditSpan() async throws {
        let harness = Harness()
        harness.apply(revision: 1)

        harness.apply(revision: 1, handoffToken: 1)
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.editEndedGenerations.isEmpty)
        #expect(harness.cancelledCount == 1)
        #expect(harness.handoffTokens == [1])
    }
}
