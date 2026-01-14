//
//  CustomSlider.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

public struct CustomSlider: View {
    @Binding private var value: CGFloat
    private var minValue: CGFloat
    private var maxValue: CGFloat
    public var isFloat: Bool
    
    public init(value: Binding<CGFloat>, 
                minValue: CGFloat,
                maxValue: CGFloat,
                isFloat: Bool = false) {
        self._value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.isFloat = isFloat
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let sliderLength = geometry.size.width - 85
            HStack(alignment: .center, spacing: 5) {
                Text("-")
                    .font(.title)
                    .fontWeight(.bold)
                
                ZStack(alignment: .leading ) {
                    Rectangle()
                        .fill(Color.black.opacity(0.20))
                        .frame(width:sliderLength, height: 6)
                    
                    Rectangle()
                        .fill(Color.teal)
                        .frame(width: normalizationValue(sliderLength: sliderLength), height: 6)
                    
                    Circle()
                        .fill(Color.teal)
                        .frame(width: 18, height: 18)
                        .offset(x: normalizationValue(sliderLength: sliderLength))
                        .gesture(
                            DragGesture()
                                .onChanged( { (value) in
                                    let newValue = value.location.x / sliderLength * CGFloat(maxValue - minValue) + CGFloat(minValue)
                                    if newValue <= CGFloat(maxValue) && newValue >= CGFloat(minValue) {
                                        self.value = isFloat ? newValue : CGFloat(Int(newValue))
                                    }
                                }))
                }
                .padding(.horizontal)
                
                Text("+")
                    .font(.title)
                    .fontWeight(.bold)
            }
        }
    }
        
    
    private func normalizationValue(sliderLength: CGFloat) -> CGFloat {
        return CGFloat(value - minValue) / CGFloat(maxValue - minValue) * sliderLength
    }
}
