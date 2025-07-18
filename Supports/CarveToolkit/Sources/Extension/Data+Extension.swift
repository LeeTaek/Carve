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
}
