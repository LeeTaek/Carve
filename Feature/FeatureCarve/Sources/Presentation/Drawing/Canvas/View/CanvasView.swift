//
//  CanvasView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/23/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import PencilKit
import SwiftUI
import Combine

import ComposableArchitecture

public struct CanvasView: UIViewRepresentable {
    public typealias UIViewType = PKCanvasView
    private var store: StoreOf<CanvasReducer>
    init(store: StoreOf<CanvasReducer>) {
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
        canvas.drawing = toDrawing(from: store.drawing?.lineData)
        canvas.delegate = context.coordinator
        context.coordinator.bind(to: canvas)
        
        return canvas
    }
    
    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        Task { @MainActor in
            let newDrawing = toDrawing(from: store.drawing?.lineData)
            if uiView.drawing != newDrawing {
                uiView.drawing = newDrawing
            }
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    final public class Coordinator: NSObject, PKCanvasViewDelegate {
        private var store: StoreOf<CanvasReducer>
        private var lastUpdate = Date()
        private let debounceInterval: TimeInterval = 0.3
        private var cancaellable = Set<AnyCancellable>()

        init(store: StoreOf<CanvasReducer>) {
            self.store = store
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let now = Date()
            guard now.timeIntervalSince(lastUpdate) > debounceInterval else { return }
            lastUpdate = now
            self.store.send(.saveDrawing(canvasView.drawing))
            self.store.send(.registUndoCanvas(canvasView))
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
        }
    }
    
    private func toDrawing(from data: Data?) -> PKDrawing {
        guard let data else { return PKDrawing() }
        do {
            let drawing = try PKDrawing.init(data: data)
            return drawing
        } catch {
            Log.debug("Data to Drawing Error", error)
        }
        return PKDrawing()
    }
    
}


#Preview {
    @Previewable @State var store = Store(initialState: .initialState,
                                          reducer: { CanvasReducer() },
                                          withDependencies: {
        $0.drawingData = .previewValue
        $0.undoManager = .previewValue
    })
    CanvasView(store: store)
}
