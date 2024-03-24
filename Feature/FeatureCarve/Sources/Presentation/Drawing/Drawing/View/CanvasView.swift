//
//  CanvasView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/23/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import PencilKit
import SwiftUI

import ComposableArchitecture

public struct CanvasView: UIViewRepresentable {
    public typealias UIViewType = PKCanvasView
    private let store: StoreOf<CanvasReducer>
    @ObservedObject
    private var viewStore: ViewStore<CanvasReducer.State, CanvasReducer.Action>
    
    
    init(store: StoreOf<CanvasReducer>) {
        self.store = store
        self.viewStore = ViewStore(self.store, observe: { $0 })
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
                                       color: self.viewStore.lineColor,
                                       width: self.viewStore.lineWidth)
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.translatesAutoresizingMaskIntoConstraints = false
            canvas.becomeFirstResponder()
            
            return canvas
        }()
        canvas.drawing = viewStore.drawing.lineData
        canvas.delegate = context.coordinator
        
        return canvas
    }
    
    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = PKInkingTool(.pencil,
                                   color: self.viewStore.lineColor,
                                   width: self.viewStore.lineWidth)
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(lineColor: viewStore.binding(get: \.lineColor,
                                                 send: .selectDidFinish),
                    lineWidth: viewStore.binding(get: \.lineWidth,
                                                 send: .selectDidFinish))
    }
    
    final public class Coordinator: NSObject, PKCanvasViewDelegate {
        let lineColor: Binding<UIColor>
        let lineWidth: Binding<CGFloat>
        
        init(lineColor: Binding<UIColor>, lineWidth: Binding<CGFloat>) {
            self.lineColor = lineColor
            self.lineWidth = lineWidth
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            canvasView.tool = PKInkingTool(.pencil,
                                           color: self.lineColor.wrappedValue,
                                           width: self.lineWidth.wrappedValue)
        }
    }
    
}


#Preview {
    let store = Store(initialState: .initialState) {
        CanvasReducer()
    }
    return CanvasView(store: store)
}
