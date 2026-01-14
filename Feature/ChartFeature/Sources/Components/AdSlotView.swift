//
//  AdSlot.swift
//  ChartFeature
//
//  Created by 이택성 on 1/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import ClientInterfaces
import UIComponents
import CarveToolkit

import ComposableArchitecture

public struct AdSlotView: View {
    @Bindable public var store: StoreOf<SponsorAdSlotFeature>

    public init(store: StoreOf<SponsorAdSlotFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120)

            Group {
                if let adView = store.adView {
                    UIViewEmbedContainer { adView }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 120)
                } else if store.isLoading {
                    EmptyView()
                }
            }
        }
    }
}
