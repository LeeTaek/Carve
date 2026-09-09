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

/// 폭이 좁아지면 세로로 길어지는 컬럼 — **텍스트 줄바꿈의 성질만** 재현한다 (회전 시퀀스용).
///
/// 실제 절 행은 폭이 줄면 줄 수가 늘어 컬럼이 길어진다. 그 관계를 `면적 / 폭` 으로 모델링하면
/// 회전을 폭 변경만으로 태울 수 있다 — 시뮬레이터에 회전 명령이 없고(`simctl ui` 에 orientation 없음),
/// 실기기 회전은 D9 H-4 에서만 볼 수 있기 때문이다.
private struct WidthDrivenHeightColumn: Layout {
    let area: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let width = proposal.width, width > 0 else { return .zero }
        return CGSize(width: width, height: (area / width).rounded())
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
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
        func setColumn(_ column: some View, chapter: BibleChapter? = BibleChapter(title: .genesis, chapter: 1)) {
            let hosted = ChapterCanvasView.hostedColumn(AnyView(column)) { [unowned self] height in
                self.controller.setColumnHeight(height)
            }
            controller.setColumn(hosted, chapter: chapter)
        }

        /// 회전을 폭 변경으로 재현한다 — 창과 컨트롤러 뷰를 함께 바꾼다 (`viewDidLayoutSubviews` 의 `lastBounds` 경로를 태운다).
        @MainActor
        func resize(to size: CGSize) {
            let frame = CGRect(origin: .zero, size: size)
            window?.frame = frame
            controller.view.frame = frame
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
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
                   scroll: ChapterCanvasFeature.State.ScrollRequest? = nil,
                   tool: PKTool = PKInkingTool(.pen), drawingPolicy: PKCanvasViewDrawingPolicy = .anyInput) {
            controller.apply(ChapterCanvasController.Configuration(
                renderedData: data, renderedRevision: revision, isInputEnabled: true,
                tool: tool, drawingPolicy: drawingPolicy, topInset: topInset,
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

    @Test("회전(폭 A→B→A) 왕복 뒤 컬럼 기하가 A 로 정확히 돌아온다 — 낡은 폭·높이가 남지 않는다")
    func rotationRoundTripRestoresColumnGeometry() async throws {
        let harness = Harness(inWindow: true)
        harness.setColumn(WidthDrivenHeightColumn(area: 480_000) { Color.clear })

        // ── 세로 800 × 1,200 → 컬럼 이상적 높이 480,000 / 800 = 600 ──
        harness.resize(to: CGSize(width: 800, height: 1_200))
        #expect(await harness.settleContentFrameHeight(expecting: 600) == 600)
        let portrait = harness.controller.canvas.contentFrame
        #expect(portrait == CGRect(x: 0, y: 0, width: 800, height: 600))

        // ── 가로 1,200 × 800 → 480,000 / 1,200 = 400 ──
        harness.resize(to: CGSize(width: 1_200, height: 800))
        #expect(await harness.settleContentFrameHeight(expecting: 400) == 400)
        #expect(harness.controller.canvas.contentFrame == CGRect(x: 0, y: 0, width: 1_200, height: 400))

        // ── 다시 세로 — 낡은 값이 남으면 여기서 갈린다 (D9 H-4 실기기 관측) ──
        harness.resize(to: CGSize(width: 800, height: 1_200))
        #expect(await harness.settleContentFrameHeight(expecting: 600) == 600)
        #expect(harness.controller.canvas.contentFrame == portrait)
        #expect(harness.controller.canvas.contentSize.width == 800)
        harness.teardown()
    }


    // MARK: 회전 뒤 재합성 표시 (D9 — 합성물이 캔버스까지 가는가)

    /// 지정한 content x 범위에 획 하나를 놓은 drawing 데이터.
    private func inkData(minX: CGFloat, maxX: CGFloat) -> Data {
        PKDrawing(strokes: [
            OwnershipTestSupport.stroke(
                from: CGPoint(x: minX, y: 100), to: CGPoint(x: maxX, y: 100),
                seed: UInt32(minX), creationTime: Double(minX)
            )
        ]).dataRepresentation()
    }

    /// `canvas.drawing` 의 x 범위 (획 굵기 때문에 bounds 는 양쪽으로 조금 넓다).
    private func inkRangeX(_ canvas: PKCanvasView) -> ClosedRange<CGFloat>? {
        let bounds = canvas.drawing.bounds
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        return bounds.minX...bounds.maxX
    }

    @Test("회전 왕복 중 revision 이 오른 합성물은 캔버스에 실제로 적용된다 — 이전 방향의 렌더가 남지 않는다 (D9)")
    func rotationRoundTripAppliesLatestComposition() async throws {
        let harness = Harness(inWindow: true)
        harness.setColumn(WidthDrivenHeightColumn(area: 480_000) { Color.clear })

        let landscapeInk = inkData(minX: 573, maxX: 728)
        let portraitInk = inkData(minX: 383, maxX: 538)
        let canvas = harness.controller.canvas

        // ① 가로 진입 — rev 2, 잉크 x[573…728].
        harness.resize(to: CGSize(width: 1_200, height: 800))
        _ = await harness.settleContentFrameHeight(expecting: 400)
        harness.apply(revision: 2, data: landscapeInk)
        let first = try #require(inkRangeX(canvas))
        #expect(abs(first.lowerBound - 573) < 5)

        // ② 세로로 회전 — 재합성 rev 3, 잉크 x[383…538].
        harness.resize(to: CGSize(width: 800, height: 1_200))
        _ = await harness.settleContentFrameHeight(expecting: 600)
        harness.apply(revision: 3, data: portraitInk)
        let rotated = try #require(inkRangeX(canvas))
        #expect(abs(rotated.lowerBound - 383) < 5)

        // ③ 다시 가로 — 재합성 rev 4. 여기서 ② 의 잉크가 남으면 결함이다 (실기기 D9 관측).
        harness.resize(to: CGSize(width: 1_200, height: 800))
        _ = await harness.settleContentFrameHeight(expecting: 400)
        harness.apply(revision: 4, data: landscapeInk)
        let restored = try #require(inkRangeX(canvas))
        #expect(abs(restored.lowerBound - 573) < 5)
        #expect(harness.controller.appliedRevision == 4)
        harness.teardown()
    }

    @Test("합성 적용은 뷰 갱신 도중에 액션을 내보내지 않는다 — undo 상태 보고도 다음 턴으로 미룬다 (D9)")
    func applyDoesNotEmitEventsDuringViewUpdate() async throws {
        let harness = Harness()
        harness.apply(revision: 1)
        harness.events.removeAll()

        // `apply` 는 `updateUIViewController` 안에서 불린다. 여기서 store 로 액션이 들어가면
        // SwiftUI 가 **갱신 도중 상태 변경**을 보게 되고, 그 턴에 예약된 다른 갱신이 함께 무너질 수 있다.
        // `flushUnreportedEdit` 이 이미 같은 이유로 이벤트를 다음 턴에 보낸다 — undo 상태 보고만 예외였다.
        harness.apply(revision: 2, data: inkData(minX: 573, maxX: 728))
        #expect(harness.events.isEmpty)

        // 미루기만 할 뿐 유실되지는 않는다.
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.events.contains { if case .undoStateChanged = $0 { return true } else { return false } })
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

extension ChapterCanvasControllerTesting {

    // MARK: 표시용 획 재구성 (D9 H — 회전 뒤 이전 렌더가 남는 결함의 정식 수정)

    /// 다양한 잉크·변환·마스크가 섞인 표본. 지우개 조각은 실제 앱 블롭(`EraserFixture`)에서 가져온다 —
    /// `mask` / `maskedPathRanges` 를 합성으로 만들면 PencilKit 이 실제로 만드는 형태와 다를 수 있다.
    private func mixedInkStrokes() throws -> [PKStroke] {
        let erased = try #require(Data(base64Encoded: EraserFixture.afterPartialErase))
        var strokes = try PKDrawing(data: erased).strokes
        #expect(strokes.contains { $0.mask != nil })
        let inks: [PKInk] = [
            PKInk(.pen, color: .black), PKInk(.pencil, color: .red), PKInk(.marker, color: .blue),
            PKInk(.monoline, color: .green), PKInk(.fountainPen, color: .purple),
            PKInk(.watercolor, color: .orange), PKInk(.crayon, color: .brown)
        ]
        for (index, ink) in inks.enumerated() {
            var stroke = OwnershipTestSupport.stroke(
                from: CGPoint(x: 10, y: 200 + CGFloat(index) * 20),
                to: CGPoint(x: 90, y: 200 + CGFloat(index) * 20),
                seed: UInt32(7_000 + index), creationTime: 1_700_000_000 + Double(index),
                transform: CGAffineTransform(translationX: CGFloat(index) * 3, y: 1.5)
            )
            stroke.ink = ink
            strokes.append(stroke)
        }
        return strokes
    }

    @Test("표시용 획 재구성은 잉크·변환·마스크·control point·seed·생성 시각과 소유권 식별자를 전부 보존한다 (D9 H)")
    func freshDisplayStrokesPreserveEveryPublicStrokeProperty() throws {
        let source = PKDrawing(strokes: try mixedInkStrokes())
        let fresh = ChapterCanvasController.freshDrawingForDisplay(source)

        #expect(fresh.strokes.count == source.strokes.count)
        #expect(fresh.bounds == source.bounds)
        for (index, pair) in zip(source.strokes, fresh.strokes).enumerated() {
            let (before, after) = pair
            #expect(after.ink.inkType == before.ink.inkType, "잉크 종류 \(index)")
            #expect(after.ink.color == before.ink.color, "잉크 색 \(index)")
            #expect(after.transform == before.transform, "변환 \(index)")
            #expect(after.randomSeed == before.randomSeed, "seed \(index)")
            #expect(after.renderBounds == before.renderBounds, "renderBounds \(index)")
            #expect(after.requiredContentVersion == before.requiredContentVersion, "contentVersion \(index)")
            // path 는 통째로 넘긴다 — 생성 시각과 control point 가 그대로여야 `StrokeIdentityKey` 가 살아남는다.
            #expect(after.path.creationDate == before.path.creationDate, "생성 시각 \(index)")
            #expect(after.path.count == before.path.count, "point 수 \(index)")
            #expect(after.path.map(\.location) == before.path.map(\.location), "point 좌표 \(index)")
            // 마스크는 있음/없음과 가시 구간이 같아야 한다 (지우개 조각, §7-2 S1-5).
            // 가시 구간은 마스크에서 **파생**되는 값이라 재구성 시 재계산되며 실측 오차가 1e-3 미만 남는다
            // (아래 `maskedStrokeRebuildIsAFixedPoint` 가 그 크기와 저장 영향을 따로 고정한다).
            #expect((after.mask == nil) == (before.mask == nil), "마스크 유무 \(index)")
            #expect(after.maskedPathRanges.count == before.maskedPathRanges.count, "가시 구간 수 \(index)")
            for (lhs, rhs) in zip(after.maskedPathRanges, before.maskedPathRanges) {
                #expect(abs(lhs.lowerBound - rhs.lowerBound) < 0.001, "가시 구간 하한 \(index)")
                #expect(abs(lhs.upperBound - rhs.upperBound) < 0.001, "가시 구간 상한 \(index)")
            }
        }
        // 소유권 승계 키 — 지우개 조각은 같은 키를 공유하므로 집합이 아니라 순서 그대로 비교한다 (§7-2).
        #expect(fresh.strokes.map { StrokeIdentityKey(stroke: $0) } == source.strokes.map { StrokeIdentityKey(stroke: $0) })
        // 마스크 없는 획은 dirty 판정 키까지 완전히 같다 — 재구성이 "내용이 바뀌었다"로 읽히지 않는다 (§8-2).
        let plain = zip(source.strokes, fresh.strokes).filter { $0.0.mask == nil }
        #expect(!plain.isEmpty)
        #expect(plain.map { StrokeContentSignature(stroke: $0.1) } == plain.map { StrokeContentSignature(stroke: $0.0) })
    }

    @Test("지우개 조각을 재구성하면 마스크는 같고 파생 가시 구간만 재계산된다 — 그리고 그 결과는 고정점이다 (D9 H)")
    func maskedStrokeRebuildIsAFixedPoint() throws {
        let erased = try #require(Data(base64Encoded: EraserFixture.afterPartialErase))
        let stored = try PKDrawing(data: erased)
        #expect(stored.strokes.filter { $0.mask != nil }.count == 2)

        // ① 저장된 값을 재구성하면 가시 구간이 미세하게 달라진다 — `StrokeContentSignature` 는 반올림하지 않으므로
        //    그 절이 한 번 dirty 로 잡힌다 (§7-2 는 반올림을 금지한다 — D7 재발 방지).
        let rebuilt = try PKDrawing(data: ChapterCanvasController.freshDrawingForDisplay(stored).dataRepresentation())
        #expect(rebuilt.strokes.map { StrokeIdentityKey(stroke: $0) } == stored.strokes.map { StrokeIdentityKey(stroke: $0) })
        for (lhs, rhs) in zip(rebuilt.strokes, stored.strokes) {
            #expect(lhs.renderBounds == rhs.renderBounds)
            #expect((lhs.mask == nil) == (rhs.mask == nil))
        }

        // ② **한 번 저장되면 반복되지 않는다.** 재구성 → 직렬화 → 디코드 → 재구성이 같은 값을 준다.
        let again = try PKDrawing(data: ChapterCanvasController.freshDrawingForDisplay(rebuilt).dataRepresentation())
        #expect(again.strokes.map(StrokeContentSignature.init) == rebuilt.strokes.map(StrokeContentSignature.init))
    }

    @Test("빈 drawing 과 디코드 실패는 재구성을 거쳐도 기존대로 빈 캔버스가 된다")
    func emptyAndUndecodableDataStillClearTheCanvas() throws {
        // helper 자체는 빈 입력을 그대로 돌려준다 — 새 획을 만들지 않는다.
        #expect(ChapterCanvasController.freshDrawingForDisplay(PKDrawing()).strokes.isEmpty)

        let harness = Harness()
        let canvas = harness.controller.canvas
        harness.apply(revision: 1, data: inkData(minX: 573, maxX: 728))
        #expect(canvas.drawing.strokes.count == 1)

        harness.apply(revision: 2, data: Data())               // 빈 Data
        #expect(canvas.drawing.strokes.isEmpty)

        harness.apply(revision: 3, data: inkData(minX: 573, maxX: 728))
        #expect(canvas.drawing.strokes.count == 1)
        harness.apply(revision: 4, data: Data("깨진 블롭".utf8))   // 디코드 실패
        #expect(canvas.drawing.strokes.isEmpty)

        harness.apply(revision: 5, data: inkData(minX: 573, maxX: 728))
        #expect(canvas.drawing.strokes.count == 1)
        harness.apply(revision: 6, data: nil)                  // 아직 합성 전
        #expect(canvas.drawing.strokes.isEmpty)
    }

    @Test("회전 직전 미보고 획은 이전 세대로 flush 되고, 재구성 교체는 저장 mutation 을 만들지 않는다 (D9 H)")
    func rotationFlushesPreviousGenerationAndRebuildMakesNoMutation() async throws {
        let harness = Harness(inWindow: true)
        defer { harness.teardown() }
        harness.setColumn(WidthDrivenHeightColumn(area: 480_000) { Color.clear })
        harness.resize(to: CGSize(width: 1_200, height: 800))
        _ = await harness.settleContentFrameHeight(expecting: 400)

        let landscapeInk = inkData(minX: 573, maxX: 728)
        let portraitInk = inkData(minX: 383, maxX: 538)
        let canvas = harness.controller.canvas
        harness.apply(revision: 2, data: landscapeInk)

        // 회전 직전에 그은 획. trailing 보고 전에 재합성이 들어온다.
        harness.controller.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [stroke(y: 300)])
        harness.controller.canvasViewDrawingDidChange(canvas)
        harness.controller.canvasViewDidEndUsingTool(canvas)
        harness.events.removeAll()

        harness.resize(to: CGSize(width: 800, height: 1_200))
        _ = await harness.settleContentFrameHeight(expecting: 600)
        harness.apply(revision: 3, data: portraitInk)
        try await Task.sleep(for: .milliseconds(50))

        // ① 미보고 획은 **이전 세대(2)** 로, 교체 전 두 획을 담아 한 번만 보고된다.
        #expect(harness.editEndedGenerations == [2])
        guard case .editEnded(let snapshot)? = harness.events.first(where: { if case .editEnded = $0 { return true } else { return false } }) else {
            Issue.record("editEnded 가 없다"); return
        }
        #expect(try PKDrawing(data: snapshot.drawingData).strokes.count == 2)

        // ② 프로그램 교체는 새 편집을 만들지 않는다 — trailing 창이 다 지나도 보고가 늘지 않는다.
        #expect(!harness.controller.hasUnreportedChange)
        try await Task.sleep(for: .milliseconds(450))
        #expect(harness.editEndedGenerations == [2])

        // ③ 캔버스에 들어간 것은 새 세대의 합성물이고, 재구성이 소유권 키를 바꾸지 않았다.
        let expected = try PKDrawing(data: portraitInk)
        #expect(canvas.drawing.strokes.map { StrokeIdentityKey(stroke: $0) }
                == expected.strokes.map { StrokeIdentityKey(stroke: $0) })

        // ④ 재구성한 표시 내용을 그대로 저장 계산에 넣으면 mutation 이 없다 — 회전이 DB 쓰기를 만들지 않는다 (§8-2).
        let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)
        let codec = DrawingCodec()
        let composed = codec.compose(
            snapshots: [Self.storedRow(verse: 1, seed: 11), Self.storedRow(verse: 2, seed: 12)],
            layout: layout, columnOrigin: .zero
        )
        #expect(try PKDrawing(data: composed.data).strokes.count == 2)   // 표본이 비어 있지 않다
        let rebuilt = ChapterCanvasController.freshDrawingForDisplay(try PKDrawing(data: composed.data))
        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: rebuilt.dataRepresentation(),
            context: DrawingEditContext(layout: layout, columnOrigin: .zero, activeRowIDs: composed.activeRowIDs)
        )
        #expect(result.mutations.isEmpty)
        #expect(result.ownership.map == composed.ownership.map)
    }

    @Test("지우개 조각이 있는 절은 재구성 뒤 저장 계산에서 한 번만 dirty 로 잡히고 좌표·소유권은 그대로다 (D9 H)")
    func maskedVerseIsDirtyOnlyOnceAfterRebuild() throws {
        let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)
        let codec = DrawingCodec()
        let erased = try #require(Data(base64Encoded: EraserFixture.afterPartialErase))
        let row = VerseDrawingSnapshot(
            verse: 1, rowID: BibleDrawingRowID(raw: "erased-1"), isPresent: true,
            updateDate: Date(timeIntervalSince1970: 1), lineData: erased, drawingVersion: 1, metadata: nil
        )
        let composed = codec.compose(snapshots: [row], layout: layout, columnOrigin: .zero)
        let context = DrawingEditContext(layout: layout, columnOrigin: .zero, activeRowIDs: composed.activeRowIDs)
        let displayed = ChapterCanvasController.freshDrawingForDisplay(try PKDrawing(data: composed.data)).dataRepresentation()

        // ① 파생 가시 구간이 재계산되므로 그 절이 한 번 dirty 로 잡힌다.
        //    `StrokeContentSignature` 는 반올림을 금지하므로(§7-2 — D7 재발 방지) 이것이 설계상 정상 동작이다.
        let first = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership, afterData: displayed, context: context
        )
        #expect(first.mutations.count == 1)
        // 다시 저장돼도 획 수·좌표·소유권은 그대로다 — 데이터가 변질되지 않는다.
        guard case .replace(let verse, let rowID, let saved, let savedMetadata) = try #require(first.mutations.first) else {
            Issue.record("replace 가 아니다"); return
        }
        #expect(verse == 1)
        let before = try PKDrawing(data: composed.data)
        let after = try PKDrawing(data: saved)
        #expect(after.strokes.count == before.strokes.count)
        #expect(after.strokes.map { StrokeIdentityKey(stroke: $0) } == before.strokes.map { StrokeIdentityKey(stroke: $0) })
        #expect(first.ownership.map == composed.ownership.map)

        // ② 되풀이되지 않는다 — 그 저장 결과로 **다시 합성**해서 또 재구성해도 mutation 이 없다.
        //    회전할 때마다 같은 절을 다시 쓰는 것이 아니라, 재구성 도입 뒤 한 번으로 끝난다.
        let stored = VerseDrawingSnapshot(
            verse: verse, rowID: rowID, isPresent: true, updateDate: Date(timeIntervalSince1970: 2),
            lineData: saved, drawingVersion: 3, metadata: savedMetadata
        )
        let recomposed = codec.compose(snapshots: [stored], layout: layout, columnOrigin: .zero)
        let redisplayed = ChapterCanvasController.freshDrawingForDisplay(try PKDrawing(data: recomposed.data)).dataRepresentation()
        let second = codec.mutations(
            beforeData: recomposed.data, beforeOwnership: recomposed.ownership, afterData: redisplayed,
            context: DrawingEditContext(layout: layout, columnOrigin: .zero, activeRowIDs: recomposed.activeRowIDs)
        )
        #expect(second.mutations.isEmpty)
    }

    /// 첫 밑줄 5pt 위에 획 하나를 담은 `drawingVersion == 3` 행.
    private static func storedRow(verse: Int, seed: UInt32) -> VerseDrawingSnapshot {
        let stroke = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: -5), to: CGPoint(x: 20, y: -5),
            seed: seed, creationTime: 1_700_000_000 + Double(seed)
        )
        return VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: "row-\(verse)"), isPresent: true,
            updateDate: Date(timeIntervalSince1970: 1),
            lineData: PKDrawing(strokes: [stroke]).dataRepresentation(), drawingVersion: 3,
            metadata: DrawingLayoutMetadata(
                baseWritingWidth: 320, baseWritingHeight: 30, baseUnderlineAnchors: [0], layoutSignature: "old"
            )
        )
    }
}

#if DEBUG
extension ChapterCanvasControllerTesting {
    @Test("같은 revision 의 도구·정책·인셋·스크롤 갱신은 표시를 교체하지 않는다 — 재구성도 undo 초기화도 없다 (D9 H)")
    func sameRevisionUpdatesDoNotRebuildDisplayOrClearUndo() async throws {
        let harness = Harness()
        let canvas = harness.controller.canvas
        harness.apply(revision: 2, data: inkData(minX: 573, maxX: 728))
        #expect(harness.controller.freshDisplayRebuildCount == 1)

        // 사용자가 획 하나를 더 그었고 아직 보고 전이다.
        harness.controller.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [stroke(y: 300)])
        harness.controller.canvasViewDrawingDidChange(canvas)
        harness.controller.canvasViewDidEndUsingTool(canvas)
        #expect(harness.controller.hasUnreportedChange)
        harness.events.removeAll()

        // 같은 세대에서 도구·정책·헤더 높이·스크롤만 바뀐다 (팔레트 전환, 헤더 실측 도착, 스크롤).
        harness.apply(revision: 2, data: inkData(minX: 573, maxX: 728), topInset: 120,
                      tool: PKEraserTool(.bitmap), drawingPolicy: .pencilOnly)
        harness.apply(revision: 2, data: inkData(minX: 573, maxX: 728), topInset: 120,
                      layout: OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30),
                      scroll: ChapterCanvasFeature.State.ScrollRequest(verse: 2, token: 9),
                      tool: PKInkingTool(.marker), drawingPolicy: .anyInput)
        harness.controller.scrollViewDidScroll(canvas)

        // 표시는 그대로다 — 재구성이 돌지 않았고 사용자의 미보고 획도 살아 있다.
        // undo 초기화(`undoManager.removeAllActions()`)는 아래 계수기가 세는 교체 경로 **안**에 있으므로,
        // 계수기가 그대로면 undo 스택도 건드리지 않았다는 뜻이다 (하네스의 응답자 사슬에는 undoManager 가 없어 직접 못 읽는다).
        #expect(harness.controller.freshDisplayRebuildCount == 1)
        #expect(canvas.drawing.strokes.count == 2)
        #expect(harness.controller.hasUnreportedChange)
        // 요청받은 설정은 반영된다 — "아무 일도 안 한다" 가 아니라 "표시만 안 바꾼다" 이다.
        #expect(canvas.tool is PKInkingTool)
        #expect(canvas.contentInset.top == 120)

        // 세대가 실제로 오르면 그때 교체하고 undo 를 비운다 (§9-5).
        harness.apply(revision: 3, data: inkData(minX: 383, maxX: 538), topInset: 120)
        #expect(harness.controller.freshDisplayRebuildCount == 2)
        #expect(canvas.drawing.strokes.count == 1)
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("표시 진단 실험은 획 좌표·소유권 식별자를 보존하고 편집을 보고하지 않는다")
    func displayExperimentsDoNotSaveOrChangeStrokeGeometry() async throws {
        let harness = Harness(inWindow: true)
        defer { harness.teardown() }
        harness.apply(revision: 2, data: inkData(minX: 573, maxX: 728))
        try await Task.sleep(for: .milliseconds(400))
        let baseline = try #require(harness.controller.canvas.drawing.strokes.first)
        harness.events.removeAll()

        for name in ["redraw", "reassign", "clear", "fresh"] {
            harness.controller.runDisplayExperiment(name)
            try await Task.sleep(for: .milliseconds(400))
            let drawing = harness.controller.canvas.drawing
            let stroke = try #require(drawing.strokes.first)
            #expect(drawing.strokes.count == 1)
            #expect(stroke.renderBounds == baseline.renderBounds)
            #expect(stroke.transform == baseline.transform)
            #expect(stroke.randomSeed == baseline.randomSeed)
            #expect(stroke.path.creationDate == baseline.path.creationDate)
            #expect(stroke.path.map(\.location) == baseline.path.map(\.location))
            #expect(harness.controller.appliedRevision == 2)
            #expect(!harness.controller.hasUnreportedChange)
            #expect(harness.events.isEmpty)
        }
    }

    // MARK: R26 — 장 전환에서 이전 컬럼을 놓는다

    /// 메모리 해제 자체는 단위 테스트로 볼 수 없다. 대신 **결정**을 고정한다 —
    /// 실기기 귀속(2026-09-09)에서 컬럼만 비우자 757 MB 가 풀렸고, 잉크는 16 MB 였다.
    @MainActor
    @Test("같은 장으로 컬럼을 다시 넣으면 이전 컬럼을 놓지 않는다 — 매번 놓으면 깜빡인다 (R26)")
    func sameChapterKeepsHostedColumn() {
        let harness = Harness()
        let chapter = BibleChapter(title: .genesis, chapter: 1)
        harness.setColumn(Color.clear, chapter: chapter)
        harness.setColumn(Color.clear, chapter: chapter)
        harness.setColumn(Color.clear, chapter: chapter)
        #expect(harness.controller.columnReleaseCount == 0)
    }

    @MainActor
    @Test("장이 바뀌면 새 컬럼을 넣기 전에 이전 컬럼을 놓는다 (R26)")
    func chapterChangeReleasesPreviousColumn() {
        let harness = Harness()
        harness.setColumn(Color.clear, chapter: BibleChapter(title: .psalms, chapter: 119))
        #expect(harness.controller.columnReleaseCount == 0)   // 첫 장에는 놓을 것이 없다

        harness.setColumn(Color.clear, chapter: BibleChapter(title: .psalms, chapter: 120))
        #expect(harness.controller.columnReleaseCount == 1)

        harness.setColumn(Color.clear, chapter: BibleChapter(title: .psalms, chapter: 121))
        #expect(harness.controller.columnReleaseCount == 2)
    }

}
#endif
