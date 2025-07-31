//
//  SentencesWithDrawingView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

@ViewAction(for: SentencesWithDrawingFeature.self)
public struct SentencesWithDrawingView: View {
    @Bindable public var store: StoreOf<SentencesWithDrawingFeature>
    @Binding private var halfWidth: CGFloat
    
    public init(store: StoreOf<SentencesWithDrawingFeature>, halfWidth: Binding<CGFloat>) {
        self.store = store
        self._halfWidth = halfWidth
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
                .frame(width: halfWidth * 0.95, alignment: .leading)

                ZStack {
                    underLineView
                    CanvasView(
                        store: self.store.scope(state: \.canvasState,
                                                action: \.scope.canvasAction)
                    )
                }
                .frame(width: halfWidth, alignment: .topTrailing)
            }
            .padding(.vertical, 2)
        }
        .contextMenu {
            Button("이전 필사 내용 보기") {
                send(.presentDrewHistory(true))
            }
        }
        .sheet(isPresented: $store.isPresentDrewHistory.sending(\.view.presentDrewHistory)) {
            SentenceDrewHistoryListView(
                store: self.store.scope(state: \.drewHistoryState,
                                        action: \.scope.drewHistoryAction)
            )
        }
    }
    
    private var chapterTitleView: some View {
        Text(store.sentenceState.chapterTitle ?? "")
            .font(.system(size: 22))
            .fontWeight(.heavy)
    }
    
    private var underLineView: some View {
        let underlineOffsets = store.sentenceState.underlineOffsets
        
        return Canvas { context, size in
            for y in underlineOffsets {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray), style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
    }
    
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState) {
            SentencesWithDrawingFeature()
        }
    @Previewable @State var halfWidth = UIScreen().bounds.width / 2
    
    SentencesWithDrawingView(store: store, halfWidth: $halfWidth)
}
