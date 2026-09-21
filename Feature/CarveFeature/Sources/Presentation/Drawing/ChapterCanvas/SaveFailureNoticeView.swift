//
//  SaveFailureNoticeView.swift
//  CarveFeature
//
//  필사가 기기에 저장되지 못했을 때의 안내 (로드맵 SAVE-1).
//

import SwiftUI

import UIComponents

/// 저장 실패 안내. **사라지는 안내로 두지 않는다** — 해결될 때까지 남고 「다시 시도」 를 함께 둔다.
///
/// 실패해도 저장 큐는 보존되고 다음 편집·장 전환에서 자동으로 다시 시도한다(설계 §8-4). 그래도 알리는 이유는
/// 그 재시도가 언제 일어날지 사용자가 알 수 없고, **그 사이에 앱을 닫으면 미저장분이 사라지기** 때문이다.
///
/// - Note: 이 안내는 **기기 저장**에 관한 것이다. iCloud 로 전해졌는지는 별개이며 여기서 말하지 않는다.
struct SaveFailureNoticeView: View {
    /// 지금까지의 재시도 횟수. 1보다 크면 이미 자동으로 다시 시도해 봤다는 뜻이다.
    let retryCount: Int
    let onRetry: () -> Void

    var body: some View {
        CarveStatusMessage(.failure, message: message, onRetry: onRetry)
            .onChange(of: retryCount, initial: true) { _, _ in
                AccessibilityNotification.Announcement(message).post()
            }
    }

    private var message: String {
        // 처음 실패와 반복 실패를 같은 문구로 두지 않는다. 반복되면 사용자가 다른 조치를 생각할 수 있어야 한다.
        retryCount > 1
            ? "필사를 이 기기에 저장하지 못했어요. 저장 공간을 확인해 주세요"
            : "필사를 이 기기에 저장하지 못했어요"
    }
}
