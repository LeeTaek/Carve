//
//  View+Extension.swift
//  Core
//
//  Created by 이택성 on 7/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

extension View {
    
    /// 뷰 흔드는 애니메이션
    /// - Parameters:
    ///   - trigger: true인 경우 view 흔듬
    ///   - amount: 흔드는 강도
    ///   - shakesPerUnit: 흔들림 횟수
    public func shakeAnimation(
        trigger: Binding<Bool>,
        amount: CGFloat = 10,
        shakesPerUnit: CGFloat = 3
    ) -> some View {
        self.modifier(ShakeEffect(amount: amount,
                                  shakesPerUnit: shakesPerUnit,
                                  animatableData: trigger.wrappedValue ? 1 : 0))
    }
    
    
    /// 특정 터치 타입에 컨텍스트 메뉴 무시하도록 설정(ex. 펜슬로 롱제스처 무시 등)
    /// - Parameters:
    ///   - ignoringType: 무시할 터치 타입
    ///   - menu: 표시할 UIMenu
    public func touchIgnoringContextMenu(
        ignoringType: UITouch.TouchType,
        _ menu: @escaping () -> UIMenu
    ) -> some View {
        self.modifier(TouchIgnoringContextMenuModifier(ignoringType: ignoringType, menu: menu))
    }
    
    
    /// 두 손가락으로 더블탭 하는 제스처 감지
    /// - Parameter action: 더블탭 시 실행할 액션
    public func onTwoFingerDoubleTap(perform
                                     action: @escaping () -> Void) -> some View {
        overlay(TwoFingerTapDoubleTapView(action: action))
    }
    
    /// insetGrouped의 섹션 콘텐츠를 카드처럼 띄워 보이게 하는 스타일
    /// - Note: List의 row background는 clear로 두고, 콘텐츠 자체에 배경+그림자를 준다.
    public func sectionCardShadow(
        cornerRadius: CGFloat = 12,
        shadowRadius: CGFloat = 10,
        shadowX: CGFloat = 6,
        shadowY: CGFloat = 8
    ) -> some View {
        self
            // 배경색은 호출한 View에 이미 적용된 값을 그대로 사용
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // 아래-오른쪽으로 떨어지는 그림자
            .shadow(
                color: Color.Brand.accent.opacity(0.05),
                radius: shadowRadius,
                x: shadowX,
                y: shadowY
            )
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
