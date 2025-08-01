//
//  SentenceView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import SwiftUI

import ComposableArchitecture

public struct SentenceView: View {
    @Bindable public var store: StoreOf<SentenceFeature>

    public init(store: StoreOf<SentenceFeature>) {
        self.store = store
    }
    
    public var body: some View {
        sentenceDescription
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
            .tracking(sentenceSetting.traking)
            .font(Font(sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize)))
            .padding(.vertical,
                     (sentenceSetting.lineSpace - sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize).lineHeight) / 2)
    }
    
    
    public var sentenceDescription: some View {
        let sentenceSetting = store.sentenceSetting
        let lineSpacing = sentenceSetting.lineSpace - sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize).lineHeight
        let lineGapPadding = (sentenceSetting.lineSpace - sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize).lineHeight) / 2
        
        return HStack(alignment: .top) {
            verseNumberView(store.verse)
            
            Text(store.sentence)
                .tracking(sentenceSetting.traking)
                .font(Font(sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize)))
                .lineSpacing(lineSpacing)
                .lineLimit(nil)
                .onPreferenceChange(Text.LayoutKey.self) { textLayout in
                    store.send(.setUnderlineOffsets(textLayout))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, lineGapPadding)
        
        }
    }
}



#if DEBUG
#Preview {
    let store = Store(initialState: SentenceFeature.State.initialState) {
        SentenceFeature()
    }
    return SentenceView(store: store)
}
#endif
