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
    /// 레이아웃 변경 이벤트를 한 프레임 단위로 합치기 위한 객체
    @StateObject private var layoutChangeCoalescer = LayoutChangeCoalescer()
    
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
    private func verseNumberView(
        _ verse: Int,
        lineGapPadding: CGFloat
    ) -> some View {
        let sectionString = verse > 9 ? verse.description : verse.description + " "
        let sentenceSetting = store.sentenceSetting
        let font = sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize)
        return Text("\(sectionString)")
            .bold()
            .tracking(sentenceSetting.traking)
            .font(Font(font))
            .padding(.vertical, lineGapPadding)
    }
    
    /// 각 절의 내용 문장
    public var sentenceDescription: some View {
        let sentenceSetting = store.sentenceSetting
        let font = sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize)
        let lineGap = max(0, sentenceSetting.lineSpace - font.lineHeight)
        let lineGapPadding = lineGap / 2
        
        return HStack(alignment: .top) {
            verseNumberView(store.verse, lineGapPadding: lineGapPadding)
            
            Text(store.sentence)
                .id(store.preferenceVersion)
                .tracking(sentenceSetting.traking)
                .font(Font(font))
                .lineSpacing(lineGap)
                .lineLimit(nil)
                .onPreferenceChange(Text.LayoutKey.self) { textLayout in
                    Task { @MainActor in
                        layoutChangeCoalescer.schedule(layout: textLayout) { layout in
                            onLayoutChange(layout)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, lineGapPadding)
        
        }
    }
}

/// 화면 회전, 문자열 설정 변경과 같은 레이아웃에 변화를 주는 이벤트들을 즉시 적용하지 않고
/// 잠깐 대기했다가 최종 결과만 적용.
@MainActor
private final class LayoutChangeCoalescer: ObservableObject {
    private var pendingLayout: Text.LayoutKey.Value?
    private var isScheduled = false
    private var task: Task<Void, Never>?

    func schedule(
        layout: Text.LayoutKey.Value,
        onFlush: @escaping (Text.LayoutKey.Value) -> Void
    ) {
        pendingLayout = layout
        guard !isScheduled else { return }
        isScheduled = true
        task?.cancel()
        task = Task { @MainActor in
            // 레이아웃 안정화를 위해 1프레임 정도 대기
            await Task.yield()
            try? await Task.sleep(nanoseconds: 16_000_000)
            isScheduled = false
            guard let pendingLayout else { return }
            onFlush(pendingLayout)
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
