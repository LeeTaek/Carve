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
        Coordinator(lineColor: $store.lineColor,
                    lineWidth: $store.lineWidth)
    }
    
    final public class Coordinator: NSObject, PKCanvasViewDelegate {
        let lineColor: Binding<UIColor>
        let lineWidth: Binding<CGFloat>
        
        init(lineColor: Binding<UIColor>, lineWidth: Binding<CGFloat>) {
            self.lineColor = lineColor
            self.lineWidth = lineWidth
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            observe { [weak self] in
                guard let self else { return }
                canvasView.tool = PKInkingTool(.pencil,
                                               color: self.lineColor.wrappedValue,
                                               width: self.lineWidth.wrappedValue)
            }
        }
    }
    
    private func toDrawing(from data: Data) -> PKDrawing {
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
