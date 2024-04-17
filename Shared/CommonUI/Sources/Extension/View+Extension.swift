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
    
    
    @ViewBuilder
    func isEmpty(_ empty: Bool) -> some View {
        if empty {
            EmptyView()
        } else {
            self
        }
    }
    
    
    @ViewBuilder
    func onReadSize(_ perform: @escaping (CGRect) -> Void) -> some View {
        self.customBackground {
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, 
                                value: geometryProxy.frame(in: .global))
            }
        }
        .onPreferenceChange(SizePreferenceKey.self, perform: perform)
    }
    
    @ViewBuilder
    func customBackground<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        self.background(alignment: alignment, content: content)
    }
}

public struct SizePreferenceKey: PreferenceKey {
    public static var defaultValue: CGRect = .zero
    public static func reduce(value: inout CGRect, nextValue: () -> CGRect) { }
}
