// Copyright © 2026 leetaek. All rights reserved.

#if DEBUG
import Foundation
import notify
import PencilKit
import UIKit

/// D9 표시 진단. SwiftUI 관찰 구간 밖에서 Store와 화면에 붙은 캔버스를 비교한다.
/// 기본 모드는 읽기와 콘솔 출력만 수행한다. 별도 실험 인자가 있을 때만 명시적인 표시 갱신 명령을 받는다.
@MainActor
final class ChapterCanvasDisplayProbe {
    private weak var controller: ChapterCanvasController?
    private let expected: () -> (revision: Int, data: Data?)
    private let identity = String(UUID().uuidString.prefix(8))
    private var polling: Task<Void, Never>?
    private var expectedRevision = -1
    private var expectedDrawing = PKDrawing()
    private var deliveredRevision = -1
    private var deliveredDrawing = PKDrawing()
    private var completionCount = 0
    private var lastReport = ""
    private var experimentTokens: [String: Int32] = [:]

    init(controller: ChapterCanvasController, expected: @escaping () -> (revision: Int, data: Data?)) {
        self.controller = controller
        self.expected = expected
        print("CanvasDisplay create controller=\(identity)")
        if ProcessInfo.processInfo.arguments.contains("-CanvasDisplayExperiments") {
            for name in ["redraw", "reassign", "clear", "fresh"] {
                var token: Int32 = 0
                guard notify_register_check("kr.co.carve.canvas-probe.\(name)", &token) == NOTIFY_STATUS_OK else { continue }
                var changed: Int32 = 0
                notify_check(token, &changed)
                experimentTokens[name] = token
            }
        }
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.controller != nil, !Task.isCancelled else { return }
                self.sample()
            }
        }
    }

    deinit {
        polling?.cancel()
        for token in experimentTokens.values { notify_cancel(token) }
    }

    /// apply에 전달된 입력 데이터를 세대마다 기록한다.
    func recordApply(revision: Int, data: Data?) {
        guard revision != deliveredRevision else { return }
        deliveredRevision = revision
        deliveredDrawing = Self.decode(data)
        print("CanvasDisplay apply controller=\(identity) rev=\(revision) incoming=\(Self.summary(deliveredDrawing))")
    }

    /// 완료 콜백에는 세대가 없으므로 현재 applied를 완료 세대로 간주하지 않고 횟수만 기록한다.
    func recordRenderCompletion() {
        completionCount += 1
        print("CanvasDisplay finish controller=\(identity) count=\(completionCount) appliedAtCallback=\(controller?.appliedRevision ?? -1)")
    }

    /// Store를 주기적으로 읽어 같은 전체 획 집합끼리 비교한다. 뷰 갱신을 유발하지 않는다.
    private func sample() {
        guard let controller, let view = controller.viewIfLoaded else { return }
        for (name, token) in experimentTokens {
            var changed: Int32 = 0
            if notify_check(token, &changed) == NOTIFY_STATUS_OK, changed != 0 {
                print("CanvasDisplay experiment controller=\(identity) name=\(name)")
                controller.runDisplayExperiment(name)
            }
        }
        let current = expected()
        if current.revision != expectedRevision {
            expectedRevision = current.revision
            expectedDrawing = Self.decode(current.data)
        }
        let canvas = controller.canvas
        let actual = canvas.drawing
        let report = "controller=\(identity) attached=\(view.window != nil) "
            + "store=\(expectedRevision) delivered=\(deliveredRevision) applied=\(controller.appliedRevision) finish=\(completionCount) "
            + "expected=\(Self.summary(expectedDrawing)) canvas=\(Self.summary(actual)) "
            + "storeDiff=\(Self.differences(expectedDrawing, actual)) deliveredDiff=\(Self.differences(deliveredDrawing, actual)) "
            + "frame=\(canvas.frame) bounds=\(canvas.bounds) size=\(canvas.contentSize) "
            + "offset=\(canvas.contentOffset) inset=\(canvas.adjustedContentInset) zoom=\(canvas.zoomScale) "
            + "transform=\(canvas.transform) screenInk=\(canvas.convert(actual.bounds, to: view.window))"
        guard report != lastReport else { return }
        lastReport = report
        print("CanvasDisplay sample \(report)")
        print("CanvasDisplay tree \(Self.tree(canvas, depth: 0))")
    }

    private static func decode(_ data: Data?) -> PKDrawing {
        guard let data, let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    private static func summary(_ drawing: PKDrawing) -> String {
        "n\(drawing.strokes.count):\(drawing.bounds)"
    }

    /// 합성물과 실제 캔버스에서 같은 순서의 획을 비교한다. legacy만의 bounds와 비교하지 않는다.
    private static func differences(_ expected: PKDrawing, _ actual: PKDrawing) -> String {
        guard expected.strokes.count == actual.strokes.count else { return "count" }
        let mismatches = zip(expected.strokes, actual.strokes).enumerated().compactMap { index, pair -> String? in
            let (left, right) = pair
            guard left.renderBounds != right.renderBounds || left.transform != right.transform
                || left.randomSeed != right.randomSeed || left.path.count != right.path.count else { return nil }
            return "\(index):\(left.renderBounds)→\(right.renderBounds)"
        }
        return mismatches.isEmpty ? "0" : mismatches.prefix(4).joined(separator: ";")
    }

    /// 공개 UIView 프로퍼티만 읽으며 내부 뷰를 변경하거나 비공개 셀렉터를 호출하지 않는다.
    private static func tree(_ view: UIView, depth: Int) -> String {
        guard depth < 4 else { return "" }
        let current = "\(type(of: view)):frame=\(view.frame),bounds=\(view.bounds),transform=\(view.transform)"
        return current + "[" + view.subviews.map { tree($0, depth: depth + 1) }.joined(separator: "|") + "]"
    }
}
#endif
