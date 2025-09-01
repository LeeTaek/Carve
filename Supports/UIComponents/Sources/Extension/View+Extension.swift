//
//  View+Extension.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

extension View {
    func pickerTextStyle(isSelected: Bool, selectionColor: Color = .teal) -> some View {
        modifier(PickerStyle(isSelected: isSelected, selectionColor: selectionColor))
    }
    
    func animationEffect(isSelected: Bool, id: String, in namespace: Namespace.ID) -> some View {
        modifier(AnimationEffect(isSelected: isSelected, id: id, namespace: namespace))
    }
}

struct AnimationEffect: ViewModifier {
    var isSelected = true
    var id: String
    var namespace: Namespace.ID
    
    func body(content: Content) -> some View {
        if isSelected {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
