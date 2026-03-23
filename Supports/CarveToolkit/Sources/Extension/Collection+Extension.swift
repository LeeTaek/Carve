//
//  Collection+Extension.swift
//  CarveToolkit
//
//  Created by 이택성 on 3/23/26.
//

import Foundation

public extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
