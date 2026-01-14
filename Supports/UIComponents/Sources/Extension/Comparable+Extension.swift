//
//  Comparable+Extension.swift
//  UIComponents
//
//  Created by 이택성 on 8/29/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

extension Comparable {
    /// ragne를 벗어나는 경우 범위 안으로 제한함
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
