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
