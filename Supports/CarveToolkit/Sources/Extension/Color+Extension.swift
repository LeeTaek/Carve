//
//  Color+Extension.swift
//  CarveToolkit
//
//  Created by 이택성 on 8/12/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

public extension Color {
    init(hex: Int, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double((hex >> 0) & 0xff) / 255

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
