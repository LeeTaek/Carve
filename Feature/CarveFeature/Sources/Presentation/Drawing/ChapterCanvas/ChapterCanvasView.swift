//
//  ChapterCanvasView.swift
//  CarveFeature
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import PencilKit
import SwiftUI

import ComposableArchitecture

/// 단일 Canvas 의 SwiftUI 진입점. `ChapterCanvasFeature` 상태를 `ChapterCanvasController` 에 옮기고 사건을 액션으로 돌려보낸다.
///
/// 텍스트 컬럼(`column`)은 호출부가 만든 SwiftUI 뷰다 — Phase 2 의 절 행(`SentencesWithDrawingView`, 캔버스 없음)을 그대로 쓴다.
/// 컬럼의 실측(밑줄·소제목·frame)은 호출부의 수집기를 통해 `CarveDetailFeature` 로 가고, 거기서 `ChapterLayout` 이 완성되면
/// `layoutCompleted` 로 이 Feature 에 들어온다. 즉 **측정 파이프라인은 N-Canvas 경로와 같다.**
struct ChapterCanvasView: UIViewControllerRepresentable {
    /// 부모가 관찰해서 넘기는 표시 상태. 표현 가능 뷰 안에서 store 를 읽지 않고 값으로 받아,
    /// 부모 body 가 다시 평가될 때 `updateUIViewController` 가 확실히 불리게 한다.
    struct Display: Equatable {
        var renderedData: Data?
        var renderedRevision: Int
        var isInputEnabled: Bool
        var undoRequestVersion: Int
        var redoRequestVersion: Int
        var scrollRequest: ChapterCanvasFeature.State.ScrollRequest?
        var layout: ChapterLayout?

        init(_ state: ChapterCanvasFeature.State) {
            renderedData = state.renderedData
            renderedRevision = state.renderedRevision
            // 새 획 입력만 여는 게이트다 — Δ 안전망(§14)이 여기 하나에만 걸린다. 합성·저장은 이 값을 보지 않는다.
            isInputEnabled = state.isDrawingInputEnabled
            undoRequestVersion = state.undoRequestVersion
            redoRequestVersion = state.redoRequestVersion
            scrollRequest = state.scrollRequest
            layout = state.layout
        }
    }

    /// 액션을 보내는 데만 쓴다.
    let store: StoreOf<ChapterCanvasFeature>
    let display: Display
    /// 헤더 높이. 콘텐츠 좌표를 건드리지 않고 `contentInset.top` 으로 비운다.
    let topInset: CGFloat
    let column: AnyView
    /// 스크롤 (이전, 현재) 콘텐츠 상단 y — 헤더 애니메이션용 (SwiftUI `offsetY` 와 같은 의미).
    let onScroll: (CGFloat, CGFloat) -> Void

    @Shared(.appStorage("pencilConfig")) private var pencilConfig: PencilPalatte = .initialState
    @Shared(.appStorage("allowFingerDrawing")) private var allowFingerDrawing: Bool = false

    func makeUIViewController(context: Context) -> ChapterCanvasController {
        let controller = ChapterCanvasController()
        controller.onEvent = { [coordinator = context.coordinator] event in
            coordinator.handle(event)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(ChapterCanvasMemoryProbe.launchArgument) {
            controller.memoryProbe = ChapterCanvasMemoryProbe()
        }
        if ProcessInfo.processInfo.arguments.contains("-CanvasDisplayProbe") {
            controller.displayProbe = ChapterCanvasDisplayProbe(controller: controller) { [store] in
                (store.renderedRevision, store.renderedData)
            }
        }
        #endif
        return controller
    }

    func updateUIViewController(_ controller: ChapterCanvasController, context: Context) {
        context.coordinator.store = store
        context.coordinator.onScroll = onScroll

        controller.setColumn(Self.hostedColumn(column) { [weak controller] height in
            controller?.setColumnHeight(height)
        })
        controller.apply(ChapterCanvasController.Configuration(
            renderedData: display.renderedData,
            renderedRevision: display.renderedRevision,
            isInputEnabled: display.isInputEnabled,
            tool: Self.tool(for: pencilConfig),
            drawingPolicy: allowFingerDrawing ? .anyInput : .pencilOnly,
            topInset: topInset,
            undoRequestVersion: display.undoRequestVersion,
            redoRequestVersion: display.redoRequestVersion,
            scrollRequest: display.scrollRequest,
            layout: display.layout
        ))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, onScroll: onScroll)
    }

    /// 호스트(`ChapterCanvasController` 의 `UIHostingController`)에 넣을 컬럼 조합.
    /// 컨트롤러의 기하 계약(`setColumnHeight` → `contentFrame`)과 한 쌍이라 한곳에 모아 둔다 — 테스트도 같은 조합을 쓴다.
    ///
    /// **`.fixedSize(horizontal: false, vertical: true)` 가 핵심이다.** 호스트 frame 의 높이는 직전에 보고된 `columnHeight` 이고,
    /// 그 값은 장이 바뀐 직후에는 **이전 장(더 긴 장)의 값**이다. 이 고정이 없으면 초과 높이가 컬럼에 그대로 제안되고,
    /// 행 안 밑줄 뷰(`maxHeight: .infinity`)가 세로로 늘어나 컬럼이 제안된 높이만큼 실제로 커진다.
    /// 그러면 다시 잰 높이가 이전 장 값과 같아 `setColumnHeight` 의 `guard` 에 걸려 아무 일도 일어나지 않는다 —
    /// 스스로 빠져나올 수 없는 고정점이다(D9 실기기: 창세기 1장 → 2장 전환 시 마지막 절 1335.78pt 어긋남).
    /// 컬럼이 어떤 제안을 받아도 자기 이상적 높이를 보고하면 다음 측정에서 곧바로 수렴하므로 되먹임 고리가 구조적으로 사라진다.
    ///
    /// 바깥 `.frame(maxHeight: .infinity, alignment: .top)` 은 그대로 둔다 — 호스트가 컬럼보다 커도 컬럼은 상단에 붙어야 한다.
    /// 레이아웃 좌표의 원점이 컬럼 상단이므로 세로 중앙 배치는 곧 좌표 어긋남이다.
    @MainActor
    static func hostedColumn(_ column: AnyView, reportHeight: @escaping (CGFloat) -> Void) -> AnyView {
        AnyView(
            column
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    reportHeight(height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }

    /// 팔레트 설정 → PencilKit 도구. `CanvasView` 와 같은 규칙(monoline = 지우개, §7-4 `.bitmap`).
    private static func tool(for config: PencilPalatte) -> PKTool {
        config.pencilType == .monoline
            ? PKEraserTool(.bitmap)
            : PKInkingTool(config.pencilType, color: config.lineColor.color, width: config.lineWidth)
    }

    @MainActor
    final class Coordinator {
        var store: StoreOf<ChapterCanvasFeature>
        var onScroll: (CGFloat, CGFloat) -> Void

        init(store: StoreOf<ChapterCanvasFeature>, onScroll: @escaping (CGFloat, CGFloat) -> Void) {
            self.store = store
            self.onScroll = onScroll
        }

        func handle(_ event: ChapterCanvasController.Event) {
            switch event {
            case .editBegan:
                store.send(.editBegan)
            case .editEnded(let snapshot):
                store.send(.editEnded(snapshot))
            case .editCancelled:
                store.send(.editCancelled)
            case .undoStateChanged(let canUndo, let canRedo):
                store.send(.undoStateChanged(canUndo: canUndo, canRedo: canRedo))
            case .scrolled(let previous, let current):
                onScroll(previous, current)
            case .historyRequested(let point):
                store.send(.historyRequested(at: point))
            }
        }
    }
}
