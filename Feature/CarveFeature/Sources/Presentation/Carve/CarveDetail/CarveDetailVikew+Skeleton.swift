//
//  CarveDetailVikew+Skeleton.swift
//  CarveFeature
//
//  Created by 이택성 on 2/26/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

struct DrawingCanvasSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOffset: CGFloat = -1.2
    let linePitch: CGFloat
    let horizontalInset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear

                skeletonBands(in: proxy.size)
                    .padding(.horizontal, horizontalInset)

                if !reduceMotion {
                    skeletonBands(in: proxy.size)
                        .padding(.horizontal, horizontalInset)
                        .foregroundStyle(Color.white.opacity(0.95))
                        .mask {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white,
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: 84)
                            .rotationEffect(.degrees(18))
                            .offset(x: proxy.size.width * shimmerOffset)
                        }
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                shimmerOffset = -1.2
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.2
                }
            }
        }
    }

    @ViewBuilder
    private func skeletonBands(in size: CGSize) -> some View {
        let contentWidth = max(0, size.width - horizontalInset * 2)
        let pitch = max(22, linePitch)
        let bandHeight = max(10, pitch * 0.56)
        let startY = max(8, pitch * 0.18)
        let count = Int(ceil((size.height + pitch) / pitch))

        ZStack(alignment: .topLeading) {
            ForEach(0..<max(0, count), id: \.self) { index in
                let widthRatio: CGFloat = index.isMultiple(of: 4) ? 0.82 : (index.isMultiple(of: 3) ? 0.93 : 0.97)
                let y = startY + (CGFloat(index) * pitch)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.10))
                    .frame(width: contentWidth * widthRatio, height: bandHeight)
                    .offset(x: 0, y: y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
