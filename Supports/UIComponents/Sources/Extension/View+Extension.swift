//
//  View+Extension.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import ClientInterfaces
import Dependencies

extension View {
    func pickerTextStyle(isSelected: Bool, selectionColor: Color = .teal) -> some View {
        modifier(PickerStyle(isSelected: isSelected, selectionColor: selectionColor))
    }
    
    func animationEffect(isSelected: Bool, id: String, in namespace: Namespace.ID) -> some View {
        modifier(AnimationEffect(isSelected: isSelected, id: id, namespace: namespace))
    }
    
    /// Firebase `analyticsScreen` 대신, App에서 주입한 `analyticsClient`를 통해 화면 노출을 기록.
    /// - Note: `onAppear` 기반이므로, 동일 View가 여러 번 나타날 수 있는 구조에서는 중복 이벤트가 발생할 수 있음.
    @MainActor
    public func trackScreen(
        _ name: String,
        parameters: [String: AnalyticsValue] = [:]
    ) -> some View {
        modifier(
            TrackScreenModifier(
                name: name,
                parameters: parameters
            )
        )
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

private struct TrackScreenModifier: ViewModifier {
    let name: String
    let parameters: [String: AnalyticsValue]

    @Dependency(\.analyticsClient) private var analyticsClient

    func body(content: Content) -> some View {
        content.onAppear {
            analyticsClient.screen(name, parameters: parameters)
        }
    }
}
