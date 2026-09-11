//
//  CarvePanelHeader.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 팝오버 · 시트의 제목 줄. 제목과 오른쪽 액션 자리(「완료」 · 개수), 아래 구분선(시안 D · E · F · I).
public struct CarvePanelHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    /// - Parameters:
    ///   - title: 제목. VoiceOver 에서 머리말로 읽힌다.
    ///   - trailing: 오른쪽 자리 — 닫기 · 완료 버튼이나 개수 같은 값.
    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: CarveSpacing.small) {
                Text(title)
                    .font(CarveTypography.title)
                    .foregroundStyle(CarveColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, CarveSpacing.large)
            .padding(.vertical, CarveSpacing.xSmall)
            .frame(minHeight: 56)

            CarveDivider()
        }
    }
}

public extension CarvePanelHeader where Trailing == EmptyView {
    /// 제목만 있는 제목 줄.
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}
