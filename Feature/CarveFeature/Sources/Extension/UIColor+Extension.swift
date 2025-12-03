//
//  UIColor+Extension.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import UIKit

extension UIColor {
    /// 현재 투명도
    var alphaValue: CGFloat {
        var alpha: CGFloat = 0
        self.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return alpha
    }
}
