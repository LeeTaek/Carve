//
//  CGFloat+Extension.swift
//  Domain
//
//  Created by 이택성 on 6/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

extension CGFloat: @retroactive Identifiable {
    public var id: CGFloat {
        return self
    }
}
