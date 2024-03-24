//
//  LineVO.swift
//  DomainRealm
//
//  Created by 이택성 on 2/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

public class LineVO: Equatable {
    public static func == (lhs: LineVO, rhs: LineVO) -> Bool {
        lhs.linePoints == rhs.linePoints
    }
    
    public var lineColor: UIColor
    public var lineWidth: CGFloat
    public var linePoints: [CGPoint] = []

    public init(lineColor: UIColor,
                lineWidth: CGFloat = 5.0,
                point: CGPoint) {
        self.lineColor = lineColor
        self.lineWidth = lineWidth
        self.linePoints.append(point)
    }

    public init(points: [CGPoint],
                color: UIColor,
                lineWidth: CGFloat = 5.0,
                xScale: CGFloat,
                yScale: CGFloat) {
        self.linePoints = points
        self.lineColor = color
        self.lineWidth = lineWidth
    }
}
