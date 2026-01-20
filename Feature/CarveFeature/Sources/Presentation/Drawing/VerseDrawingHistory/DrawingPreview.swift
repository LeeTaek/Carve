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

        // 프리뷰에서는 스크롤/바운스를 끄고, drawing bounds 만큼 콘텐츠 크기를 확보한다.
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.showsVerticalScrollIndicator = false
        canvasView.showsHorizontalScrollIndicator = false

        let bounds = drawing.bounds
        let contentWidth = max(44, bounds.maxX)
        let contentHeight = max(44, bounds.maxY)
        canvasView.contentSize = CGSize(width: contentWidth, height: contentHeight)
        canvasView.contentOffset = .zero

        return canvasView
    }
    
    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawing = drawing

        let bounds = drawing.bounds
        let contentWidth = max(44, bounds.maxX)
        let contentHeight = max(44, bounds.maxY)
        uiView.contentSize = CGSize(width: contentWidth, height: contentHeight)
        uiView.contentOffset = .zero
    }
}
