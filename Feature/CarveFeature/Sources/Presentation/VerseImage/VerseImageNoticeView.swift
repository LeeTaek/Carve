//
//  VerseImageNoticeView.swift
//  CarveFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import UIComponents

/// 필사 화면의 이미지 저장 결과 안내(시안 G2).
///
/// 성공은 체크와 문장만 잠깐 보이고, 실패는 사라지는 안내만 두지 않고 「다시 시도」 를 함께 둔다.
/// 사진 추가 권한이 꺼진 경우는 안내가 아니라 확인창으로 알린다. 띄우는 시간은 Feature 가 정한다.
struct VerseImageNoticeView: View {
    let notice: CarveDetailFeature.ImageSaveNotice
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
        case .saved:
            CarveStatusMessage(.success, message: message)
        case .failed:
            CarveStatusMessage(.failure, message: message, onRetry: onRetry)
        }
    }

    private var message: String {
        switch notice {
        case .saved: CarveFeatureCatalog.string("사진에 저장했어요", locale: locale)
        case .failed: CarveFeatureCatalog.string("저장하지 못했어요", locale: locale)
        }
    }
}
