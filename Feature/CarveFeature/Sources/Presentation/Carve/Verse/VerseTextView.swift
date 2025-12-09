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
    
    /// Text.LayoutKey(텍스트 레이아웃 변경 이벤트)를 상위로 전달하기 위한 클로저.
    /// - Note: 실제 이 클로저를 통해 CarveDetailFeature의
    ///         `.view(.underlineLayoutChanged)`액션을 보내어 밑줄 offset 계산 및 상태 갱신.
    ///         이렇게 레이아웃 이벤트만 상위로 올려 처리함으로써 ForEachReducer의
    ///         missing element warning을 회피한다.
    let onLayoutChange: (Text.LayoutKey.Value) -> Void

    public init(
        store: StoreOf<VerseTextFeature>,
        onLayoutChange: @escaping (Text.LayoutKey.Value) -> Void
    ) {
        self.store = store
        self.onLayoutChange = onLayoutChange
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
                    onLayoutChange(textLayout)
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
    VerseTextView(store: store) { layout in
        let offsets =  VerseTextFeature.makeUnderlineOffsets(
            from: layout,
            sentenceSetting: store.sentenceSetting
        )
        store.send(.setUnderlineOffsets(offsets))
    }
}
#endif
