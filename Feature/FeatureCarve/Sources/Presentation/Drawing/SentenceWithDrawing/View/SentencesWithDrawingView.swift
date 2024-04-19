//
//  SentencesWithDrawingView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CommonUI
import SwiftUI

import ComposableArchitecture

public struct SentencesWithDrawingView: View {
    private var store: StoreOf<SentencesWithDrawingReducer>

    public init(store: StoreOf<SentencesWithDrawingReducer>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            HStack {
                BibleSentenceView(store: Store(initialState: store.sentenceState) {
                    BibleSentenceReducer()
                })
                .onDescriptionRectSize { rect in
                    store.send(.view(.calculateLineOffsets(rect)))
                }
                Spacer()
                ZStack {
                    underLineView
                    WithPerceptionTracking {   
                        CanvasView(store: Store(initialState: store.canvasState) {
                            CanvasReducer()
                        })
                    }
                }
                .frame(width: UIScreen.main.bounds.width / 2,
                       alignment: .topTrailing)
            }
        }
    }
    
    
    private var underLineView: some View {
        VStack(spacing: 0) {
            ForEach(0..<store.underLineCount, id: \.self) { lineIndex in
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .frame(height: store.underlineOffset[lineIndex]) // 밑줄 높이
            }
        }
        .padding(.horizontal, 20)
    }
    
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.maxY))
            return path
        }
    }
    
}
