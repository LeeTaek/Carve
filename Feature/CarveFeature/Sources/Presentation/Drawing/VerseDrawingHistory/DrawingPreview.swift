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
        // 다크에서도 잉크를 저장된 색 그대로 그린다(결정 8-1 안 1). 바탕 종이는 감싸는 쪽이 칠한다.
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.backgroundColor = .clear
        return canvasView
    }
    
    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawing = drawing
    }
}
