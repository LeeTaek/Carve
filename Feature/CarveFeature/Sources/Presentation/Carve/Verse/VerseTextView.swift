//
//  VerseTextView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import SwiftUI

import ComposableArchitecture

/// 한 절(verse)의 텍스트를 표시하고 밑줄(underline) 계산하는 뷰입니다.
public struct VerseTextView: View {
    @Bindable public var store: StoreOf<VerseTextFeature>

    public init(store: StoreOf<VerseTextFeature>) {
        self.store = store
    }
    
    public var body: some View {
        sentenceDescription
    }
    
    /// 각 절의 번호
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
    
    /// 각 절의 내용 문장
    public var sentenceDescription: some View {
        let sentenceSetting = store.sentenceSetting
        let lineSpacing = sentenceSetting.lineSpace - sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize).lineHeight
        let lineGapPadding = (sentenceSetting.lineSpace - sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize).lineHeight) / 2
        
        return HStack(alignment: .top) {
            verseNumberView(store.verse)
            
            Text(store.sentence)
                .id(store.preferenceVersion)
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
    let store = Store(initialState: VerseTextFeature.State.initialState) {
        VerseTextFeature()
    }
    return VerseTextView(store: store)
}
#endif
