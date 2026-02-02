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
    private var viewportSize: CGSize
    private var contentHeight: CGFloat
    private var scrollOffset: CGFloat
    private var bottomBuffer: CGFloat

    init(
        store: StoreOf<CombinedCanvasFeature>,
        viewportSize: CGSize = .zero,
        contentHeight: CGFloat = 0,
        scrollOffset: CGFloat = 0,
        bottomBuffer: CGFloat = 0
    ) {
        self.store = store
        self.viewportSize = viewportSize
        self.contentHeight = contentHeight
        self.scrollOffset = scrollOffset
        self.bottomBuffer = bottomBuffer
    }
    

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas: PKCanvasView = {
            let canvas = PKCanvasView()

#if DEBUG
            canvas.drawingPolicy = .anyInput
#else
            canvas.drawingPolicy = .pencilOnly
#endif

            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.translatesAutoresizingMaskIntoConstraints = false
            
            canvas.isScrollEnabled = false
            canvas.bounces = true
            canvas.alwaysBounceVertical = true
            canvas.alwaysBounceHorizontal = false
            canvas.contentInsetAdjustmentBehavior = .never
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
        context.coordinator.applyScrollState(
            canvas,
            viewportSize: viewportSize,
            contentHeight: contentHeight,
            scrollOffset: scrollOffset,
            bottomBuffer: bottomBuffer
        )
        // publisher 구독 타이밍과 엇갈려도 SwiftUI update cycle에서 drawing을 확실히 반영
        context.coordinator.applyStoreDrawingIfNeeded(canvas, store.combinedDrawing)
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
        /// programmatic drawing 업데이트로 인한 save 방지용
        private var suppressSaveVersion: Int = 0

        init(store: StoreOf<CombinedCanvasFeature>) {
            self.store = store
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if suppressSaveVersion > 0 {
                suppressSaveVersion = 0
                notifyUndoState(from: canvasView)
                return
            }
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
            store.publisher.combinedDrawing
              .removeDuplicates(
                by: { $0.dataRepresentation() == $1.dataRepresentation() }
              )
              .receive(on: DispatchQueue.main)
              .sink { [weak self] newDrawing in
                guard let self else { return }
                self.markProgrammaticUpdate()
                canvas.drawing = newDrawing
                self.previousStrokeCount = newDrawing.strokes.count
              }
              .store(in: &cancellables)
            
            
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
#if DEBUG
                    canvas.drawingPolicy = .anyInput
#else
                    canvas.drawingPolicy = allow ? .anyInput : .pencilOnly
#endif
                }
                .store(in: &cancellables)
        }

        
        /// SwiftUI update cycle에서도 store의 drawing을 PKCanvasView에 확실히 반영
        func applyStoreDrawingIfNeeded(_ canvas: PKCanvasView, _ newDrawing: PKDrawing) {
            guard canvas.drawing.dataRepresentation() != newDrawing.dataRepresentation() else { return }
            markProgrammaticUpdate()
            canvas.drawing = newDrawing
            self.previousStrokeCount = newDrawing.strokes.count
        }
        
        /// Undo/Redo 가능 여부를 Feature로 전달
        private func notifyUndoState(from canvas: PKCanvasView) {
            let canUndo = canvas.undoManager?.canUndo ?? false
            let canRedo = canvas.undoManager?.canRedo ?? false
            store.send(.undoStateChanged(canUndo: canUndo, canRedo: canRedo))
        }

        /// `canvasViewDrawingDidChange` 콜백에서 "사용자 입력"으로 오인되어
        /// `saveDrawing`이 호출되는 것을 방지하기 위한 플래그 관리.
        private func markProgrammaticUpdate() {
            suppressSaveVersion &+= 1
            let token = suppressSaveVersion
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.suppressSaveVersion == token {
                    self.suppressSaveVersion = 0
                }
            }
        }
        
        /// 리사이즈/회전/윈도우 크기 변경 시 PKCanvasView(UIScrollView) 내부 상태가 남아
        /// 라이브 스트로크가 입력 위치와 어긋나는 것을 완화하기 위해 상태를 정규화.
        func normalizeCanvasForOverlay(_ canvas: PKCanvasView) {
            // 스크롤/줌 고정
            canvas.isScrollEnabled = false
            canvas.bounces = true
            canvas.alwaysBounceVertical = true
            canvas.alwaysBounceHorizontal = false
            canvas.minimumZoomScale = 1
            canvas.maximumZoomScale = 1
            if canvas.zoomScale != 1 { canvas.zoomScale = 1 }

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
        
        
        /// 부모(예: SwiftUI ScrollView)의 스크롤 상태를 PKCanvasView 내부 UIScrollView에 동기화.
        /// 캔버스 자체의 스크롤을 막아두고 부모스크롤(SwiftUI ScrollView)가 스크롤된 만큼 Canvas 내부 스크롤.
        /// - Parameters:
        ///   - canvas: 스크롤 동기화할 Canvas
        ///   - viewportSize: contentSize 계산할때 사용할 최소 기준.
        ///   - contentHeight: 캔버스가 표현해야하는 전체 컨텐츠 높이
        ///   - scrollOffset: 부모 scrollView의 현재 세로 스크롤 offset
        ///   - bottomBuffer: 콘텐츠 아래 rubber-band를 표현할 여백
        func applyScrollState(
            _ canvas: PKCanvasView,
            viewportSize: CGSize,
            contentHeight: CGFloat,
            scrollOffset: CGFloat,
            bottomBuffer: CGFloat
        ) {
            // contentSize: 캔버스 내부 좌표계의 “총 높이/너비”를 확정.
            let width = max(viewportSize.width, canvas.bounds.width)
            let height = max(contentHeight, viewportSize.height)
            if width > 0, height > 0 {
                let desiredSize = CGSize(width: width, height: height)
                if canvas.contentSize != desiredSize {
                    canvas.contentSize = desiredSize
                    PerformanceLog.event("Canvas.ContentSizeUpdated")
                }
            }
            
            // rubber-Band 액션을 위해 contentInset(하단 여백) 확보
            let inset = UIEdgeInsets(top: 0, left: 0, bottom: bottomBuffer, right: 0)
            if canvas.contentInset != inset {
                canvas.contentInset = inset
                PerformanceLog.event("Canvas.ContentInsetUpdated")
            }
            

            // contentOffset: 부모 ScrollView의 스크롤 위치를 캔버스에 적용.
            let desiredOffset = CGPoint(x: 0, y: scrollOffset)
            if canvas.contentOffset != desiredOffset { canvas.contentOffset = desiredOffset }
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
