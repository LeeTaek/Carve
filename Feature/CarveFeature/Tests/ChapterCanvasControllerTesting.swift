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
import SwiftUI
import Testing
import UIKit

@testable import CarveFeature

/// 실제 절 행과 **같은 종류의 세로 유연성**을 갖는 최소 컬럼.
///
/// 행 안 밑줄 뷰(`SentencesWithDrawingView.underLineView`)가 `maxHeight: .infinity` 라, 큰 높이를 제안받으면
/// 행이 실제로 커진다. 그 성질만 재현한다 — 이상적 높이는 `rowCount * rowHeight`, 그보다 큰 제안이 오면 그만큼 늘어난다.
private struct StretchyColumnStub: View {
    let rowCount: Int
    let rowHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                Color.clear.frame(minHeight: rowHeight, maxHeight: .infinity)
            }
        }
    }
}

/// `onGeometryChange` 로 온 값을 테스트로 넘기는 상자 (전부 main actor 에서만 만진다).
@MainActor
private final class ValueBox<Value> {
    var value: Value?
}

@Suite("Phase 3 — ChapterCanvasController · 편집 계약과 기하 (rev.17)")
@MainActor
struct ChapterCanvasControllerTesting {

    /// 컨트롤러와 그 이벤트 기록.
    private final class Harness {
        let controller = ChapterCanvasController()
        var events: [ChapterCanvasController.Event] = []
        /// SwiftUI 컬럼을 실제로 배치·측정해야 하는 테스트만 창을 쓴다 (`onGeometryChange` 가 돌아야 하므로).
        private let window: UIWindow?

        init(inWindow: Bool = false) {
            controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 1200)
            if inWindow {
                let window = UIWindow(frame: controller.view.frame)
                window.rootViewController = controller
                window.isHidden = false
                self.window = window
            } else {
                self.window = nil
            }
            controller.loadViewIfNeeded()
            controller.view.layoutIfNeeded()
            controller.onEvent = { [unowned self] event in self.events.append(event) }
        }

        @MainActor
        func teardown() {
            window?.isHidden = true
        }

        /// 컬럼을 컨트롤러에 붙인다 — **뷰가 쓰는 조합 그대로**(`ChapterCanvasView.hostedColumn`).
        @MainActor
        func setColumn(_ column: some View) {
            controller.setColumn(ChapterCanvasView.hostedColumn(AnyView(column)) { [unowned self] height in
                self.controller.setColumnHeight(height)
            })
        }

        /// SwiftUI 배치 → `onGeometryChange` → `setColumnHeight` → `updateContentGeometry` 가 한 바퀴 도는 것을 기다린다.
        @MainActor
        func settleContentFrameHeight(expecting expected: CGFloat, tolerance: CGFloat = 0.5) async -> CGFloat {
            for _ in 0..<60 {
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                if abs(controller.canvas.contentFrame.height - expected) <= tolerance { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            return controller.canvas.contentFrame.height
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

    @Test("긴 장에서 온 columnHeight 가 남아 있어도 짧은 장의 컬럼은 그 높이로 늘어나지 않는다 — 장 전환 좌표 어긋남 (D9)")
    func staleColumnHeightDoesNotInflateShorterChapter() async throws {
        let harness = Harness(inWindow: true)
        harness.apply(revision: 1)

        // 긴 장(창세기 1장)을 보고 나온 직후. 컨트롤러는 장 전환에도 살아남고 columnHeight 를 지우는 곳이 없다.
        harness.controller.setColumnHeight(5_000)
        #expect(harness.controller.canvas.contentFrame.height == 5_000)

        // 짧은 장(창세기 2장)의 컬럼이 들어온다. 이상적 높이는 300 — 호스트 frame(5,000)보다 훨씬 작다.
        harness.setColumn(StretchyColumnStub(rowCount: 3, rowHeight: 100))

        // 컬럼이 5,000 으로 늘어나면 다시 잰 높이가 이전 값과 같아 setColumnHeight 의 guard 에 걸린다 → 고정점.
        let settled = await harness.settleContentFrameHeight(expecting: 300)
        #expect(settled == 300)
        #expect(harness.controller.canvas.contentFrame.height == 300)
        #expect(harness.controller.canvas.contentHostView?.frame.height == 300)
        harness.teardown()
    }

    @Test("호스트가 컬럼보다 커도 컬럼은 이상적 높이를 유지하고 상단에 붙는다 — 세로 중앙 배치 금지")
    func hostedColumnKeepsIdealHeightAndStaysAtTop() async throws {
        let reported = ValueBox<CGFloat>()
        let columnFrame = ValueBox<CGRect>()
        let hosting = UIHostingController(
            rootView: ChapterCanvasView.hostedColumn(AnyView(
                StretchyColumnStub(rowCount: 3, rowHeight: 100)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        columnFrame.value = frame
                    }
            )) { height in
                reported.value = height
            }
        )
        // 호스트는 컬럼(300)보다 훨씬 크다 — 장 전환 직후 낡은 columnHeight 로 잡힌 호스트 frame 과 같은 상황.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1_200))
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.frame = window.bounds

        for _ in 0..<60 {
            hosting.view.setNeedsLayout()
            hosting.view.layoutIfNeeded()
            if columnFrame.value != nil, reported.value != nil { break }
            try? await Task.sleep(for: .milliseconds(30))
        }

        // fixedSize 가 없으면 컬럼이 제안된 1,200 을 그대로 채우고 그 값을 보고한다.
        #expect(reported.value == 300)
        let frame = try #require(columnFrame.value)
        #expect(frame.height == 300)
        // 세로 중앙이었다면 (1,200 − 300) / 2 = 450 만큼 내려갔을 것이다. 레이아웃 좌표의 원점은 컬럼 상단이다.
        let hostTop = hosting.view.convert(CGPoint.zero, to: nil).y + hosting.view.safeAreaInsets.top
        #expect(frame.minY - hostTop <= 0.5)

        window.isHidden = true
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
