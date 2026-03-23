//
//  CardSection.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 제목 + 카드 콘텐츠
struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.Brand.ink)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .sectionCardShadow()
        }
    }
}
