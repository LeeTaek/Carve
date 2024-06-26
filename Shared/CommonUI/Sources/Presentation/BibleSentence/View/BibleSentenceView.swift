//
//  BibleSentenceView.swift
//  CommonUI
//
//  Created by 이택성 on 1/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI

import ComposableArchitecture

public struct BibleSentenceView: View {
    private var store: StoreOf<BibleSentenceReducer>

    public init(store: StoreOf<BibleSentenceReducer>) {
        self.store = store
    }
    
    public var body: some View {
        VStack {
            if store.state.chapterTitle != nil {
                chapterTitleView
            }
            sentenceDescription
                .background(alignment: .center) {
                    GeometryReader { geometryProxy in
                        Color.clear
                            .onAppear {
                                store.send(.inner(.redrawUnderline(geometryProxy.frame(in: .local))))
                            }
                    }
                }
        }
    }
    
    private var chapterTitleView: some View {
        Text(store.state.chapterTitle ?? "")
            .font(.system(size: 22))
            .fontWeight(.heavy)
    }
    
    private func sectionNumberView(_ section: Int) -> some View {
        let sectionString = section > 9 ? section.description : section.description + " "
        
        return Text("\(sectionString)")
            .bold()
            .padding(.vertical, (store.lineSpace - store.font.font(size: store.fontSize).lineHeight) / 2)
    }
    
    
    public var sentenceDescription: some View {
        HStack(alignment: .top) {
            sectionNumberView(store.section)
            
            Text(store.sentence)
                .tracking(store.traking)
                .font(Font(store.font.font(size: store.fontSize)))
                .lineSpacing(store.lineSpace - store.font.font(size: store.fontSize).lineHeight)
                .lineLimit(nil)
                .padding(.vertical, (store.lineSpace - store.font.font(size: store.fontSize).lineHeight) / 2)
        }
    }
}



#if DEBUG
#Preview {
    let store = Store(initialState: BibleSentenceReducer.State.initialState) {
        BibleSentenceReducer()
    }
    return BibleSentenceView(store: store)
}
#endif
