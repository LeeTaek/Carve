//
//  WidgetNoticeView.swift
//  CarveFeature
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import Domain
import UIComponents

/// 필사 화면의 위젯 담기 결과 안내(시안 N6).
///
/// 즐겨찾기에 없던 절은 보관까지 했다는 것을 함께 알린다. 실패는 사라지는 안내만 두지 않고 「다시 시도」 를 함께 둔다.
struct WidgetNoticeView: View {
    let notice: CarveDetailFeature.WidgetNotice
    let onRetry: () -> Void
    /// 화면 언어 — 안내 문구 · 접근성 알림을 이 값으로 만든다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    var body: some View {
        content
            .onChange(of: notice, initial: true) { _, _ in
                AccessibilityNotification.Announcement(message).post()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch notice {
        case .added, .alreadyAdded:
            CarveStatusMessage(.success, message: message)
        case .limitReached, .blocked:
            CarveStatusMessage(.failure, message: message)
        case .failed:
            CarveStatusMessage(.failure, message: message, onRetry: onRetry)
        }
    }

    private var message: String {
        switch notice {
        case .added(let addedToFavorites):
            // 3항 연산을 문구 안에 두면 컴파일러가 한쪽 문구만 카탈로그 추출에 넣는다 — 문구마다 따로 부른다.
            if addedToFavorites {
                CarveFeatureCatalog.string("즐겨찾기에 추가하고 위젯에 담았어요", locale: locale)
            } else {
                CarveFeatureCatalog.string("위젯에 담았어요", locale: locale)
            }
        case .alreadyAdded:
            CarveFeatureCatalog.string("이미 위젯에 담긴 말씀이에요", locale: locale)
        case .limitReached:
            CarveFeatureCatalog.string("위젯에는 \(WidgetVerseLimit.maximum)개까지 담을 수 있어요", locale: locale)
        case .failed:
            CarveFeatureCatalog.string("위젯에 담지 못했어요", locale: locale)
        case .blocked(let block):
            CarveFeatureCatalog.string("위젯에 담지 않았어요. \(block.reasonText(locale: locale))", locale: locale)
        }
    }
}
