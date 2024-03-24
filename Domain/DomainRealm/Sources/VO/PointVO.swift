//
//  PointVO.swift
//  DomainRealm
//
//  Created by 이택성 on 2/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

public class PointVO {
    var x: Double
    var y: Double
    
    public init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }
}
