//
//  SentenceView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI

import ComposableArchitecture

@ViewAction(for: SentenceReducer.self)
public struct SentenceView: View {
    @Bindable public var store: StoreOf<SentenceReducer>

    public init(store: StoreOf<SentenceReducer>) {
        self.store = store
    }
    
    public var body: some View {
        sentenceDescription
            .onAppear {
                send(.isRedraw(true))
            }
            .background(alignment: .center) {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: store.isredraw) { _, _ in
                            if store.isredraw {
                                let proxySize = proxy.frame(in: .local)
                                send(.redrawUnderline(proxySize))
                            }
                        }
                }
            }
    }
    
    private var chapterTitleView: some View {
        Text(store.chapterTitle ?? "")
            .font(.system(size: 22))
            .fontWeight(.heavy)
    }
    
    private func verseNumberView(_ verse: Int) -> some View {
        let sectionString = verse > 9 ? verse.description : verse.description + " "
        let sentenceSetting = store.sentenceSetting
        return Text("\(sectionString)")
            .bold()
            .padding(.vertical, 
                     (sentenceSetting.lineSpace - sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize).lineHeight) / 2)
    }
    
    
    public var sentenceDescription: some View {
        let sentenceSetting = store.sentenceSetting
        return HStack(alignment: .top) {
            verseNumberView(store.verse)
            
            Text(store.sentence)
                .tracking(sentenceSetting.traking)
                .font(Font(sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize)))
                .lineSpacing(sentenceSetting.lineSpace - sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize).lineHeight)
                .lineLimit(nil)
                .padding(.vertical, 
                         (sentenceSetting.lineSpace - sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize).lineHeight) / 2)
        }
    }
}



#if DEBUG
#Preview {
    let store = Store(initialState: SentenceReducer.State.initialState) {
        SentenceReducer()
    }
    return SentenceView(store: store)
}
#endif
