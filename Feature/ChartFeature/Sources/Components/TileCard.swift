//
//  TileCard.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import UIComponents

struct TileCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            Text(title)
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)

            content()
        }
        .padding(CarveSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .carveSurface(
            .panel,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}
