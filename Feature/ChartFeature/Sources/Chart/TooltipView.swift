//
//  TooltipView.swift
//  ChartFeature
//
//  Created by 이택성 on 8/12/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

public struct TooltipView: View {
    let text: String
    
    init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(hex: 0xE5089CF5),
                                Color(hex: 0xCC76DAF0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(width: 46, height: 33)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                
                Text(text)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                
            }
        }
    }
}


public struct CustomSymbol: View {
    private func color(for value: Int) -> Color {
        switch value {
        case 0..<5:
            return .red.opacity(0.85)
        case 5..<20:
            return .yellow.opacity(0.85)
        case 20...100:
            return .green.opacity(0.85)
        default:
            return .gray.opacity(0.7)
        }
    }

    let value: Int
    let isSelected: Bool

    public var body: some View {
        ZStack {
            if isSelected == true {
                TooltipView(text: "\(value)")
                    .offset(y: value > 88 ? 28 : -28)
            }

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [color(for: value), color(for: value).opacity(0.5)]),
                        center: .center,
                        startRadius: 3,
                        endRadius: 8
                    )
                )
                .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.3), lineWidth: isSelected ? 3 : 2)
                )
                .shadow(color: color(for: value).opacity(0.7), radius: 8, x: 0, y: 2)
        }
    }
}
