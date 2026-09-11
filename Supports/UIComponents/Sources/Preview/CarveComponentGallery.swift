//
//  CarveComponentGallery.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import SwiftUI

import CarveToolkit
import Resources

/// 디자인 토큰 · 공용 컴포넌트를 한눈에 보는 미리보기(Debug 전용). 앱 화면에서는 쓰지 않는다.
///
/// `TUIST_FOR_PREVIEW=TRUE tuist generate` 로 연 뒤 Xcode 프리뷰에서 라이트 · 다크를 나란히 본다.
/// 마지막 묶음은 시안 D1 을 부품으로 조립해 본 예시이며, 실제 본문 설정 화면에 적용한 것이 아니다.
struct CarveComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.xLarge) {
                GallerySection("색 토큰") { ColorTokenSamples() }
                GallerySection("글자") { TypographySamples() }
                GallerySection("아이콘") { IconSamples() }
                GallerySection("아이콘 버튼 — 기본 · 선택 · 비활성, 팔레트 안") { IconButtonSamples() }
                GallerySection("글자 버튼 — 화면 바탕 위 · 표면 안") { ButtonSamples() }
                GallerySection("표면") { SurfaceSamples() }
                GallerySection("빈 상태 · 상태 알림") { StateSamples() }
                GallerySection("조합 예시 — 시안 D1 본문 설정") { TextSettingsPanelSample() }
            }
            .padding(CarveSpacing.xLarge)
        }
        .background(CarveColor.canvas)
    }
}

private struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            Text(title)
                .font(CarveTypography.sectionTitle)
                .foregroundStyle(CarveColor.secondary)
            content
        }
    }
}

// MARK: - 토큰

private struct ColorTokenSamples: View {
    private let theme: [(String, Color)] = [
        ("canvas", CarveColor.canvas), ("surface", CarveColor.surface), ("selected", CarveColor.selected),
        ("divider", CarveColor.divider), ("ink", CarveColor.ink), ("secondary", CarveColor.secondary),
        ("accent", CarveColor.accent), ("danger", CarveColor.danger), ("scrim", CarveColor.scrim),
        ("fill", CarveColor.fill)
    ]
    private let paper: [(String, Color)] = [
        ("Paper.background", CarveColor.Paper.background),
        ("Paper.text", CarveColor.Paper.text),
        ("Paper.guide", CarveColor.Paper.guide)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            grid(theme)
            Text("필사 영역 전용 — 다크에서도 같은 값")
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)
            grid(paper)
        }
    }

    private func grid(_ tokens: [(String, Color)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: CarveSpacing.small)], spacing: CarveSpacing.small) {
            ForEach(tokens, id: \.0) { name, color in
                VStack(spacing: CarveSpacing.xxSmall) {
                    RoundedRectangle(cornerRadius: CarveRadius.inner)
                        .fill(color)
                        .overlay {
                            RoundedRectangle(cornerRadius: CarveRadius.inner).stroke(CarveColor.divider)
                        }
                        .frame(height: 44)
                    Text(name)
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.ink)
                }
            }
        }
    }
}

private struct TypographySamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            Text("본문 설정 — title").font(CarveTypography.title)
            Text("화면과 필기 — sectionTitle").font(CarveTypography.sectionTitle).foregroundStyle(CarveColor.secondary)
            Text("왼손 사용자용 화면 — body").font(CarveTypography.body)
            Text("글자 크기 · 20 pt — label").font(CarveTypography.label)
            Text("필기 열이 왼쪽으로 가요 — caption").font(CarveTypography.caption).foregroundStyle(CarveColor.secondary)
            Text("여호와는 나의 목자시니 — scripture(나눔명조 20pt)")
                .font(CarveTypography.scripture(ResourcesFontFamily.NanumMyeongjo.regular.font(size: 20)))
        }
        .foregroundStyle(CarveColor.ink)
    }
}

private struct IconSamples: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: CarveSpacing.small)], spacing: CarveSpacing.medium) {
            ForEach(CarveIcon.allCases, id: \.self) { icon in
                VStack(spacing: CarveSpacing.xxSmall) {
                    icon.image
                        .foregroundStyle(CarveColor.ink)
                        .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
                    Text(String(describing: icon))
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                }
            }
        }
    }
}

// MARK: - 조작 부품

private struct IconButtonSamples: View {
    @State private var tool: CarveIcon = .pen
    @State private var penColor = 0
    private let penColors = [Color(hex: 0x303B36), Color(hex: 0x476550), Color(hex: 0x9D7967)]

    var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            HStack(spacing: CarveSpacing.xxSmall) {
                CarveIconButton(.library, accessibilityLabel: "성경 목록 열기") {}
                CarveIconButton(.previous, accessibilityLabel: "이전 장") {}
                    .disabled(true)
                CarveIconButton(.next, accessibilityLabel: "다음 장") {}
                CarveIconButton(.textFormat, accessibilityLabel: "본문 설정", isSelected: true) {}
            }

            HStack(spacing: CarveSpacing.xxSmall) {
                ForEach([CarveIcon.pen, .eraser, .lasso], id: \.self) { icon in
                    CarveIconButton(icon, accessibilityLabel: String(describing: icon), isSelected: tool == icon, background: .plain) {
                        tool = icon
                    }
                }
                ForEach(penColors.indices, id: \.self) { index in
                    Button { penColor = index } label: {
                        CarveColorSwatch(penColors[index], isSelected: penColor == index)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(penColor == index ? .isSelected : [])
                }
                CarveIconButton(.undo, accessibilityLabel: "실행 취소", background: .plain) {}
                CarveIconButton(.redo, accessibilityLabel: "다시 실행", background: .plain) {}
                    .disabled(true)
            }
            .padding(.horizontal, CarveSpacing.xSmall)
            .padding(.vertical, 10)
            .carveSurface(.floatingControl, in: RoundedRectangle(cornerRadius: CarveRadius.card, style: .continuous))
        }
    }
}

private struct ButtonSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            buttons
            buttons
                .padding(CarveSpacing.medium)
                .carveSurface(.panel, in: RoundedRectangle(cornerRadius: CarveRadius.panel, style: .continuous))
        }
    }

    private var buttons: some View {
        HStack(spacing: CarveSpacing.small) {
            Button("필사하러 가기") {}.buttonStyle(.carve(.primary))
            Button("취소") {}.buttonStyle(.carve(.secondary))
            Button("모든 필사 데이터 삭제") {}.buttonStyle(.carve(.destructive))
            Button("본문 모양 초기화") {}.buttonStyle(.carve(.primary)).disabled(true)
        }
    }
}

private struct SurfaceSamples: View {
    var body: some View {
        HStack(spacing: CarveSpacing.medium) {
            sample("floatingControl", .floatingControl)
            sample("panel", .panel)
            sample("solid", .solid)
        }
    }

    private func sample(_ name: String, _ style: CarveSurfaceStyle) -> some View {
        Text(name)
            .font(CarveTypography.label)
            .foregroundStyle(CarveColor.ink)
            .frame(width: 140, height: 72)
            .carveSurface(style, in: RoundedRectangle(cornerRadius: CarveRadius.card, style: .continuous))
    }
}

private struct StateSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            CarveEmptyState(
                "아직 기록이 없어요",
                message: "한 절이라도 필사하면 여기에 쌓여요.",
                actionTitle: "필사하러 가기"
            ) {}
            .frame(width: 440)
            .carveSurface(.solid, in: RoundedRectangle(cornerRadius: CarveRadius.card, style: .continuous))

            HStack(spacing: CarveSpacing.medium) {
                CarveStatusMessage(.success, message: "사진에 저장했어요")
                CarveStatusMessage(.failure, message: "저장하지 못했어요") {}
            }
        }
    }
}

// MARK: - 조합 예시

/// 시안 D1 을 부품으로 조립해 본 것. 실제 화면은 Feature 가 조립한다.
private struct TextSettingsPanelSample: View {
    private enum SampleFont: CaseIterable {
        case gothic, myeongjo, flower

        var title: String {
            switch self {
            case .gothic: "나눔바른고딕"
            case .myeongjo: "나눔명조"
            case .flower: "나눔꽃향기"
            }
        }

        func font(size: CGFloat) -> UIFont {
            switch self {
            case .gothic: ResourcesFontFamily.NanumGothic.regular.font(size: size)
            case .myeongjo: ResourcesFontFamily.NanumMyeongjo.regular.font(size: size)
            case .flower: ResourcesFontFamily.나눔손글씨꽃내음.regular.font(size: size)
            }
        }
    }

    @State private var font = SampleFont.gothic
    @State private var fontSize: CGFloat = 20
    @State private var lineSpace: CGFloat = 30
    @State private var tracking: CGFloat = 1
    @State private var isLeftHanded = false
    @State private var allowsFingerDrawing = false

    private var isDefault: Bool {
        font == .gothic && fontSize == 20 && lineSpace == 30 && tracking == 1
    }

    var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader("본문 설정")

            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                CarveSettingsSection("글꼴") {
                    CarveSegmentedPicker(selection: $font, items: SampleFont.allCases) { item in
                        Text(item.title)
                            .font(CarveTypography.scripture(item.font(size: 14)))
                    }
                }
                CarveLabeledSlider("글자 크기", value: $fontSize, in: 15...40, step: 1, valueText: "\(Int(fontSize)) pt")
                CarveLabeledSlider("줄 간격", value: $lineSpace, in: 5...70, step: 1, valueText: "\(Int(lineSpace))")
                CarveLabeledSlider("자간", value: $tracking, in: 1...10, step: 1, valueText: "\(Int(tracking))")
            }
            .padding(CarveSpacing.large)

            CarveDivider()

            CarveSettingsSection("화면과 필기") {
                CarveSettingsRow("왼손 사용자용 화면", description: "필기 열이 왼쪽으로 가요", isOn: $isLeftHanded)
                CarveSettingsRow("손가락 필사 허용", description: "끄면 Apple Pencil로만 필사할 수 있어요", isOn: $allowsFingerDrawing)
            }
            .padding(.horizontal, CarveSpacing.large)
            .padding(.vertical, CarveSpacing.medium)

            CarveDivider()

            Button("본문 모양 초기화") {
                font = .gothic
                fontSize = 20
                lineSpace = 30
                tracking = 1
            }
            .buttonStyle(.carve(.primary, fillsWidth: true))
            .disabled(isDefault)
            .padding(CarveSpacing.large)
        }
        .frame(width: 350)
        .carveSurface(.panel, in: RoundedRectangle(cornerRadius: CarveRadius.panel, style: .continuous))
    }
}

#Preview("갤러리 · 라이트") {
    CarveComponentGallery()
}

#Preview("갤러리 · 다크") {
    CarveComponentGallery()
        .preferredColorScheme(.dark)
}

#Preview("D1 조합 · 라이트") {
    TextSettingsPanelSample()
        .padding(CarveSpacing.xLarge)
        .background(CarveColor.canvas)
}

#Preview("J3 조합 · 다크") {
    TextSettingsPanelSample()
        .padding(CarveSpacing.xLarge)
        .background(CarveColor.canvas)
        .preferredColorScheme(.dark)
}
#endif
