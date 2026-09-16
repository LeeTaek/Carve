//
//  InkPreview.swift
//  CarveFeature
//
//  시안 P1 · P2 의 「선택한 색상」 · 굵기 미리보기 물결.
//

import SwiftUI

import UIComponents

/// 고른 색과 굵기로 그린 물결 한 줄. 팔레트 세부 팝오버 두 곳(P1 색상 · P2 굵기)이 같은 그림을 쓴다.
///
/// 잉크 색은 사용자가 고른 필기 색이라 외관(라이트 · 다크)에 따라 바꾸지 않는다 —
/// 필사 영역이 다크에서도 종이를 유지하는 것과 같은 이유다(결정 8-1 안 1). 바탕만 표면색을 쓴다.
struct InkPreview: View {
    let color: Color
    /// PencilKit 의 선 두께(pt). 화면 미리보기도 같은 값으로 그린다.
    let lineWidth: CGFloat

    /// 시안의 물결은 한 줄에 1.5 주기다.
    private static let periods: CGFloat = 1.5
    private static let height: CGFloat = 64

    var body: some View {
        Canvas { context, size in
            context.stroke(
                Self.wave(in: size),
                with: .color(color),
                style: StrokeStyle(lineWidth: max(1, lineWidth), lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: CarveRadius.control))
        .accessibilityHidden(true)
    }

    /// 가로를 꽉 채우는 사인 곡선. 위아래 여백은 선 굵기만큼 남긴다.
    static func wave(in size: CGSize) -> Path {
        let midY = size.height / 2
        let amplitude = max(0, min(size.height / 2 - 12, 16))
        let steps = 64
        return Path { path in
            for step in 0...steps {
                let ratio = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(
                    x: size.width * ratio,
                    y: midY - sin(ratio * 2 * .pi * periods) * amplitude
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }
}
