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
    
    
    func textHeightFrom(width: CGFloat, 
                        fontName: String = "System Font",
                        fontSize: CGFloat = .zero) -> CGFloat {
#if os(macOS)
        typealias UXFont = NSFont
        let text: NSTextField = .init(string: self)
        text.font = NSFont.init(name: fontName, size: fontSize)
#else
        typealias UXFont = UIFont
        let text: UILabel = .init()
        text.text = self
        text.numberOfLines = 0
#endif
        
        text.font = UXFont.init(name: fontName, size: fontSize)
        text.lineBreakMode = .byWordWrapping
        return text.sizeThatFits(CGSize.init(width: width, height: .infinity)).height
    }
}
