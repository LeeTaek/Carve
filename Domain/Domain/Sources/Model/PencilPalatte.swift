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

/// 펜 색상, 펜 종류(Pencil/Marker 등), 선 두께 등 펜 설정 모델.
public struct PencilPalatte: Codable, Sendable {
    /// 현재 선택된 펜의 색상.
    public var lineColor: CodableColor
    /// 펜의 종류(연필, 펜, 마커 등)를 나타내는 PencilKit InkType.
    public var pencilType: PKInkingTool.InkType
    /// 펜의 선 두께 값.
    public var lineWidth: CGFloat
    
    /// 기본 펜 설정 값. (검정색 연필, 선 두께 4pt)
    public static let initialState: Self = .init(
        lineColor: .init(color: .black),
        pencilType: .pencil,
        lineWidth: 4
    )
}

/// PencilKit의 InkType을 Codable로 확장, PencilPalatte를 JSON으로 저장/복원할 때 사용.
extension PKInkingTool.InkType: Codable { }
