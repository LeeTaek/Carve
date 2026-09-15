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
import UIComponents

/// 한 절(verse)의 텍스트를 표시하고 밑줄(underline) 계산하는 뷰입니다.
///
/// 시안 M1 · M2: 절 번호는 첫 줄 위 왼쪽에 작은 강조색 숫자로 올리고(위첨자), 본문은 번호 칸 오른쪽에서 시작한다.
/// 줄 거리는 `SentenceSetting.linePitch`(글꼴 줄 높이 + 줄 간격)이고, 블록 위아래에 줄 간격의 절반을 둔다.
/// 종이 위 글자라 색은 외관과 무관한 `CarveColor.Paper` 를 쓴다.
public struct VerseTextView: View {
    @Bindable public var store: StoreOf<VerseTextFeature>

    /// Text.LayoutKey(텍스트 레이아웃 변경 이벤트)를 상위로 전달하기 위한 클로저.
    /// - Note: 실제 이 클로저를 통해 CarveDetailFeature의
    ///         `CarveDetailView` 가 offset 을 계산해 `VerseGeometryCollector` 에 모으고,
    ///         `.view(.verseGeometryMeasured)` 액션 한 번으로 상태를 갱신한다.
    ///         이렇게 레이아웃 이벤트만 상위로 올려 처리함으로써 ForEachReducer의
    ///         missing element warning을 회피한다.
    let onLayoutChange: (Text.LayoutKey.Value) -> Void
    /// 즐겨찾기한 절인가 — 절 번호 아래에 작은 채운 별을 둔다(시안 N2).
    let isFavorite: Bool

    /// 절 번호 칸 폭(시안: 번호 x 44 → 본문 x 78).
    static let verseNumberGutter: CGFloat = 34

    public init(
        store: StoreOf<VerseTextFeature>,
        isFavorite: Bool = false,
        onLayoutChange: @escaping (Text.LayoutKey.Value) -> Void
    ) {
        self.store = store
        self.isFavorite = isFavorite
        self.onLayoutChange = onLayoutChange
    }

    public var body: some View {
        sentenceDescription
    }

    /// 절 번호 — 첫 줄 기준선보다 글자 크기의 0.9 배 위(시안 20pt 본문에서 18pt 위).
    /// `offset` 은 배치를 바꾸지 않으므로 행 높이 · 밑줄 실측에 영향이 없다.
    private func verseNumberView(_ verse: Int) -> some View {
        let fontSize = store.sentenceSetting.fontSize
        return Text(String(format: "%02d", verse))
            .font(.system(size: max(11, fontSize * 0.55)))
            .monospacedDigit()
            .foregroundStyle(CarveColor.Paper.accent)
            .frame(width: Self.verseNumberGutter, alignment: .leading)
            .offset(y: -fontSize * 0.9)
            // `offset` 뒤에 붙여 올린 번호가 아니라 **첫 줄 기준선**에 맞춘다. overlay 라 행 높이 · 밑줄 실측에 영향이 없다.
            .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                if isFavorite {
                    favoriteMark(fontSize: fontSize)
                }
            }
            // 실기기 UI 테스트가 「1절」 이라는 이름으로 번호를 찾는다 — 즐겨찾기는 이름이 아니라 값으로 알린다.
            .accessibilityLabel("\(verse)절")
            .accessibilityValue(isFavorite ? "즐겨찾기" : "")
    }

    /// 즐겨찾기 표시 — 절 번호 칸 안, 첫 줄 기준선 아래(시안 N2: 20pt 본문에서 기준선 13pt 아래 · 16pt 별).
    private func favoriteMark(fontSize: CGFloat) -> some View {
        let size = max(12, fontSize * 0.78)
        return CarveIcon.starFill.image
            .resizable()
            .frame(width: size, height: size)
            .foregroundStyle(CarveColor.Paper.accent)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.top] - fontSize * 0.65
            }
            .accessibilityHidden(true)
    }

    /// 각 절의 내용 문장
    public var sentenceDescription: some View {
        let sentenceSetting = store.sentenceSetting

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            verseNumberView(store.verse)

            Text(store.sentence)
                .id(store.preferenceVersion)
                .tracking(sentenceSetting.traking)
                .font(CarveTypography.scripture(sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize)))
                .foregroundStyle(CarveColor.Paper.text)
                .lineSpacing(max(0, sentenceSetting.lineSpace))
                .lineLimit(nil)
                .onPreferenceChange(Text.LayoutKey.self) { textLayout in
                    onLayoutChange(textLayout)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, sentenceSetting.textVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
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
