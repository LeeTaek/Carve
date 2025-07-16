//
//  PencilPalatte.swift
//  Domain
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import SwiftUI
@preconcurrency import PencilKit

public struct PencilPalatte: Codable, Sendable {
    public var lineColor: CodableColor
    public var pencilType: PKInkingTool.InkType
    public var lineWidth: CGFloat
    
    public static let initialState: Self = .init(lineColor: .init(color: .black),
                                                 pencilType: .pencil,
                                                 lineWidth: 4)
}

extension PKInkingTool.InkType: Codable { }
