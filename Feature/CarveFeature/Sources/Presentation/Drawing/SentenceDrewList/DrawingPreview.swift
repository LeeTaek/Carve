//
//  DrawingPreview.swift
//  FeatureCarve
//
//  Created by 이택성 on 7/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import PencilKit

public struct DrawingPreview: UIViewRepresentable {
    let drawing: PKDrawing
    
    public func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.isUserInteractionEnabled = false
        canvasView.backgroundColor = .clear
        return canvasView
    }
    
    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawing = drawing
    }
}
