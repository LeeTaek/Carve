//
//  View+Extension.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

extension View {
    @ViewBuilder
    func offsetY(completion: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        self
            .modifier(OffsetHelper(onChange: completion))
    }
    
    func safeArea() -> UIEdgeInsets {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return .zero }
        guard let safeArea = scene.windows.first?.safeAreaInsets else { return .zero }
        return safeArea
        
    }
    
    func pickerTextStyle(isSelected: Bool, selectionColor: Color = .teal) -> some View {
        modifier(PickerStyle(isSelected: isSelected, selectionColor: selectionColor))
    }
    
    func animationEffect(isSelected: Bool, id: String, in namespace: Namespace.ID) -> some View {
        modifier(AnimationEffect(isSelected: isSelected, id: id, namespace: namespace))
    }
}

struct OffsetHelper: ViewModifier {
    var onChange: (CGFloat, CGFloat) -> Void
    @State var currentOffset: CGFloat = 0
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

struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HeaderBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue()
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
