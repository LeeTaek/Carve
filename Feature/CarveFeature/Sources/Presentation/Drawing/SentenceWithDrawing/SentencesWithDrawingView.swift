//
//  SentencesWithDrawingView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import CarveToolkit

import ComposableArchitecture

@ViewAction(for: SentencesWithDrawingFeature.self)
public struct SentencesWithDrawingView: View {
    @Bindable public var store: StoreOf<SentencesWithDrawingFeature>
    @Binding private var halfWidth: CGFloat
    
    private var topDrawingInset: CGFloat {
        store.sentence.verse == 1 ? 25 : 0
    }
    let onUnderlineLayoutChange: (VerseRowFeature.State.ID, Text.LayoutKey.Value) -> Void

    
    public init(
        store: StoreOf<SentencesWithDrawingFeature>,
        halfWidth: Binding<CGFloat>,
        onUnderlineLayoutChange: @escaping (VerseRowFeature.State.ID, Text.LayoutKey.Value) -> Void
    ) {
        self.store = store
        self._halfWidth = halfWidth
        self.onUnderlineLayoutChange = onUnderlineLayoutChange
    }
    
    public var body: some View {
        VStack {
            if store.sentenceState.chapterTitle != nil {
                chapterTitleView
            }
            HStack(alignment: .top) {
                if store.isLeftHanded {
                    // 왼손잡이
                    canvasView
                    sentenceView
                } else {
                    // 오른손잡이
                    sentenceView
                    canvasView
                }
            }
            .animation(.easeInOut(duration: 0.3), value: store.isLeftHanded)
            .padding(.vertical, 2)
        }
        .touchIgnoringContextMenu(ignoringType: .pencil) {
            UIMenu(children: [
                UIAction(title: "이전 필사 내용 보기") {_ in send(.presentDrewHistory(true)) }
            ])
        }
        .sheet(isPresented: $store.isPresentDrewHistory.sending(\.view.presentDrewHistory)) {
            VerseDrawingHistoryView(
                store: self.store.scope(state: \.drewHistoryState,
                                        action: \.scope.drewHistoryAction)
            )
        }
    }
    
    private var sentenceView: some View {
        VerseTextView(
            store: self.store.scope(state: \.sentenceState,
                                    action: \.scope.sentenceAction),
            onLayoutChange: { layout in
                onUnderlineLayoutChange(store.id, layout)
            }
        )
        .frame(width: halfWidth * 0.95, alignment: .leading)
        .padding(.top, topDrawingInset)
    }
    
    private var canvasView: some View {
        ZStack {
            underLineView
            CanvasView(
                store: self.store.scope(state: \.canvasState,
                                        action: \.scope.canvasAction)
            )
        }
        .frame(width: halfWidth, alignment: .topTrailing)
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
                path.move(to: CGPoint(x: 0, y: y + topDrawingInset))
                path.addLine(to: CGPoint(x: size.width, y: y + topDrawingInset))
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
    
    SentencesWithDrawingView(store: store, halfWidth: $halfWidth) { _, layout in
        let offsets =  VerseTextFeature.makeUnderlineOffsets(
            from: layout,
            sentenceSetting: store.sentenceState.sentenceSetting
        )
        store.send(.scope(.sentenceAction(.setUnderlineOffsets(offsets))))
    }
}
