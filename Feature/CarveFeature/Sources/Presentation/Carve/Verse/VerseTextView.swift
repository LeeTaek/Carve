//
//  VerseTextView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
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
    private func verseNumberView(_ verse: Int, verseEnd: Int?) -> some View {
        let fontSize = store.sentenceSetting.fontSize
        return Text(Self.verseNumberText(verse: verse, verseEnd: verseEnd))
            .font(.system(size: max(11, fontSize * 0.55)))
            .monospacedDigit()
            // 합쳐진 절(`18-19`)도 번호 칸 안에 한 줄로 둔다.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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
            .accessibilityLabel(verseEnd.map { Text("\(verse)-\($0)절", bundle: .module) } ?? Text("\(verse)절", bundle: .module))
            .accessibilityValue(isFavorite ? Text("즐겨찾기", bundle: .module) : Text(verbatim: ""))
    }

    /// 절 번호 표기. 두 자리로 맞추고, 합쳐진 절은 범위로 쓴다(`06`, `18-19`).
    static func verseNumberText(verse: Int, verseEnd: Int?) -> String {
        let start = String(format: "%02d", verse)
        guard let verseEnd else { return start }
        return start + "-" + String(format: "%02d", verseEnd)
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

    /// 역할: 본문 블록(위 여백 포함) 위에서 첫 줄 기준선까지의 높이 — 절 번호를 이 높이에 맞춘다.
    /// 입력 · 출력: 줄 실측(밑줄 offset — 첫 값 = 첫 줄 기준선 + descender + 위 여백) · 본문 설정 → 높이(pt).
    ///   실측이 있으면 첫 밑줄에서 descender 를 뺀 값, 실측 전(빈 배열)이면 위 여백 + 글꼴 ascender 다.
    /// 부작용: 없음.
    ///
    /// ⚠️ SwiftUI 의 `firstTextBaseline` 을 쓰지 않는다. iPadOS 17.5 는 줄 실측(`Text.LayoutKey`)을 읽는 `Text` 의 기준선을 `HStack` 에 넘기지 않고
    ///    블록 바닥(높이)을 기준선으로 써, 번호가 마지막 줄 옆에 붙었다(2026-10-15 시뮬레이터 — 실측을 읽지 않으면 첫 줄, 18.6 · 26.2 는 실측을 읽어도 첫 줄).
    ///    창세기 1장 나눔명조 20pt 에서 실측 33.5 · 글꼴 수치 33.4 다(SwiftUI 가 픽셀에 맞춘 차이). 어느 값이든 번호가 블록 안이라 행 높이는 그대로다.
    static func firstBaseline(underlineOffsets: [CGFloat], sentenceSetting: SentenceSetting) -> CGFloat {
        let uiFont = sentenceSetting.fontFamily.font(size: sentenceSetting.fontSize)
        if let firstUnderline = underlineOffsets.first {
            return firstUnderline - uiFont.descender.magnitude
        }
        return sentenceSetting.textVerticalPadding + uiFont.ascender
    }

    /// 각 절의 내용 문장. 절 번호는 본문 블록의 첫 줄 기준선(`firstBaseline`)에 맞춘다.
    public var sentenceDescription: some View {
        let sentenceSetting = store.sentenceSetting
        let firstBaseline = Self.firstBaseline(underlineOffsets: store.underlineOffsets, sentenceSetting: sentenceSetting)

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            verseNumberView(store.verse, verseEnd: store.verseEnd)

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
                .alignmentGuide(.firstTextBaseline) { _ in
                    firstBaseline
                }
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
