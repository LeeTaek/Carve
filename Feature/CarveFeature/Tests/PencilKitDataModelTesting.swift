//
//  PencilKitDataModelTesting.swift
//  FeatureCarveTest
//
//  Phase 0A-S1 — PencilKit 데이터 모델 검증
//  단일 Canvas 설계(docs/single-canvas-design.md) §7-2 / §7-3 / §7-4 / §7-5 의 전제를 실측으로 확인한다.
//

import Foundation
import PencilKit
import Testing
import UIKit

/// iPad mini(A17 Pro) / iOS 26.2 시뮬레이터에서 실제 앱으로 필기·지우기를 수행한 뒤
/// `ZBIBLEDRAWING.ZLINEDATA` 블롭을 그대로 추출한 fixture.
///
/// 재현 절차
/// 1. `allowFingerDrawing = true` 로 시드 후 앱 기동 (drawingPolicy == .anyInput)
/// 2. 창세기 1:2 캔버스에 연필 획 2개를 그림                              → `beforeErase`
/// 3. 팔레트를 지우개(monoline → PKEraserTool(.bitmap))로 전환
/// 4. 1번 획의 중간을 세로로 가로질러 지움                                 → `afterPartialErase`
/// 5. 2번 획을 가로로 쓸어 완전히 지움                                     → `afterFullErase`
enum EraserFixture {
    /// 지우개 사용 전: 연필 획 2개 (690 bytes)
    static let beforeErase =
        "AXdyZPABAAgAEhAAAAAAAAAAAAAAAAAAAAAAEhAfLpB9kMpABIMQo+Qqe0aLGgYIABAAGAAaBggCEAEYAiI3ChQNAAAAABUAAAAAHQAAAAAlAACAPxIUY29tLmFwcGxlLmluay5wZW5jaWwYA0FaOx" +
        "1/eHjovyqOAgoQnPjd6ZtMQXuNqF/8bAKRjRIGCAAQARgBGgYIABABGAAgACrKAQoQ1IF7pbu7QDSOPFvP+9ahKhGtMOWqVyXIQRgKIIMCKPwNMhTEw8M/6AMJAAAA9DcAAAAAgD8AADqMAQAAVEIA" +
        "ADhBAAAAAJkZAACmQgAAsEDAqfk8mRkAAOJCAAB4QWAvbD2ZGQAAD0MAALBAIN2yPZkZAAAtQwAAeEGwmfA9mRkAAEtDAACwQAhyEj6ZGQAAaUMAAHhBUGoxPpkZAICDQwAAsEDgjlA+yxkAgJJDAA" +
        "B4QRj0bj7XEwCAnEMAAChBCPOEPg8MQAEyFA0AAExCFQAAoEAdAACEQyUAACBBQIDH5fzxBCqOAgoQXsf/6BZrQkyd3hU107HYIRIGCAEQARgCGgYIABABGAAgACrKAQoQyATpXBRJQ+iNzNcngJN0" +
        "lxE9YZGyVyXIQRgKIIMCKPwNMhTEw8M/6AMJAAAAAAAAAAAAgD8AADqMAQAAVEIAACZCAAAAAJkZAACmQgAAEELAJ+g8mRkAAOJCAAA0QmDmbz2ZGQAAD0MAABBCEPq0PZkZAAAtQwAANELANvI9mR" +
        "kAAEtDAAAQQmACGD6ZGQAAaUMAADRCAOAyPpkZAICDQwAAEEIQVFE+mRmqW5JDhFo0Qii+bT79FQCAnEMAACJC9EiGPkcNQAEyFA0AAEhCFQAAEEIdAICEQyUAABBBQODs1Mu6BDoGCAAQABgAQhC5" +
        "RIV1T99JeYOHeHBZ0I1x"

    /// 1번 획 중간을 bitmap 지우개로 가로질러 지운 뒤 (1266 bytes)
    static let afterPartialErase =
        "AXdyZPABAAgAEhAAAAAAAAAAAAAAAAAAAAAAEhAfLpB9kMpABIMQo+Qqe0aLEhBsLN/gIkpBpIb5KDbJcFTDGgYIABAAGAAaBggDEAEYAxoGCAIQAhgAIjcKFA0AAAAAFQAAAAAdAAAAACUAAIA/Eh" +
        "Rjb20uYXBwbGUuaW5rLnBlbmNpbBgDQVo7HX94eOi/IjcKFA0AAAAAFQAAAAAdAAAAACUAAAAAEhRjb20uYXBwbGUuaW5rLmVyYXNlchgDQQAAAAAAAAAAKs4FChCc+N3pm0xBe42oX/xsApGNEgYI" +
        "ABABGAEaBggAEAEYACAAKsoBChDUgXulu7tANI48W8/71qEqEa0w5apXJchBGAoggwIo/A0yFMTDwz/oAwkAAAD0NwAAAACAPwAAOowBAABUQgAAOEEAAAAAmRkAAKZCAACwQMCp+TyZGQAA4kIAAH" +
        "hBYC9sPZkZAAAPQwAAsEAg3bI9mRkAAC1DAAB4QbCZ8D2ZGQAAS0MAALBACHISPpkZAABpQwAAeEFQajE+mRkAgINDAACwQOCOUD7LGQCAkkMAAHhBGPRuPtcTAICcQwAAKEEI84Q+DwxAAUCAx+X8" +
        "8QRKBggAEAIYAFr0AQoQI+5ktRWFTN2BJFMfW20lThIGCAAQARgBGgYIABABGAAyFA0AAEtDFQAAwEAdAADgQiUAABBBQI7H5fzxBFKoAa5ni0OkcP1Ae9SXQwrXH0GPgptDXI8GQY8CnUOF6/lAj0" +
        "KdQx+FD0FcT51Dw/UsQY9CnUPsUUBB9iiYQylcY0EUbpJD7FFoQWbmkEPsUWhBSCGKQ3sUQkGFa3lD4XpAQR+FakM9CltBUnhnQz0KW0FSeFhD7FFAQZoZS0PsUUBBmhlLQwAAyEAfBUxDzczEQB8F" +
        "W0OF6/lAHwV5Q4Xr+UCPAoRDzczEQGVPG6BAZQAAEEFa1AEKEI+M9jyekkNXlPmvatWDzWESBggAEAEYARoGCAAQARgAMhQNAABMQhUAAKBAHQAA4EIlAAAQQUCOx+X88QRSiAEfBQFDhev5QB8FEE" +
        "PNzMRAHwUfQ4Xr+UBm5iJDhev5QGbmIkMK10tBUngcQ+xRQEEfhQFD7FFAQT0K5UI9CltBpPDeQj0KW0Gk8MBCPQo/QT2KpUJ7FB5BexRaQuxRUEFI4U1C7FFQQXsUTEJcjxZBexRYQsP1DEE9CopC" +
        "zczEQD0KqEIpXK9AZQAAAABlDnRqQCqOAgoQXsf/6BZrQkyd3hU107HYIRIGCAEQARgCGgYIABABGAAgACrKAQoQyATpXBRJQ+iNzNcngJN0lxE9YZGyVyXIQRgKIIMCKPwNMhTEw8M/6AMJAAAAAA" +
        "AAAAAAgD8AADqMAQAAVEIAACZCAAAAAJkZAACmQgAAEELAJ+g8mRkAAOJCAAA0QmDmbz2ZGQAAD0MAABBCEPq0PZkZAAAtQwAANELANvI9mRkAAEtDAAAQQmACGD6ZGQAAaUMAADRCAOAyPpkZAICD" +
        "QwAAEEIQVFE+mRmqW5JDhFo0Qii+bT79FQCAnEMAACJC9EiGPkcNQAEyFA0AAEhCFQAAEEIdAICEQyUAABBBQODs1Mu6BCorChDZceDKgjRKRrmuQ5XmcKTsEgYIAhABGAMaBggAEAIYACABQOHXpu" +
        "mLBjoGCAAQABgAQhC5RIV1T99JeYOHeHBZ0I1x"

    /// 2번 획을 bitmap 지우개로 완전히 지운 뒤 (1083 bytes)
    static let afterFullErase =
        "AXdyZPABAAgAEhAAAAAAAAAAAAAAAAAAAAAAEhAfLpB9kMpABIMQo+Qqe0aLEhBsLN/gIkpBpIb5KDbJcFTDGgYIABAAGAAaBggEEAEYBBoGCAQQAhgAIjcKFA0AAAAAFQAAAAAdAAAAACUAAIA/Eh" +
        "Rjb20uYXBwbGUuaW5rLnBlbmNpbBgDQVo7HX94eOi/IjcKFA0AAAAAFQAAAAAdAAAAACUAAAAAEhRjb20uYXBwbGUuaW5rLmVyYXNlchgDQQAAAAAAAAAAKs4FChCc+N3pm0xBe42oX/xsApGNEgYI" +
        "ABABGAEaBggAEAEYACAAKsoBChDUgXulu7tANI48W8/71qEqEa0w5apXJchBGAoggwIo/A0yFMTDwz/oAwkAAAD0NwAAAACAPwAAOowBAABUQgAAOEEAAAAAmRkAAKZCAACwQMCp+TyZGQAA4kIAAH" +
        "hBYC9sPZkZAAAPQwAAsEAg3bI9mRkAAC1DAAB4QbCZ8D2ZGQAAS0MAALBACHISPpkZAABpQwAAeEFQajE+mRkAgINDAACwQOCOUD7LGQCAkkMAAHhBGPRuPtcTAICcQwAAKEEI84Q+DwxAAUCAx+X8" +
        "8QRKBggAEAIYAFr0AQoQI+5ktRWFTN2BJFMfW20lThIGCAAQARgBGgYIABABGAAyFA0AAEtDFQAAwEAdAADgQiUAABBBQI7H5fzxBFKoAa5ni0OkcP1Ae9SXQwrXH0GPgptDXI8GQY8CnUOF6/lAj0" +
        "KdQx+FD0FcT51Dw/UsQY9CnUPsUUBB9iiYQylcY0EUbpJD7FFoQWbmkEPsUWhBSCGKQ3sUQkGFa3lD4XpAQR+FakM9CltBUnhnQz0KW0FSeFhD7FFAQZoZS0PsUUBBmhlLQwAAyEAfBUxDzczEQB8F" +
        "W0OF6/lAHwV5Q4Xr+UCPAoRDzczEQGVPG6BAZQAAEEFa1AEKEI+M9jyekkNXlPmvatWDzWESBggAEAEYARoGCAAQARgAMhQNAABMQhUAAKBAHQAA4EIlAAAQQUCOx+X88QRSiAEfBQFDhev5QB8FEE" +
        "PNzMRAHwUfQ4Xr+UBm5iJDhev5QGbmIkMK10tBUngcQ+xRQEEfhQFD7FFAQT0K5UI9CltBpPDeQj0KW0Gk8MBCPQo/QT2KpUJ7FB5BexRaQuxRUEFI4U1C7FFQQXsUTEJcjxZBexRYQsP1DEE9CopC" +
        "zczEQD0KqEIpXK9AZQAAAABlDnRqQCorChBex//oFmtCTJ3eFTXTsdghEgYIARABGAIaBggAEAEYACAAQOHs1Mu6BCorChDZceDKgjRKRrmuQ5XmcKTsEgYIAhABGAMaBggAEAIYACABQOHXpumLBi" +
        "orChCX4Y1lt8RGp4SeEdDMgfC4EgYIAxABGAQaBggAEAIYACABQOHdy+3iBzoGCAAQABgAQhC5RIV1T99JeYOHeHBZ0I1x"
}

/// fixture 를 디코드하기 위한 헬퍼.
private func drawing(_ base64: String) throws -> PKDrawing {
    let data = try #require(Data(base64Encoded: base64))
    return try PKDrawing(data: data)
}

/// 설계 문서 §7-2 의 `StrokeIdentityKey` 후보. 마스크를 제외한 식별 정보만 담는다.
private struct IdentityKey: Hashable {
    let randomSeed: UInt32
    let creationTime: TimeInterval
    let pointCount: Int

    init(_ stroke: PKStroke) {
        randomSeed = stroke.randomSeed
        creationTime = stroke.path.creationDate.timeIntervalSince1970
        pointCount = stroke.path.count
    }
}

@Suite("Phase 0A-S1 — PencilKit 데이터 모델")
struct PencilKitDataModelTesting {

    // MARK: - S1-1 randomSeed 라운드트립

    @Test("S1-1 randomSeed 는 dataRepresentation() 라운드트립에서 보존된다")
    func randomSeedSurvivesDataRepresentationRoundTrip() throws {
        let seed: UInt32 = 0xDEAD_BEEF
        let creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let path = PKStrokePath(controlPoints: Self.controlPoints(count: 8), creationDate: creationDate)
        let stroke = PKStroke(ink: PKInk(.pencil, color: .black), path: path, randomSeed: seed)

        let restored = try drawing(PKDrawing(strokes: [stroke]).dataRepresentation().base64EncodedString())

        #expect(restored.strokes.count == 1)
        let round = try #require(restored.strokes.first)
        #expect(round.randomSeed == seed)
        #expect(round.path.count == 8)
        #expect(abs(round.path.creationDate.timeIntervalSince1970 - creationDate.timeIntervalSince1970) < 0.001)
    }

    @Test("S1-1 randomSeed 는 앱이 실제로 저장한 블롭에서도 보존된다")
    func randomSeedSurvivesRealAppRoundTrip() throws {
        let before = try drawing(EraserFixture.beforeErase)
        #expect(before.strokes.map(\.randomSeed) == [956_091_164, 491_497_907])
    }

    // MARK: - S1-5 mask / maskedPathRanges 라운드트립

    @Test("S1-5 mask 와 maskedPathRanges 는 dataRepresentation() 라운드트립에서 보존된다")
    func maskSurvivesDataRepresentationRoundTrip() throws {
        let creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let path = PKStrokePath(controlPoints: Self.controlPoints(count: 8), creationDate: creationDate)
        let mask = UIBezierPath(rect: CGRect(x: 0, y: -20, width: 40, height: 60))
        let stroke = PKStroke(ink: PKInk(.pencil, color: .black), path: path, mask: mask, randomSeed: 42)

        #expect(stroke.mask != nil)
        let originalRanges = stroke.maskedPathRanges

        let restored = try drawing(PKDrawing(strokes: [stroke]).dataRepresentation().base64EncodedString())
        let round = try #require(restored.strokes.first)

        #expect(round.mask != nil)
        #expect(round.randomSeed == 42)
        #expect(round.maskedPathRanges.count == originalRanges.count)
        for (lhs, rhs) in zip(round.maskedPathRanges, originalRanges) {
            #expect(abs(lhs.lowerBound - rhs.lowerBound) < 0.001)
            #expect(abs(lhs.upperBound - rhs.upperBound) < 0.001)
        }
    }

    @Test("S1-5 지우개가 만든 mask 는 앱 저장 블롭에서도 보존된다")
    func maskSurvivesRealAppRoundTrip() throws {
        let after = try drawing(EraserFixture.afterPartialErase)
        let masked = after.strokes.filter { $0.mask != nil }

        #expect(masked.count == 2)
        // 남은 가시 구간(parametric range)이 좌/우로 나뉘어 있다.
        let ranges = masked.flatMap(\.maskedPathRanges).sorted { $0.lowerBound < $1.lowerBound }
        #expect(ranges.count == 2)
        #expect(ranges[0].lowerBound == 0)
        #expect(ranges[0].upperBound < ranges[1].lowerBound)
        // mask 가 없는 stroke 의 maskedPathRanges 는 "빈 배열"이 아니라 path 전체 구간이다.
        let untouched = try #require(after.strokes.first { $0.mask == nil })
        #expect(untouched.maskedPathRanges == [0...CGFloat(untouched.path.count - 1)])
    }

    // MARK: - S1-2 bitmap 지우개는 분할인가 마스킹인가

    @Test("S1-2 bitmap 지우개는 획을 '분할'하면서 동시에 각 조각에 mask 를 붙인다")
    func bitmapEraserSplitsStrokeAndMasksEachFragment() throws {
        let before = try drawing(EraserFixture.beforeErase)
        let after = try drawing(EraserFixture.afterPartialErase)

        // 획 하나의 중간만 지웠는데 stroke 수가 2 → 3 으로 늘어난다.
        #expect(before.strokes.count == 2)
        #expect(after.strokes.count == 3)

        let original = try #require(before.strokes.first { $0.randomSeed == 956_091_164 })
        let fragments = after.strokes.filter { $0.randomSeed == 956_091_164 }
        #expect(fragments.count == 2)

        // 조각들은 원본 path 를 '잘라 갖는' 것이 아니라 원본 path 를 그대로 공유한다.
        for fragment in fragments {
            #expect(fragment.path.count == original.path.count)
            #expect(fragment.path.creationDate == original.path.creationDate)
            #expect(fragment.transform == original.transform)
            #expect(fragment.mask != nil)
        }

        // 구분되는 것은 mask / maskedPathRanges / renderBounds 뿐이다.
        let renderWidths = fragments.map(\.renderBounds.width).sorted()
        #expect(renderWidths.allSatisfy { $0 < original.renderBounds.width })
        #expect(fragments[0].renderBounds != fragments[1].renderBounds)
    }

    @Test("S1-2 결과: IdentityKey(randomSeed+creationTime+pointCount) 는 한 drawing 안에서 유일하지 않다")
    func identityKeyCollidesAfterBitmapErase() throws {
        let after = try drawing(EraserFixture.afterPartialErase)
        let keys = after.strokes.map(IdentityKey.init)

        // stroke 는 3개인데 서로 다른 IdentityKey 는 2개뿐이다 → 1:1 dictionary 로 쓸 수 없다.
        #expect(keys.count == 3)
        #expect(Set(keys).count == 2)
    }

    // MARK: - S1-3 완전히 지운 stroke 의 행방

    @Test("S1-3 완전히 지운 stroke 는 drawing.strokes 에서 제거된다 (마스킹된 채 남지 않는다)")
    func fullyErasedStrokeIsRemovedFromDrawing() throws {
        let before = try drawing(EraserFixture.beforeErase)
        let after = try drawing(EraserFixture.afterFullErase)

        #expect(before.strokes.contains { $0.randomSeed == 491_497_907 })
        #expect(!after.strokes.contains { $0.randomSeed == 491_497_907 })
        // 같은 편집에서 부분만 지운 다른 획의 조각들은 그대로 남아 있다.
        #expect(after.strokes.count == 2)
        #expect(after.strokes.allSatisfy { $0.randomSeed == 956_091_164 })
        // 완전히 지워진 stroke 가 "renderBounds 가 비어 있는 stroke" 로 남지도 않는다.
        #expect(after.strokes.allSatisfy { !$0.renderBounds.isEmpty })
    }

    // MARK: - S1-4 지우개 후 IdentityKey 구성요소의 변화

    @Test("S1-4 지우개는 creationDate / randomSeed / path.count 를 바꾸지 않는다")
    func eraseKeepsCreationDateRandomSeedAndPointCount() throws {
        let before = try drawing(EraserFixture.beforeErase)
        let after = try drawing(EraserFixture.afterPartialErase)

        let original = try #require(before.strokes.first { $0.randomSeed == 956_091_164 })
        let originalKey = IdentityKey(original)

        for fragment in after.strokes.filter({ $0.randomSeed == 956_091_164 }) {
            #expect(IdentityKey(fragment) == originalKey)
        }

        // 반면 renderBounds 는 가시 영역만 남도록 줄어든다 → "가시 획" 판정에 사용할 수 있다.
        let shrunk = after.strokes.filter { $0.randomSeed == 956_091_164 }.map(\.renderBounds)
        #expect(shrunk.allSatisfy { $0.width < original.renderBounds.width })
    }

    // MARK: - 헬퍼

    private static func controlPoints(count: Int) -> [PKStrokePoint] {
        (0..<count).map { index in
            PKStrokePoint(
                location: CGPoint(x: Double(index) * 10, y: 0),
                timeOffset: Double(index) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
    }
}
