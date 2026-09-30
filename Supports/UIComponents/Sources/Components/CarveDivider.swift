//
//  CarveDivider.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 표면 안의 1pt 구분선.
public struct CarveDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(CarveColor.divider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
