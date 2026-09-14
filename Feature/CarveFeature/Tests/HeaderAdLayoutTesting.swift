//
//  HeaderAdLayoutTesting.swift
//  CarveFeatureTest
//
//  Created by Claude on 9/14/26.
//

@testable import CarveFeature
import Testing

/// 헤더 줄 광고(시안 K2) 폭과 높이. 줄 폭은 헤더 좌우 여백(24pt × 2)을 뺀 값이다.
/// 제목은 가운데 200pt 를 남기고, 광고는 서재 버튼 뒤에 184pt 고정 폭으로 둔다.
/// 본문 설정 버튼은 왼손 모드에서도 오른쪽에 있어 서재 쪽 버튼은 늘 하나다.
struct HeaderAdLayoutTesting {
    @Test("세로 iPad mini 에서는 가운데 제목과 서재 버튼 사이를 광고로 채운다(왼손 모드 포함)")
    func portraitMiniFillsGap() {
        let width = HeaderAdLayout.adWidth(rowWidth: 744 - 48, leadingWidth: HeaderAdLayout.buttonGroupWidth(1))
        #expect(width == 184)
    }

    @Test("가로에서는 자리가 남아도 광고를 넓히지 않고 세로와 같은 폭으로 둔다")
    func landscapeKeepsPortraitAdWidth() {
        let width = HeaderAdLayout.adWidth(rowWidth: 1_133 - 48, leadingWidth: HeaderAdLayout.buttonGroupWidth(1))
        #expect(width == 184)
    }

    @Test("가로 절반 분할처럼 좁은 창에서는 광고를 두지 않는다")
    func narrowWindowHidesAd() {
        let width = HeaderAdLayout.adWidth(rowWidth: 560 - 48, leadingWidth: HeaderAdLayout.buttonGroupWidth(1))
        #expect(width == nil)
    }

    @Test("광고 높이는 헤더 축소를 따라 56pt 에서 44pt 로 줄고 범위를 넘지 않는다")
    func heightFollowsCollapse() {
        #expect(HeaderAdLayout.height(collapseProgress: 0) == 56)
        #expect(HeaderAdLayout.height(collapseProgress: 0.5) == 50)
        #expect(HeaderAdLayout.height(collapseProgress: 1) == 44)
        #expect(HeaderAdLayout.height(collapseProgress: 1.4) == 44)
        #expect(HeaderAdLayout.height(collapseProgress: -0.2) == 56)
    }
}
