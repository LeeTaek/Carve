//
//  CombinedCanvasView.swift
//  CarveFeature
//
//  Created by 이택성 on 11/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Combine
import SwiftUI
import PencilKit
import Domain
import CarveToolkit

import ComposableArchitecture

public struct CombinedCanvasView: UIViewRepresentable {
    public typealias UIViewType = PKCanvasView
    private var store: StoreOf<CombinedCanvasFeature>

    init(store: StoreOf<CombinedCanvasFeature>) {
        self.store = store
    }
    

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas: PKCanvasView = {
            let canvas = PKCanvasView()

            canvas.drawingPolicy = .pencilOnly
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.translatesAutoresizingMaskIntoConstraints = false
            
            canvas.isScrollEnabled = false
            canvas.bounces = false
            canvas.alwaysBounceVertical = false
            canvas.alwaysBounceHorizontal = false
            canvas.minimumZoomScale = 1
            canvas.maximumZoomScale = 1
            canvas.zoomScale = 1
            canvas.contentInset = .zero
            canvas.contentOffset = .zero

            let scale = UIScreen.main.scale
            canvas.contentScaleFactor = scale
            canvas.layer.contentsScale = scale
            
            
            canvas.becomeFirstResponder()
            
            return canvas
        }()
        canvas.drawing = store.combinedDrawing
        canvas.delegate = context.coordinator
        context.coordinator.bind(to: canvas)

        return canvas
    }

    public func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // SwiftUI 리사이즈/회전 중에도 PKCanvasView 내부 UIScrollView 상태가 남지 않도록
        // 매 업데이트 타이밍에 안전하게 정규화.
        context.coordinator.normalizeCanvasForOverlay(canvas)
    }
    
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    final public class Coordinator: NSObject, PKCanvasViewDelegate {
        private var store: StoreOf<CombinedCanvasFeature>
        /// Debounce 적용을 위한 이전 Update 타이밍
        private var lastUpdate = Date()
        /// drawing Data update를 위한 Debounce 시간
        private let debounceInterval: TimeInterval = 0.3
        /// publisher sink cancellable
        private var cancellables = Set<AnyCancellable>()
        /// 이전 stroke 수
        private var previousStrokeCount = 0
        /// 마지막으로 정규화(normalize)했던 bounds (리사이즈 감지)
        private var lastNormalizedBounds: CGRect = .zero

        init(store: StoreOf<CombinedCanvasFeature>) {
            self.store = store
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // undo/redo 중에는 save 무시
            if canvasView.undoManager?.isUndoing == true ||
                canvasView.undoManager?.isRedoing == true {
                notifyUndoState(from: canvasView)
                return
            }
                
            let now = Date()
            guard now.timeIntervalSince(lastUpdate) > debounceInterval else { return }
            lastUpdate = now
            
            let drawing = canvasView.drawing
            let strokes = drawing.strokes
            
            // 새로 그린 stroke 추출
            let currentCount = strokes.count
            guard currentCount > previousStrokeCount else { return }
            
            let newStroke = strokes[previousStrokeCount..<currentCount]
            previousStrokeCount = currentCount
            
            // 새 stroke들의 rect 계산
            let changedRect = newStroke.reduce(CGRect.null) { partial, stroke in
                partial.union(stroke.renderBounds)
            }
            guard !changedRect.isNull, !changedRect.isEmpty else { return }

            store.send(.saveDrawing(drawing, changedRect))
            notifyUndoState(from: canvasView)
        }
        
        public func bind(to canvas: PKCanvasView) {
            // Drawing Bind
            observe { [weak self] in
                guard let self else { return }
                
                let newDrawing = self.store.combinedDrawing
                guard canvas.drawing.dataRepresentation() != newDrawing.dataRepresentation() else {
                    return
                }
                canvas.drawing = newDrawing
                self.previousStrokeCount = newDrawing.strokes.count
            }
            // undo상태 초기화
            notifyUndoState(from: canvas)
            normalizeCanvasForOverlay(canvas)
            
            store.publisher.undoVersion
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self else { return }
                    canvas.undoManager?.undo()
                    self.notifyUndoState(from: canvas)
                }
                .store(in: &cancellables)
            
            store.publisher.redoVersion
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self else { return }
                    canvas.undoManager?.redo()
                    self.notifyUndoState(from: canvas)
                }
                .store(in: &cancellables)

            // Pencil Config bind
            store.$pencilConfig.publisher
                .sink { pencil in
                    let tool: PKTool = pencil.pencilType == .monoline
                    ? PKEraserTool(.bitmap)
                    : PKInkingTool(
                        pencil.pencilType,
                        color: pencil.lineColor.color,
                        width: pencil.lineWidth
                    )
                    canvas.tool = tool
                }
                .store(in: &cancellables)
            
            // 손가락 입력 설정 Bind
            store.$allowFingerDrawing.publisher
                .sink { allow in
                    canvas.drawingPolicy = allow ? .anyInput : .pencilOnly
                }
                .store(in: &cancellables)
        }
        
        /// Undo/Redo 가능 여부를 Feature로 전달
        private func notifyUndoState(from canvas: PKCanvasView) {
            let canUndo = canvas.undoManager?.canUndo ?? false
            let canRedo = canvas.undoManager?.canRedo ?? false
            store.send(.undoStateChanged(canUndo: canUndo, canRedo: canRedo))
        }
        
        /// 리사이즈/회전/윈도우 크기 변경 시 PKCanvasView(UIScrollView) 내부 상태가 남아
        /// 라이브 스트로크가 입력 위치와 어긋나는 것을 완화하기 위해 상태를 정규화.
        func normalizeCanvasForOverlay(_ canvas: PKCanvasView) {
            // 스크롤/줌 고정
            canvas.isScrollEnabled = false
            canvas.bounces = false
            canvas.alwaysBounceVertical = false
            canvas.alwaysBounceHorizontal = false
            canvas.minimumZoomScale = 1
            canvas.maximumZoomScale = 1
            if canvas.zoomScale != 1 { canvas.zoomScale = 1 }

            // inset/offset 초기화
            if canvas.contentInset != .zero { canvas.contentInset = .zero }
            if canvas.contentOffset != .zero { canvas.contentOffset = .zero }

            // contentSize는 bounds에 맞춰 고정 (bounds가 0이면 생략)
            if !canvas.bounds.isEmpty {
                let desired = canvas.bounds.size
                if canvas.contentSize != desired { canvas.contentSize = desired }
            }

            // 화면 스케일 고정 (윈도우 모드 전환 시 contentsScale mismatch 방지)
            let scale = UIScreen.main.scale
            if canvas.contentScaleFactor != scale { canvas.contentScaleFactor = scale }
            if canvas.layer.contentsScale != scale { canvas.layer.contentsScale = scale }

            // bounds가 바뀐 시점에는 한번 더 강하게 정규화
            if lastNormalizedBounds != canvas.bounds {
                lastNormalizedBounds = canvas.bounds
                // 레이아웃 반영 타이밍을 앞당겨 라이브 렌더링 오프셋을 줄인다.
                canvas.setNeedsLayout()
                canvas.layoutIfNeeded()
            }
        }
        
    }
    
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { CombinedCanvasFeature() },
        withDependencies: {
            $0.drawingData = .previewValue
        }
    )
    CombinedCanvasView(store: store)
}
