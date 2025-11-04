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
            canvas.becomeFirstResponder()
            
            return canvas
        }()
        canvas.drawing = store.combinedDrawing
        canvas.delegate = context.coordinator
        context.coordinator.bind(to: canvas)
        
        return canvas
    }

    public func updateUIView(_ canvas: PKCanvasView, context: Context) {
        Task { @MainActor in
            let newDrawing = store.combinedDrawing
            if canvas.drawing != newDrawing {
                canvas.drawing = newDrawing
                Log.debug("🖋 Canvas Updated: strokes = \(newDrawing.strokes.count)")

            }
        }
    }
    
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    final public class Coordinator: NSObject, PKCanvasViewDelegate {
        private var store: StoreOf<CombinedCanvasFeature>
        private var lastUpdate = Date()
        private let debounceInterval: TimeInterval = 0.3
        private var cancaellable = Set<AnyCancellable>()

        init(store: StoreOf<CombinedCanvasFeature>) {
            self.store = store
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let now = Date()
            guard now.timeIntervalSince(lastUpdate) > debounceInterval else { return }
            lastUpdate = now
//            self.store.send(.saveDrawing(canvasView.drawing))
//            self.store.send(.registUndoCanvas(canvasView))
        }
        
        public func bind(to canvas: PKCanvasView) {
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
                .store(in: &cancaellable)
            
            store.$allowFingerDrawing.publisher
                .sink { allow in
                    canvas.drawingPolicy = allow ? .anyInput : .pencilOnly
                }
                .store(in: &cancaellable)
        }
    }
    
}
