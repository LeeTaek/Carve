//
//  WidgetNoticeView.swift
//  CarveFeature
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import UIComponents

/// 필사 화면의 위젯 표시 결과 안내(시안 N6).
///
/// 즐겨찾기에 없던 절은 보관까지 했다는 것을 함께 알린다. 실패는 사라지는 안내만 두지 않고 「다시 시도」 를 함께 둔다.
struct WidgetNoticeView: View {
    let notice: CarveDetailFeature.WidgetNotice
    let onRetry: () -> Void

    var body: some View {
        content
            .onChange(of: notice, initial: true) { _, _ in
                AccessibilityNotification.Announcement(message).post()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch notice {
        case .displayed:
            CarveStatusMessage(.success, message: message)
        case .failed:
            CarveStatusMessage(.failure, message: message, onRetry: onRetry)
        }
    }

    private var message: String {
        switch notice {
        case .displayed(let addedToFavorites):
            addedToFavorites ? "즐겨찾기에 추가하고 위젯에 표시했어요" : "위젯에 표시했어요"
        case .failed:
            "위젯에 표시하지 못했어요"
        }
    }
}
