//
//  PencilPalatte.swift
//  Domain
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
@preconcurrency import PencilKit

public struct PencilPalatte: Codable, Sendable {
    public var color: ChoosedColor
    public var pencilType: PKInkingTool.InkType
    public var lineWidth: CGFloat
    
    public static let initialState: Self = .init(color: .color1,
                                                 pencilType: .pencil,
                                                 lineWidth: 4)
}

public enum ChoosedColor: Int, Codable, Sendable {
    case color1 = 0
    case color2
    case color3
}

extension PKInkingTool.InkType: Codable { }

extension UIColor: @retroactive Identifiable { }
