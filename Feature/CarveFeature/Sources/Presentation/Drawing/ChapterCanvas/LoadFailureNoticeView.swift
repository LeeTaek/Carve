//
//  LoadFailureNoticeView.swift
//  CarveFeature
//
//  이 장의 필사를 불러오지 못했을 때의 안내 (로드맵 SAVE-2 리뷰 반영).
//

import SwiftUI

import UIComponents

/// 조회 실패 안내. 불러오지 못한 장은 **쓸 수 없게** 두므로, 사라지는 안내가 아니라 「다시 시도」 를 함께 둔다.
///
/// 기준이 된 내용과 저장소 세대 없이 입력을 열면 그 필기는 저장될 곳이 없다(`ChapterCanvasFeature.blockingLoadFailure`).
/// 이전에는 조회 실패를 상태에만 두고 화면에 보이지 않아, 첫 조회가 실패한 장은 빈 캔버스로 멈춰 있었다.
struct LoadFailureNoticeView: View {
    let failure: DrawingLoadFailure
    let onRetry: () -> Void

    var body: some View {
        CarveStatusMessage(.failure, message: Self.message(for: failure), onRetry: onRetry)
            .onAppear {
                AccessibilityNotification.Announcement(Self.message(for: failure)).post()
            }
    }

    static let message = "이 장의 필사를 불러오지 못했어요"
    /// 이 기기에 남은 초안을 읽지 못했다 — 그 초안 위에 새 필기가 덮이지 않게 쓸 수 없게 둔다(정책 §12-6 구현 순서 ②).
    static let draftsMessage = "이 기기에 남은 필기를 불러오지 못했어요"

    static func message(for failure: DrawingLoadFailure) -> String {
        failure.source == .drafts ? draftsMessage : message
    }
}
