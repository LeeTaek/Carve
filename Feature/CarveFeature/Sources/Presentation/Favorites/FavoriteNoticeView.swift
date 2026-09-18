//
//  FavoriteNoticeView.swift
//  CarveFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import Domain
import UIComponents

/// 필사 화면의 즐겨찾기 결과 안내(시안 N2).
///
/// 추가는 채운 별과 문장만 잠깐 보인다. 해제는 절 번호 아래 별이 사라지는 것으로 알 수 있어 따로 알리지 않는다(시안에 없음).
/// 실패는 사라지는 안내만 두지 않고 「다시 시도」 를 함께 둔다(문서 7장 문구). 띄우는 시간은 Feature 가 정한다.
struct FavoriteNoticeView: View {
    let notice: CarveDetailFeature.FavoriteNotice
    let onRetry: () -> Void

    /// 안내 줄 높이(시안 52pt). 접힌 도구 원과 세로 가운데를 맞출 때 쓴다.
    static let height: CGFloat = 52

    var body: some View {
        content
            .onChange(of: notice, initial: true) { _, _ in
                AccessibilityNotification.Announcement(message).post()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch notice {
        case .added:
            HStack(spacing: CarveSpacing.small) {
                CarveIcon.starFill.image
                    .foregroundStyle(CarveColor.accent)
                    .accessibilityHidden(true)
                Text(message)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
            }
            .padding(.horizontal, CarveSpacing.medium)
            .frame(minWidth: 320, minHeight: Self.height, alignment: .leading)
            // 시안 N2 는 표면색(#F0EFEA) 사각형이다 — 종이 위에서 구분되도록 불투명 표면을 쓴다.
            .carveSurface(.opaquePanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
        case .failed:
            CarveStatusMessage(.failure, message: message, onRetry: onRetry)
        case .blocked:
            CarveStatusMessage(.failure, message: message)
        }
    }

    private var message: String {
        switch notice {
        case .added:
            "즐겨찾기에 추가했어요"
        case .failed(let change):
            change.isAdding ? "즐겨찾기에 추가하지 못했어요" : "즐겨찾기를 해제하지 못했어요"
        case let .blocked(change, block):
            (change.isAdding ? "즐겨찾기에 추가하지 않았어요. " : "즐겨찾기를 해제하지 않았어요. ") + block.reasonText
        }
    }
}

extension SyncedWriteBlock {
    /// 동기화 저장소에 쓰지 않고 막은 사유 — 안내 문구의 뒷문장(정책 §12-6 결정 1).
    var reasonText: String {
        switch self {
        case .signedOut: "iCloud 에 로그인하지 않았어요"
        case .accountUnconfirmed: "iCloud 계정을 확인하는 중이에요"
        case .ownershipUnverified: "이 기기의 필사가 지금 계정의 것인지 아직 확인하지 못했어요"
        case .knowledgeUnreadable: "삭제 기록을 읽지 못했어요"
        }
    }
}
