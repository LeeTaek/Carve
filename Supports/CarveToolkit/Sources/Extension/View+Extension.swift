//
//  View+Extension.swift
//  Core
//
//  Created by 이택성 on 7/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

extension View {
    public func shakeAnimation(trigger: Binding<Bool>,
                               amount: CGFloat = 10,
                               shakesPerUnit: CGFloat = 3)
    -> some View {
        self.modifier(ShakeEffect(amount: amount,
                                  shakesPerUnit: shakesPerUnit,
                                  animatableData: trigger.wrappedValue ? 1 : 0))
    }
    
}

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        return ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakesPerUnit), y: 0))
    }
}
