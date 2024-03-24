//
//  Line.swift
//  CoreRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import RealmSwift

public class LineDTO: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var lineColor: Color
    @Persisted var lineWidth: CGFloat
    @Persisted var linePoints: RealmSwift.List<CGPoint>
    
    public convenience init(lineColor: Color,
                            lineWidth: CGFloat = 5.0,
                            linePoints: RealmSwift.List<CGPoint> = RealmSwift.List<CGPoint>()) {
        self.init()
        self.lineColor = lineColor
        self.lineWidth = lineWidth
        self.linePoints = linePoints
    }
    
    public convenience init(points: RealmSwift.List<CGPoint>,
                            color: Color,
                            lineWidth: CGFloat = 5.0,
                            xScale: CGFloat,
                            yScale: CGFloat) {
        self.init()
        self.linePoints = points
        self.lineColor = color
        self.lineWidth = lineWidth
    }
}
