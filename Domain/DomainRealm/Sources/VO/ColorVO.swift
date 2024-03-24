//
//  ColorVO.swift
//  DomainRealm
//
//  Created by 이택성 on 2/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

public class ColorVO {
    var red: Double = .zero
    var green: Double = .zero
    var blue: Double = .zero
    var opacity: Double = .zero

    public init(color: Color) {
        if let components = color.cgColor?.components {
            if components.count >= 3 {
                self.red = components[0]
                self.green = components[1]
                self.blue = components[2]
            }
            if components.count >= 4 {
                self.opacity = components[3]
            }
        }
    }
}
