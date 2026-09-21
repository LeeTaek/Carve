// Copyright © 2026 leetaek. All rights reserved.

#if DEBUG
import Foundation
import PencilKit
import UIKit

/// 올가미 실측 계측 (`-LassoProbe`). [올가미 설계](../../../../../docs/lasso-design.md) §5 의 L-1 ~ L-6 을 한 번의 조작으로 읽는다.
///
/// **읽기만 한다** — 도구도 `drawing` 도 바꾸지 않고, 액션도 보내지 않는다. 출력은 `print` 이므로
/// `xcrun simctl launch --console-pty` 로 받는다 (시뮬레이터에서 `Log.debug` 는 `log show` 에 남지 않는다 — AGENTS.md).
@MainActor
final class ChapterCanvasLassoProbe {
    static let launchArgument = "-LassoProbe"

    private weak var canvas: PKCanvasView?
    /// 직전 기록의 획 요약. 새로 생긴 획(`*`)과 사라진 획(`-`)을 표시하는 데만 쓴다.
    private var previous: [String] = []
    private var step = 0
    private var toolAssignments = 0

    init(canvas: PKCanvasView) {
        self.canvas = canvas
        print("LassoProbe ▸ start")
    }

    /// delegate 사건마다 캔버스의 지금 상태를 찍는다.
    func record(_ event: String) {
        guard let canvas else { return }
        step += 1
        let strokes = canvas.drawing.strokes
        let summaries = strokes.map(Self.summary)
        print("""
        LassoProbe ▸ #\(step) \(event) tool=\(String(describing: type(of: canvas.tool))) \
        strokes=\(strokes.count) canUndo=\(canvas.undoManager?.canUndo ?? false) \
        canRedo=\(canvas.undoManager?.canRedo ?? false) menus=\(Self.editMenuCount(in: canvas))
        """)
        for (index, summary) in summaries.enumerated() {
            // 이전 기록에 없던 획이면 `*` — 올가미가 획을 쪼개는지(L-1) 여기서 보인다.
            print("LassoProbe ▸   [\(index)]\(previous.contains(summary) ? " " : "*") \(summary)")
        }
        for gone in previous where !summaries.contains(gone) {
            print("LassoProbe ▸   (-)  \(gone)")
        }
        previous = summaries
    }

    /// `apply` 가 도구를 다시 넣는 시점 (L-6 — 선택 도중의 재대입이 선택을 지우는지).
    /// 올가미일 때만 찍는다. 그 밖의 도구는 재대입이 아무 상태도 갖지 않아 볼 것이 없다.
    func recordToolAssignment(_ tool: PKTool) {
        guard tool is PKLassoTool else { return }
        toolAssignments += 1
        print("LassoProbe ▸ tool-assign #\(toolAssignments) (PKLassoTool)")
    }

    /// 획 하나의 공개 속성 요약.
    ///
    /// `StrokeIdentityKey` 의 세 성분(`randomSeed` · `path.creationDate` · `path.count`)과
    /// 소유권 앵커(첫 control point + `transform`), 그리고 마스크 유무를 함께 본다 —
    /// 설계 §7-2 가 identity 와 content signature 를 가르는 기준이 그대로 여기 있다.
    private static func summary(_ stroke: PKStroke) -> String {
        let local = stroke.path.first?.location ?? .zero
        let anchor = local.applying(stroke.transform)
        let transform = stroke.transform
        return String(
            format: "seed=%u created=%.3f pts=%d local=(%.2f,%.2f) anchor=(%.2f,%.2f) "
                + "t=[%.4f %.4f %.4f %.4f %.2f %.2f] mask=%@ bounds=%@",
            stroke.randomSeed,
            stroke.path.creationDate.timeIntervalSince1970,
            stroke.path.count,
            local.x, local.y,
            anchor.x, anchor.y,
            transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty,
            stroke.mask == nil ? "nil" : "set",
            NSCoder.string(for: stroke.renderBounds)
        )
    }

    /// 캔버스 하위 뷰에 남아 있는 편집 · 컨텍스트 메뉴 수 (L-5 — R25 억제가 올가미에서도 유지되는지).
    private static func editMenuCount(in canvas: PKCanvasView) -> Int {
        canvas.subviews.reduce(0) { count, subview in
            count + subview.interactions.filter {
                $0 is UIEditMenuInteraction || $0 is UIContextMenuInteraction
            }.count
        }
    }
}
#endif
