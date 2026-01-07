//
//  TileCard.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 하나의 정사각형 타일 카드
struct TileCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.Brand.ink)

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white)
        .sectionCardShadow()
        // 타일은 가로 폭을 유지하면서 height를 width와 동일하게.
        .aspectRatio(1, contentMode: .fit)
    }
}

