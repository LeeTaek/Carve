//
//  CarveSettingsRow.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 설정 행 — 제목 · 설명과 오른쪽 자리(값 · 토글 · 임의 컨트롤)(시안 D · F · I).
///
/// 토글 행은 시스템 `Toggle` 이라 VoiceOver 가 제목 · 설명 · 켬/끔을 한 요소로 읽는다.
public struct CarveSettingsRow<Trailing: View>: View {
    private enum Accessory {
        case toggle(Binding<Bool>)
        case trailing(Trailing)
    }

    private let title: String
    private let description: String?
    private let accessory: Accessory

    /// 오른쪽 자리를 직접 채우는 행.
    /// - Parameters:
    ///   - title: 행 제목.
    ///   - description: 제목 아래 설명. 없으면 제목만 둔다.
    ///   - trailing: 오른쪽 자리.
    public init(_ title: String, description: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.description = description
        self.accessory = .trailing(trailing())
    }

    public var body: some View {
        switch accessory {
        case .toggle(let isOn):
            Toggle(isOn: isOn) { label }
                .tint(CarveColor.accent)
                .frame(minHeight: CarveSize.minimumHitTarget)
        case .trailing(let trailing):
            HStack(spacing: CarveSpacing.small) {
                label
                Spacer(minLength: 0)
                trailing
            }
            .frame(minHeight: CarveSize.minimumHitTarget)
            .accessibilityElement(children: .combine)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
            if let description {
                Text(description)
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension CarveSettingsRow where Trailing == EmptyView {
    /// 토글 행(시안 D 「왼손 사용자용 화면」 · 「손가락 필사 허용」).
    init(_ title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        self.accessory = .toggle(isOn)
    }
}

public extension CarveSettingsRow where Trailing == Text {
    /// 현재 값을 오른쪽에 적는 행(시안 F 「필사 캔버스 · 단일」 · 「앱 버전 · 1.3.1」).
    init(_ title: String, description: String? = nil, value: String) {
        self.init(title, description: description) {
            Text(value)
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)
        }
    }
}
