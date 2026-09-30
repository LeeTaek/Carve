//
//  View+Extension.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

extension View {
    
    /// ScrollView 내부에서 Y offset 변화 감지
    /// - Parameter completion: (이전/현재) 스크롤값
    @ViewBuilder
    func offsetY(completion: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        self.modifier(OffsetHelper(onChange: completion))
    }
    
    /// 현재 UIWindowScene의 safeAreaInsets를 반환.
    func safeArea() -> UIEdgeInsets {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return .zero }
        guard let safeArea = scene.windows.first?.safeAreaInsets else { return .zero }
        return safeArea
        
    }
    
}

/// ScrollView 내 콘텐츠의 Y offset 측정하고, 변경 시 콜백을 호출하는 ViewModifier.
struct OffsetHelper: ViewModifier {
    var onChange: (CGFloat, CGFloat) -> Void
    /// 현재 프레임의 Y 오프셋.
    @State var currentOffset: CGFloat = 0
    /// 직전 프레임의 Y 오프셋.
    @State var previousOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let minY = proxy.frame(in: .named("Scroll")).minY
                    Color.clear
                        .preference(key: OffsetKey.self, value: minY)
                        .onPreferenceChange(OffsetKey.self) { value in
                            previousOffset = currentOffset
                            currentOffset = value
                            onChange(previousOffset, currentOffset)
                        }
                }
            }
    }
}

/// Y 오프셋 값을 상위 뷰로 전달하기 위한 PreferenceKey.
struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 헤더 뷰의 frame(anchor)을 상위로 전달하기 위한 PreferenceKey.
struct HeaderBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue()
    }
}
