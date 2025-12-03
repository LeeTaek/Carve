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

/// 한 절(verse)에 대한 Row UI를 그리는 뷰.
@ViewAction(for: VerseRowFeature.self)
public struct VerseRowView: View {
    @Bindable public var store: StoreOf<VerseRowFeature>
    /// sentence와 canvas 영역 배치를 위한 너비
    @Binding private var halfWidth: CGFloat
    /// 1절일때만 상단 여백 추가
    private var topDrawingInset: CGFloat {
        store.sentence.verse == 1 ? 25 : 0
    }
    
    public init(store: StoreOf<VerseRowFeature>, halfWidth: Binding<CGFloat>) {
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
            VerseDrawingHistoryView(
                store: self.store.scope(state: \.drewHistoryState,
                                        action: \.scope.drewHistoryAction)
            )
        }
    }
    
    /// 현재 절 내용표시 텍스트 뷰
    private var sentenceView: some View {
        VerseTextView(
            store: self.store.scope(state: \.sentenceState,
                                    action: \.scope.sentenceAction)
        )
        .frame(width: halfWidth * 0.95, alignment: .leading)
        .padding(.top, topDrawingInset)
    }
    
    /// 각 장의 제목
    private var chapterTitleView: some View {
        Text(store.sentenceState.chapterTitle ?? "")
            .font(.system(size: 22))
            .fontWeight(.heavy)
    }
    
    /// Canvas 밑에 깔 밑줄 view
    /// glbalRect를 측정해 상위로 전달
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
                    .onAppear {
                        DispatchQueue.main.async {
                            let rectInGlobal = proxy.frame(in: .global)
                            send(.updateVerseFrame(rectInGlobal))
                        }
                    }
                    .onChange(of: proxy.size) { _, _ in
                        DispatchQueue.main.async {
                            let rect = proxy.frame(in: .global)
                            send(.updateVerseFrame(rect))
                        }
                    }
            }
        )
    }
    
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState) {
            VerseRowFeature()
        }
    @Previewable @State var halfWidth = UIScreen().bounds.width / 2
    
    VerseRowView(store: store, halfWidth: $halfWidth)
}
