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

    public init(store: StoreOf<SponsorAdSlotFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Color.clear
            if let adView = store.adView {
                UIViewEmbedContainer { adView }
            }
        }
    }
}
