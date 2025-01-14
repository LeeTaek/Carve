//
//  SentencesWithDrawingView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct SentencesWithDrawingView: View {
    @Bindable private var store: StoreOf<SentencesWithDrawingReducer>
    
    public init(store: StoreOf<SentencesWithDrawingReducer>) {
        self.store = store
    }
    
    public var body: some View {
        VStack {
            if store.sentenceState.chapterTitle != nil {
                chapterTitleView
            }
            HStack {
                SentenceView(
                    store: self.store.scope(state: \.sentenceState,
                                            action: \.scope.sentenceAction)
                )
                Spacer()
                ZStack {
                    underLineView
                    CanvasView(
                        store: self.store.scope(state: \.canvasState,
                                                action: \.scope.canvasAction)
                    )
                }
                .frame(width: UIScreen.main.bounds.width / 2,
                       alignment: .topTrailing)
            }
        }
    }
    
    private var chapterTitleView: some View {
        Text(store.sentenceState.chapterTitle ?? "")
            .font(.system(size: 22))
            .fontWeight(.heavy)
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

#Preview {
    
}
