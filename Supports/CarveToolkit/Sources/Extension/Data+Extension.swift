//
//  Data+Extension.swift
//  Core
//
//  Created by 이택성 on 7/15/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import PencilKit

public extension Data {
    ///  stroke가 있는 경우 true
    var containsPKStroke: Bool {
        guard let drawing = try? PKDrawing(data: self) else {
            return false
        }
        return !drawing.strokes.isEmpty
    }
    
    /// 필사 데이터 mock Data
    static var mockDrawing: Data {
        var points: [PKStrokePoint] = []
        for i in 0..<30 {
            let x = CGFloat(i) * 2
            let y = sin(CGFloat(i) * 0.1) * 50 + 100
            let point = PKStrokePoint(
                location: CGPoint(x: x, y: y),
                timeOffset: TimeInterval(i) * 0.01,
                size: CGSize(width: 2, height: 2),
                opacity: 1.0,
                force: 0.5,
                azimuth: 0,
                altitude: .pi / 2
            )
            points.append(point)
        }
        
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(ink: PKInk(.pen, color: .blue), path: path)
        
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }
}
