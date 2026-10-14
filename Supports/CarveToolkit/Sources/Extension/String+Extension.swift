//
//  String+Extension.swift
//  Shared
//
//  Created by 이택성 on 1/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

public extension String {
    subscript(_ index: Int) -> Character {
        return self[self.index(self.startIndex, offsetBy: index)]
    }
    
    subscript(_ range: Range<Int>) -> String {
         let fromIndex = self.index(self.startIndex, offsetBy: range.startIndex)
         let toIndex = self.index(self.startIndex,offsetBy: range.endIndex)
         return String(self[fromIndex..<toIndex])
     }
}
