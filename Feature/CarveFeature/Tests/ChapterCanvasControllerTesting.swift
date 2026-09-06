//
//  ChapterCanvasControllerTesting.swift
//  CarveFeatureTest
//
//  Phase 3 (rev.17) — ChapterCanvasController 의 편집 계약(§8-1)과 기하.
//  PKCanvasViewDelegate 메서드를 직접 불러 이벤트 순서를 고정한다. 펜 입력은 시뮬레이터에 없으므로 이것이 유일한 자동 검증이다.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing
import UIKit

@testable import CarveFeature

@Suite("Phase 3 — ChapterCanvasController · 편집 계약과 기하 (rev.17)")
@MainActor
struct ChapterCanvasControllerTesting {

    /// 컨트롤러와 그 이벤트 기록.
    private final class Harness {
        let controller = ChapterCanvasController()
        var events: [ChapterCanvasController.Event] = []

        init() {
            controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 1200)
            controller.loadViewIfNeeded()
            controller.view.layoutIfNeeded()
            controller.onEvent = { [unowned self] event in self.events.append(event) }
        }

        func apply(revision: Int, data: Data? = nil, topInset: CGFloat = 0, layout: ChapterLayout? = nil,
                   scroll: ChapterCanvasFeature.State.ScrollRequest? = nil) {
            controller.apply(ChapterCanvasController.Configuration(
                renderedData: data, renderedRevision: revision, isInputEnabled: true,
                tool: PKInkingTool(.pen), drawingPolicy: .anyInput, topInset: topInset,
                undoRequestVersion: 0, redoRequestVersion: 0, scrollRequest: scroll, layout: layout
            ))
        }

        var editEndedGenerations: [Int] {
            events.compactMap { if case .editEnded(let snapshot) = $0 { return snapshot.generation } else { return nil } }
        }
        var cancelledCount: Int {
            events.filter { if case .editCancelled = $0 { return true } else { return false } }.count
        }
    }

    private func stroke(y: CGFloat) -> PKStroke {
        OwnershipTestSupport.stroke(from: CGPoint(x: 10, y: y), to: CGPoint(x: 60, y: y), seed: UInt32(y), creationTime: Double(y))
    }

    // MARK: 편집 계약

    @Test("다음 획이 시작되면 직전 획의 trailing editEnded 는 취소되고, 도구가 끝난 뒤 두 획이 한 번에 보고된다")
    func nextStrokeCancelsTrailingReportAndMergesIt() async throws {
        let harness = Harness()
        harness.apply(revision: 5)
        let canvas = harness.controller.canvas

        // 첫 획.
        harness.controller.canvasViewDidBeginUsingTool(canvas)
        harness.controller.canvasViewDidEndUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 10)])
        harness.controller.canvasViewDrawingDidChange(canvas)

        // trailing(0.3 s) 이 나가기 전에 두 번째 획이 시작된다.
        try await Task.sleep(for: .milliseconds(100))
        harness.controller.canvasViewDidBeginUsingTool(canvas)
        try await Task.sleep(for: .milliseconds(450))
        // 이전 구현은 여기서 editEnded 가 나가 isEditing 이 획 도중에 풀렸다.
        #expect(harness.editEndedGenerations.isEmpty)
        #expect(harness.controller.hasUnreportedChange)

        harness.controller.canvasViewDidEndUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 10), stroke(y: 40)])
        harness.controller.canvasViewDrawingDidChange(canvas)
        try await Task.sleep(for: .milliseconds(450))

        #expect(harness.editEndedGenerations == [5])
        #expect(harness.cancelledCount == 0)
        guard case .editEnded(let snapshot)? = harness.events.last(where: { if case .editEnded = $0 { return true } else { return false } }) else {
            Issue.record("editEnded 가 없다"); return
        }
        #expect(try PKDrawing(data: snapshot.drawingData).strokes.count == 2)
    }

    @Test("직전 획의 보고가 취소된 뒤 변경 없는 도구 사용(탭)이 끝나면 미보고 변경이 그때 보고된다 — 유실되지 않는다")
    func unreportedChangeIsReportedAfterChangelessToolUse() async throws {
        let harness = Harness()
        harness.apply(revision: 3)
        let canvas = harness.controller.canvas

        harness.controller.canvasViewDidBeginUsingTool(canvas)
        harness.controller.canvasViewDidEndUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 10)])
        harness.controller.canvasViewDrawingDidChange(canvas)

        try await Task.sleep(for: .milliseconds(100))
        harness.controller.canvasViewDidBeginUsingTool(canvas)   // 탭 — 변경 없음
        harness.controller.canvasViewDidEndUsingTool(canvas)
        try await Task.sleep(for: .milliseconds(450))

        #expect(harness.editEndedGenerations == [3])
        #expect(harness.cancelledCount == 0)
    }

    @Test("변경 없이 끝난 도구 사용은 editCancelled 로 알린다")
    func changelessToolUseIsCancelled() async throws {
        let harness = Harness()
        harness.apply(revision: 1)
        let canvas = harness.controller.canvas

        harness.controller.canvasViewDidBeginUsingTool(canvas)
        harness.controller.canvasViewDidEndUsingTool(canvas)
        try await Task.sleep(for: .milliseconds(450))

        #expect(harness.cancelledCount == 1)
        #expect(harness.editEndedGenerations.isEmpty)
    }

    @Test("내용이 교체되면 미보고 편집은 이전 세대 번호로 먼저 보고된다 — 장 전환 직전의 마지막 획")
    func unreportedEditIsFlushedWithPreviousGenerationBeforeReplacement() async throws {
        let harness = Harness()
        harness.apply(revision: 7)
        let canvas = harness.controller.canvas

        harness.controller.canvasViewDidBeginUsingTool(canvas)
        harness.controller.canvasViewDidEndUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: [stroke(y: 10)])
        harness.controller.canvasViewDrawingDidChange(canvas)

        // trailing 이 나가기 전에 새 장(세대 8, 빈 캔버스)이 온다.
        harness.apply(revision: 8, data: nil)
        #expect(canvas.drawing.strokes.isEmpty)
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.editEndedGenerations == [7])
        guard case .editEnded(let snapshot)? = harness.events.last(where: { if case .editEnded = $0 { return true } else { return false } }) else {
            Issue.record("editEnded 가 없다"); return
        }
        // 교체 전 내용이 실려 있다.
        #expect(try PKDrawing(data: snapshot.drawingData).strokes.count == 1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.editEndedGenerations == [7])   // 이후 중복 보고 없음
    }

    // MARK: 기하

    @Test("텍스트 호스트 frame 은 컬럼 자신의 높이다 — 짧은 장에서 content 높이로 늘리면 세로 중앙 배치돼 잉크와 어긋난다")
    func hostFrameFollowsColumnHeightNotContentHeight() {
        let harness = Harness()
        harness.apply(revision: 1, topInset: 100)
        let canvas = harness.controller.canvas

        harness.controller.setColumnHeight(300)
        canvas.layoutIfNeeded()
        #expect(canvas.contentFrame.height == 300)
        #expect(canvas.contentHostView?.frame.height == 300)
        // 스크롤 영역은 여전히 뷰포트를 채운다 (1200 − 헤더 100).
        let viewportContentHeight: CGFloat = 1_100
        #expect(canvas.contentSize.height == viewportContentHeight)

        harness.controller.setColumnHeight(5_000)
        canvas.layoutIfNeeded()
        #expect(canvas.contentFrame.height == 5_000)
        #expect(canvas.contentSize.height == 5_000)
    }

    @Test("헤더 높이가 첫 apply 뒤에 도착해도 맨 위에 있던 스크롤은 새 인셋만큼 내려 상단이 가리지 않는다")
    func lateHeaderHeightRepinsTop() {
        let harness = Harness()
        let canvas = harness.controller.canvas
        harness.apply(revision: 1, topInset: 0)
        #expect(canvas.contentOffset.y == 0)

        harness.apply(revision: 1, topInset: 120)
        #expect(canvas.contentInset.top == 120)
        #expect(canvas.contentOffset.y == -120)

        // 이미 내려간 스크롤은 건드리지 않는다.
        harness.controller.setColumnHeight(5_000)
        canvas.contentOffset = CGPoint(x: 0, y: 900)
        harness.apply(revision: 1, topInset: 80)
        #expect(canvas.contentOffset.y == 900)
    }

    @Test("scrollOffset 은 top inset 을 빼지 않는다 — 절 하단이 보이는 하단(bounds − bottom inset) 근처에 온다")
    func scrollOffsetIgnoresTopInsetAndClamps() {
        let inset = UIEdgeInsets(top: 100, left: 0, bottom: 50, right: 0)
        let offset = ChapterCanvasController.scrollOffset(
            bringingBottomOf: CGRect(x: 0, y: 900, width: 300, height: 100),
            viewportHeight: 800, contentInset: inset, contentHeight: 3_000
        )
        // 1000 + 40 − (800 − 50) = 290. 이전 구현은 top 을 한 번 더 빼 390 — 목표가 헤더 높이만큼 위였다.
        #expect(offset == 290)

        let top = ChapterCanvasController.scrollOffset(
            bringingBottomOf: CGRect(x: 0, y: 0, width: 300, height: 100),
            viewportHeight: 800, contentInset: inset, contentHeight: 3_000
        )
        #expect(top == -100)

        let bottom = ChapterCanvasController.scrollOffset(
            bringingBottomOf: CGRect(x: 0, y: 2_900, width: 300, height: 100),
            viewportHeight: 800, contentInset: inset, contentHeight: 3_000
        )
        let maxOffset: CGFloat = 2_250   // 3000 − 800 + 50
        #expect(bottom == maxOffset)
    }
}
