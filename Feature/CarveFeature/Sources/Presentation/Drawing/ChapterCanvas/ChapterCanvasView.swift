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
            isInputEnabled = state.isInputEnabled
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
        return controller
    }

    func updateUIViewController(_ controller: ChapterCanvasController, context: Context) {
        context.coordinator.store = store
        context.coordinator.onScroll = onScroll

        controller.setColumn(AnyView(
            column
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { [weak controller] height in
                    controller?.setColumnHeight(height)
                }
                // 호스트 frame 이 컬럼보다 커도 컬럼은 상단에 붙는다 — 레이아웃 좌표의 원점은 컬럼 상단이다 (짧은 장의 세로 중앙 배치 금지).
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        ))
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
