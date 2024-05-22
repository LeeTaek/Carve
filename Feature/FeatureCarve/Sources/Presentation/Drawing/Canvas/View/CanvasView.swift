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
                                       color: self.store.lineColor,
                                       width: self.store.lineWidth)
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
                                   color: self.store.lineColor,
                                   width: self.store.lineWidth)
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: $store)
    }
    
    final public class Coordinator: NSObject, PKCanvasViewDelegate {
        let store: Bindable<StoreOf<CanvasReducer>>
        init(store: Bindable<Store<CanvasReducer.State, CanvasReducer.Action>>) {
            self.store = store
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            self.store.wrappedValue.send(.saveDrawing(canvasView.drawing))
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
