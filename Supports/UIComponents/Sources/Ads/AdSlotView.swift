//
//  AdSlotView.swift
//  UIComponents
//
//  Created by 이택성 on 1/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

/// ``SponsorAdSlotFeature`` 가 받은 광고 뷰를 붙인다. 크기와 표시 여부는 놓는 쪽이 정한다.
///
/// 광고가 오기 전에는 빈 자리만 그린다 — 놓는 쪽이 준 크기를 그대로 차지해 광고가 도착해도 주변이 밀리지 않는다.
public struct AdSlotView: View {
    @Bindable public var store: StoreOf<SponsorAdSlotFeature>
    /// 화면 언어 — 앱 안에서 언어를 고르면 앱 루트가 바꾼다. 광고 배지(「광고」 · 「Ad」)를 이 값으로 적는다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    public init(store: StoreOf<SponsorAdSlotFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Color.clear
            if let adView = store.adView {
                // 광고 뷰는 인프라가 따로 만든 UIKit 뷰라 환경을 물려받지 않는다 — 붙일 때와 언어가 바뀌어 이 본문을 다시 그릴 때
                // 배지 문구를 환경 locale 로 다시 적는다(룰북 현지화 9 「따로 만든 호스트」).
                UIViewEmbedContainer { [locale] in
                    NativeAdContentView.updateBadgeText(locale: locale, in: adView)
                    return adView
                }
            }
        }
    }
}
