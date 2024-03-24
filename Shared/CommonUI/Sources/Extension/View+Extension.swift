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
    func isHidden(_ hidden: Bool, remove: Bool = false) -> some View {
        if hidden {
            if !remove {
                self.hidden()
            }
        } else {
            self
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
