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
    
    public init(store: StoreOf<SentencesWithDrawingFeature>, halfWidth: Binding<CGFloat>) {
        self.store = store
        self._halfWidth = halfWidth
    }
    
    public var body: some View {
        VStack {
            if store.sentenceState.chapterTitle != nil {
                chapterTitleView
            }
            HStack(alignment: .top) {
                if store.isLeftHanded {
                    // 왼손잡이
                    underLineView
                    sentenceView
                } else {
                    // 오른손잡이
                    sentenceView
                    underLineView
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
            SentenceDrewHistoryListView(
                store: self.store.scope(state: \.drewHistoryState,
                                        action: \.scope.drewHistoryAction)
            )
        }
    }
    
    private var sentenceView: some View {
        SentenceView(
            store: self.store.scope(state: \.sentenceState,
                                    action: \.scope.sentenceAction)
        )
        .frame(width: halfWidth * 0.95, alignment: .leading)
        .padding(.top, topDrawingInset)
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
        .padding(.horizontal, 20)
        .frame(width: halfWidth, alignment: .topTrailing)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size) { 
                        // 레이아웃 패스 이후에 측정하여 .zero 방지
                        DispatchQueue.main.async {
                            let rect = proxy.frame(in: .named("Scroll"))
                                          guard rect.width > 0, rect.height > 0 else { return }
                                          send(.updateVerseFrame(rect))
                            
//                            // 이미 저장된 frame이 있으면 무시
//                            if store.verseFrame.width > 0 && store.verseFrame.height > 0 {
//                                return
//                            }
//                            
//                            let rect = proxy.frame(in: .named("Scroll"))
//                            guard rect.width > 0, rect.height > 0 else { return }
//                            send(.updateVerseFrame(rect))
                        }
                    }
            }
        )
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
