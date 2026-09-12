//
//  CardSection.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import UIComponents

struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            Text(title)
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)

            content()
        }
        .padding(.horizontal, CarveSpacing.large)
        .padding(.vertical, CarveSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .carveSurface(
            .panel,
            in: RoundedRectangle(cornerRadius: CarveRadius.card, style: .continuous)
        )
    }
}
