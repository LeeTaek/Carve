//
//  Color+Extension.swift
//  CarveToolkit
//
//  Created by 이택성 on 8/12/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import Resources

public extension Color {
    init(hex: Int, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double((hex >> 0) & 0xff) / 255

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
    
    /// 앱 전체에서 사용하는 공용 컬러
    enum Brand {
        /// 앱 배경 톤 (Primary)
        public static let background = ResourcesAsset.background.swiftUIColor
        /// cell 배경톤
        public static let cellBackground = ResourcesAsset.cellBackground.swiftUIColor
        /// 서브 텍스트/포인트에 쓰기 좋은 브라운 (Secondary)
        public static let secondary = ResourcesAsset.secondary.swiftUIColor
        /// 잉크/텍스트 블랙
        public static let ink = ResourcesAsset.ink.swiftUIColor
        /// 강조 컬러 (Accent)
        public static let accent = ResourcesAsset.accent.swiftUIColor
    }
}
