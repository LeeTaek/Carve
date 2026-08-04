//
//  CodableColorTesting.swift
//  DomainTest
//
//  Created by Codex on 4/24/26.
//

@testable import Domain
import Foundation
import Testing
import UIKit

struct CodableColorTesting {
    @Test("CodableColor는 RGBA 값을 JSON으로 왕복 직렬화해도 유지한다")
    func codableColorRoundTripPreservesRGBAComponents() throws {
        let original = CodableColor(
            color: UIColor(
                red: 0.15,
                green: 0.35,
                blue: 0.55,
                alpha: 0.75
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableColor.self, from: data)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        decoded.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(red == 0.15)
        #expect(green == 0.35)
        #expect(blue == 0.55)
        #expect(alpha == 0.75)
    }

    @Test("UIColor.id는 알파를 포함한 RGBA 조합이 달라지면 달라진다")
    func uiColorIdentifierReflectsAlphaDifferences() {
        let opaqueBlue = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        let translucentBlue = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.5)

        #expect(opaqueBlue.id != translucentBlue.id)
        #expect(opaqueBlue.id == UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0).id)
    }
}
