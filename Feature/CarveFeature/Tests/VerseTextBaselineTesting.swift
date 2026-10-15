//
//  VerseTextBaselineTesting.swift
//  CarveFeatureTest
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  절 번호를 맞추는 본문 첫 줄 기준선(`VerseTextView.firstBaseline`). iPadOS 17.5 는 줄 실측을 읽는 `Text` 의 기준선을 넘기지 않아
//  SwiftUI `firstTextBaseline` 대신 이 값을 쓴다(2026-10-15 — 번호가 마지막 줄 옆에 붙던 것).
//

import CoreGraphics
import Domain
import Testing

@testable import CarveFeature

@MainActor
struct VerseTextBaselineTesting {
    /// 나눔명조 20pt · 줄 간격 30(위 여백 15).
    private let setting = SentenceSetting.initialState

    @Test("실측이 있으면 첫 밑줄에서 글꼴 descender 를 뺀 높이다")
    func measuredBaselineComesFromFirstUnderline() {
        let descender = setting.fontFamily.font(size: setting.fontSize).descender.magnitude
        // 밑줄 = 첫 줄 기준선(위 여백 포함) + descender — `VerseTextFeature.makeUnderlineOffsets` 와 같은 식이다.
        // 33.5 는 창세기 1장 1절의 시뮬레이터 실측 기준선(iPadOS 17.5 · 26.2 같음, 2026-10-15).
        let underlines: [CGFloat] = [33.5 + descender, 33.5 + descender + setting.linePitch]

        let baseline = VerseTextView.firstBaseline(underlineOffsets: underlines, sentenceSetting: setting)

        #expect(abs(baseline - 33.5) < 0.001)
    }

    @Test("실측 전에는 위 여백 + 글꼴 ascender 이고, 실측 기준선과 1pt 안이다")
    func fallbackUsesPaddingAndAscender() {
        let ascender = setting.fontFamily.font(size: setting.fontSize).ascender

        let baseline = VerseTextView.firstBaseline(underlineOffsets: [], sentenceSetting: setting)

        #expect(baseline == setting.textVerticalPadding + ascender)
        // 실측(33.5)은 SwiftUI 가 픽셀(@2x)에 맞춘 값이다 — 실측 전 첫 배치에서도 번호가 첫 줄 높이에 놓인다.
        #expect(abs(baseline - 33.5) < 1)
    }
}
