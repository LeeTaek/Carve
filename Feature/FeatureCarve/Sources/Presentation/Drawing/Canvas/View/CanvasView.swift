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

import ComposableArchitecture

@MainActor
public struct CanvasView: UIViewRepresentable {
    public typealias UIViewType = PKCanvasView
    @Bindable private var store: StoreOf<CanvasReducer>
    init(store: StoreOf<CanvasReducer>) {
        self.store = store
    }
    
    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas: PKCanvasView = {
            let canvas = PKCanvasView()
#if DEBUG
            canvas.drawingPolicy = .anyInput
#else
            canvas.drawingPolicy = .pencilOnly
#endif
            canvas.tool = PKInkingTool(.pencil, 
                                       color: self.store.pencilConfig.lineColor.color,
                                       width: self.store.pencilConfig.lineWidth)
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.translatesAutoresizingMaskIntoConstraints = false
            canvas.becomeFirstResponder()
            
            return canvas
        }()
        canvas.drawing = toDrawing(from: store.drawing.lineData)
        canvas.delegate = context.coordinator
        
        return canvas
    }
    
    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = PKInkingTool(.pencil,
                                   color: self.store.pencilConfig.lineColor.color,
                                   width: self.store.pencilConfig.lineWidth)
        context.coordinator.updateTool(for: uiView)
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    final public class Coordinator: NSObject, PKCanvasViewDelegate {
        var store: StoreOf<CanvasReducer>
        init(store: StoreOf<CanvasReducer>) {
            self.store = store
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            self.store.send(.saveDrawing(canvasView.drawing))
        }
        
        public func updateTool(for canvas: PKCanvasView) {
            if store.pencilConfig.pencilType == .monoline {
                canvas.tool = PKEraserTool(.bitmap)
            } else {
                canvas.tool = PKInkingTool(.pencil,
                                           color: store.pencilConfig.lineColor.color,
                                           width: store.pencilConfig.lineWidth)
            }
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
    let store = Store(initialState: .initialState) {
        CanvasReducer()
    }
    return CanvasView(store: store)
}
