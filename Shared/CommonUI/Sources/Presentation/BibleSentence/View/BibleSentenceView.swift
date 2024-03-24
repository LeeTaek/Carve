//
//  BibleSentenceView.swift
//  CommonUI
//
//  Created by 이택성 on 1/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Common
import SwiftUI

import ComposableArchitecture

public struct BibleSentenceView: View {
    private let store: StoreOf<BibleSentenceReducer>
    @ObservedObject private var viewStore: ViewStore<BibleSentenceReducer.State,
                                                     BibleSentenceReducer.ViewAction>
    
    public init(store: StoreOf<BibleSentenceReducer>) {
        self.store = store
        self.viewStore = ViewStore(self.store, observe: { $0 }, send: { .view($0) })
    }
    
    public var body: some View {
        VStack {
            if viewStore.state.chapterTitle != nil {
                chapterTitleView
            }
            sentenceDescription
        }
    }
    
    private var chapterTitleView: some View {
        Text(viewStore.state.chapterTitle ?? "")
            .font(.system(size: 22))
            .fontWeight(.heavy)
    }
    
    private func sectionNumberView(_ section: Int) -> some View {
        let sectionString = section > 9 ? section.description : section.description + " "
        
        return Text("\(sectionString)")
            .bold()
            .padding(.vertical, (viewStore.lineSpace - viewStore.font.font(size: viewStore.fontSize).lineHeight) / 2)
    }
    
    
    public var sentenceDescription: some View {
        HStack(alignment: .top) {
            sectionNumberView(viewStore.section)
            
            Text(viewStore.sentence)
                .tracking(viewStore.traking)
                .font(Font(viewStore.font.font(size: viewStore.fontSize)))
                .lineSpacing(viewStore.lineSpace - viewStore.font.font(size: viewStore.fontSize).lineHeight)
                .lineLimit(nil)
                .padding(.vertical, (viewStore.lineSpace - viewStore.font.font(size: viewStore.fontSize).lineHeight) / 2)

            
        }
    }
    
    
    public func onDescriptionRectSize(_ perform: @escaping (CGRect) -> Void) -> some View {
        self.sentenceDescription
            .customBackground {
                GeometryReader { geometryProxy in
                    Color.clear
                        .preference(key: SizePreferenceKey.self,
                                    value: geometryProxy.frame(in: .local))
                }
            }
            .onPreferenceChange(SizePreferenceKey.self, perform: perform)
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
