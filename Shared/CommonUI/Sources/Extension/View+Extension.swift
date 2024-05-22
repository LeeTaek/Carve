//
//  View+Extension.swift
//  CommonUI
//
//  Created by 이택성 on 2/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

public extension View {
    @ViewBuilder
    func isHidden(_ hidden: Bool, duration: Double = 0.0) -> some View {
        if hidden {
            self
                .frame(height: 0)
                .opacity(0)
                .animation(.easeInOut(duration: duration), value: hidden) // 애
        }
        else {
            self
                .animation(.easeInOut(duration: duration), value: hidden) // 애
            
        }
    }
}
