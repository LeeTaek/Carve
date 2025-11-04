//
//  CombinedCanvasView.swift
//  CarveFeature
//
//  Created by 이택성 on 11/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import PencilKit
import Domain
import CarveToolkit

public struct CombinedCanvasView: UIViewRepresentable {
    public var sentenceStates: [SentencesWithDrawingFeature.State]

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.isUserInteractionEnabled = false  // 표시 전용
        canvas.backgroundColor = .clear
        return canvas
    }

    public func updateUIView(_ canvas: PKCanvasView, context: Context) {
        var mergedDrawing = PKDrawing()
        
        for state in sentenceStates {
            guard let drawing = state.canvasState.drawing,
                  let data = drawing.lineData,
                  let pkDrawing = try? PKDrawing(data: data)
            else { continue }
            
            let verseFrame = state.verseFrame
            guard verseFrame.width > 0, verseFrame.height > 0 else { continue }

            // Debug once if you need:
             Log.debug(state.sentenceState.verse, verseFrame)

            // verse의 실제 위치로 이동
            let transform = CGAffineTransform(translationX: verseFrame.minX, y: verseFrame.minY)
            let shiftedDrawing = pkDrawing.transformed(using: transform)

            mergedDrawing.append(shiftedDrawing)
        }

        canvas.drawing = mergedDrawing
    }
}
