//
//  DesignTokenTesting.swift
//  UIComponentsTests
//
//  Created by Claude on 9/11/26.
//

import SwiftUI
import Testing
import UIKit

import Resources
@testable import UIComponents

/// 색 · 아이콘이 리소스 번들에서 실제로 읽히는지, 값이 시안(`docs/design/ui-design-direction.md` 3-1)과 같은지 본다.
struct DesignTokenTesting {
    struct ColorCase: Sendable, CustomTestStringConvertible {
        let name: String
        let color: Color
        let light: String
        let dark: String

        var testDescription: String { name }
    }

    static let themeCases: [ColorCase] = [
        ColorCase(name: "canvas", color: CarveColor.canvas, light: "#FAF9F6", dark: "#1B1F1D"),
        ColorCase(name: "surface", color: CarveColor.surface, light: "#F0EFEA", dark: "#2A302D"),
        ColorCase(name: "selected", color: CarveColor.selected, light: "#E4EBE2", dark: "#37443C"),
        ColorCase(name: "divider", color: CarveColor.divider, light: "#DFE2DB", dark: "#FFFFFF@0.08"),
        ColorCase(name: "ink", color: CarveColor.ink, light: "#303B36", dark: "#E8EAE7"),
        ColorCase(name: "secondary", color: CarveColor.secondary, light: "#5F6862", dark: "#A3ABA5"),
        ColorCase(name: "accent", color: CarveColor.accent, light: "#476550", dark: "#8FB79A"),
        ColorCase(name: "danger", color: CarveColor.danger, light: "#A4453C", dark: "#E0877C"),
        ColorCase(name: "scrim", color: CarveColor.scrim, light: "#303B36@0.18", dark: "#000000@0.28"),
        ColorCase(name: "fill", color: CarveColor.fill, light: "#FAF9F6@0.7", dark: "#FFFFFF@0.06")
    ]

    static let paperCases: [ColorCase] = [
        ColorCase(name: "Paper.background", color: CarveColor.Paper.background, light: "#FAF9F6", dark: "#FAF9F6"),
        ColorCase(name: "Paper.text", color: CarveColor.Paper.text, light: "#303B36", dark: "#303B36"),
        ColorCase(name: "Paper.guide", color: CarveColor.Paper.guide, light: "#DFE2DB", dark: "#DFE2DB")
    ]

    @Test("UI 색 토큰은 리소스 번들에서 시안의 라이트 · 다크 값으로 풀린다", arguments: themeCases)
    func themeTokenResolvesToSpec(_ token: ColorCase) {
        #expect(describe(token.color, in: .light) == token.light)
        #expect(describe(token.color, in: .dark) == token.dark)
    }

    /// 필사 영역이 다크 UI 색에 섞이면 종이 · 원문이 어두워지고 필기 대비가 무너진다(결정 8-1 안 1).
    @Test("필사 영역 색은 다크에서도 라이트와 같은 값이다", arguments: paperCases)
    func paperColorIgnoresAppearance(_ token: ColorCase) {
        #expect(describe(token.color, in: .light) == token.light)
        #expect(describe(token.color, in: .dark) == token.dark)
    }

    @Test("선 아이콘은 모두 번들에서 24pt 템플릿 벡터로 읽히고 실제로 그려진다", arguments: CarveIcon.allCases)
    func iconLoadsAsTemplateVector(_ icon: CarveIcon) throws {
        let image = try #require(UIImage(named: icon.asset.name, in: ResourcesResources.bundle, compatibleWith: nil))

        #expect(image.size == CGSize(width: CarveSize.iconGlyph, height: CarveSize.iconGlyph))
        #expect(image.renderingMode == .alwaysTemplate)
        // SVG 해석에 실패하면 빈 이미지가 된다 — 크기만 보고 통과시키지 않는다.
        #expect(inkedPixelRatio(image) > 0.03)
    }

    @Test("표면 안 컨트롤은 fill, 화면 바탕 위 컨트롤은 surface 를 바탕으로 쓴다")
    func controlFillFollowsBackdrop() {
        #expect(CarveBackdrop.surface.controlFill == CarveColor.fill)
        #expect(CarveBackdrop.canvas.controlFill == CarveColor.surface)
    }

    /// `#RRGGBB`, 불투명하지 않으면 `#RRGGBB@알파`.
    private func describe(_ color: Color, in scheme: ColorScheme) -> String {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = color.resolve(in: environment)
        let hex = String(
            format: "#%02X%02X%02X",
            channel(resolved.red),
            channel(resolved.green),
            channel(resolved.blue)
        )
        let alpha = (Double(resolved.opacity) * 100).rounded() / 100
        return alpha == 1 ? hex : "\(hex)@\(alpha)"
    }

    private func channel(_ value: Float) -> Int {
        Int((Double(value) * 255).rounded())
    }

    /// 48×48 로 그렸을 때 알파가 있는 픽셀의 비율.
    private func inkedPixelRatio(_ image: UIImage) -> Double {
        let side = 48
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else {
            return 0
        }
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        UIGraphicsPopContext()

        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let inked = (0..<(side * side)).filter { bytes[$0 * 4 + 3] > 0 }.count
        return Double(inked) / Double(side * side)
    }
}
