//
//  Collection+Extension.swift
//  Core
//
//  Created by 이택성 on 5/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

public extension Collection {
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
