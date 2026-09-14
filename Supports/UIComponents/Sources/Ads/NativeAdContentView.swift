//
//  NativeAdContentView.swift
//  UIComponents
//
//  Created by 이택성 on 1/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import UIKit

import Resources

/// 네이티브 광고 자리의 크기(시안 K2 · K3). 광고 SDK 를 모르는 Feature 가 자리를 잡을 때 쓴다.
///
/// 폭 · 높이는 AdMob 네이티브 필수 요소가 잘리지 않는 값이다 — 광고 배지 15px 이상, 제목 한글 12~13자(영문 25자), CTA.
public enum NativeAdMetrics {
    /// 탐색 사이드바 하단 카드 높이.
    public static let sidebarHeight: CGFloat = 124
    /// 차트 스폰서 카드 높이. 16:9 미디어 120pt 와 위아래 여백.
    public static let chartHeight: CGFloat = 148
    /// 차트 스폰서 카드의 미디어 높이. AdMob 은 120 × 120 보다 작은 미디어 자리를 수익에서 뺀다고 예고했다.
    public static let chartMediaHeight: CGFloat = 120
    /// 필사 헤더 줄 광고 폭. 세로 iPad mini 에서 가운데 제목과 서재 버튼 사이를 채우는 폭이고, 가로 화면에서도 넓히지 않는다.
    /// 두 줄 제목(한글 12~13자)과 짧은 CTA 가 잘리지 않는다. 이 폭이 들어가지 않으면 광고를 두지 않는다.
    public static let headerWidth: CGFloat = 184
    /// 펼친 헤더(118pt)에서의 광고 높이.
    public static let headerExpandedHeight: CGFloat = 56
    /// 축소 헤더(78pt)에서의 광고 높이. 축소 줄 안에 들어가야 본문을 가리지 않는다.
    public static let headerCompactHeight: CGFloat = 44
}

public final class NativeAdContentView: UIView {
    /// 광고 위치별 레이아웃.
    public enum Style: Sendable {
        /// 차트 스폰서 카드. 한 줄 전체 폭 가로형이고 16:9 미디어(이미지 · 동영상)를 포함한다.
        case card
        /// 탐색 사이드바 하단 카드(시안 K3).
        case sidebar
        /// 필사 헤더 줄(시안 K2). 폭은 184pt 고정, 높이는 헤더 축소를 따라 56 ↔ 44pt 로 바뀐다.
        case headerStrip

        /// 미디어(`MediaView`)를 두는지. 이미지를 그리지 않는 레이아웃은 두지 않아도 된다(AdMob 네이티브 가이드).
        public var showsMedia: Bool { self == .card }
        /// 본문 문구를 두는지.
        public var showsBody: Bool { self != .headerStrip }
    }

    public let style: Style
    public let adBadgeLabel = UILabel()
    public let mediaContainerView = UIView()
    public let iconImageView = UIImageView()
    public let headlineLabel = UILabel()
    public let bodyLabel = UILabel()
    public let callToActionButton = UIButton(type: .system)

    public init(style: Style) {
        self.style = style
        super.init(frame: .zero)

        switch style {
        case .card:
            setupCardLayout()
        case .sidebar:
            setupSidebarLayout()
        case .headerStrip:
            setupHeaderStripLayout()
        }

        // 기본 상태(광고가 없을 때)
        headlineLabel.text = nil
        bodyLabel.text = nil
        iconImageView.image = nil
        setCallToAction(nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// CTA 문구를 넣는다. 없으면 버튼을 숨긴다.
    public func setCallToAction(_ title: String?) {
        callToActionButton.configuration?.title = title
        callToActionButton.isHidden = title == nil
    }

    // MARK: - 차트 스폰서 카드

    private func setupCardLayout() {
        // 차트 타일 그리드 아래 한 줄 전체 폭 가로형 카드. 바탕은 차트 타일과 같은 표면을 SwiftUI 가 그린다.
        backgroundColor = .clear

        configureBadge(
            font: .systemFont(ofSize: 11, weight: .medium),
            textColor: ResourcesAsset.Theme.accent.color,
            backgroundColor: ResourcesAsset.Theme.selected.color,
            cornerRadius: 5
        )

        mediaContainerView.backgroundColor = ResourcesAsset.Theme.fill.color
        mediaContainerView.layer.cornerRadius = 10
        mediaContainerView.clipsToBounds = true

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.layer.cornerRadius = 8
        iconImageView.clipsToBounds = true

        headlineLabel.numberOfLines = 2
        headlineLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        headlineLabel.textColor = ResourcesAsset.Theme.ink.color

        bodyLabel.numberOfLines = 2
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = ResourcesAsset.Theme.textSecondary.color

        configureCallToAction(
            font: .systemFont(ofSize: 13, weight: .semibold),
            background: ResourcesAsset.Theme.selected.color,
            insets: NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14),
            cornerRadius: nil
        )

        [mediaContainerView, adBadgeLabel, iconImageView, headlineLabel, bodyLabel, callToActionButton].forEach(addLayoutSubview)
        // 세로가 모자라면 본문이 먼저 줄어든다(두 줄 → 한 줄).
        bodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        callToActionButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 미디어 높이는 SDK 미디어 뷰의 고유 크기보다 앞서야 120pt 가 지켜진다. 자리가 아직 0 일 때만 풀리도록 필수 바로 아래로 둔다.
        let mediaHeight = mediaContainerView.heightAnchor.constraint(equalToConstant: NativeAdMetrics.chartMediaHeight)
        mediaHeight.priority = UILayoutPriority(999)
        let bodyBottom = bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: callToActionButton.topAnchor, constant: -6)
        bodyBottom.priority = .defaultHigh
        let bodyTop = bodyLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4)
        bodyTop.priority = .defaultLow

        NSLayoutConstraint.activate([
            // 미디어는 16:9 · 높이 120pt. AdMob 은 120 × 120 보다 작은 미디어 자리를 수익에서 뺀다고 예고했다.
            mediaContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            mediaContainerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            mediaHeight,
            mediaContainerView.widthAnchor.constraint(equalTo: mediaContainerView.heightAnchor, multiplier: 16.0 / 9.0),

            adBadgeLabel.topAnchor.constraint(equalTo: mediaContainerView.topAnchor),
            adBadgeLabel.leadingAnchor.constraint(equalTo: mediaContainerView.trailingAnchor, constant: 16),
            adBadgeLabel.widthAnchor.constraint(equalToConstant: 30),
            adBadgeLabel.heightAnchor.constraint(equalToConstant: 18),

            iconImageView.topAnchor.constraint(equalTo: adBadgeLabel.bottomAnchor, constant: 8),
            iconImageView.leadingAnchor.constraint(equalTo: adBadgeLabel.leadingAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),

            // 오른쪽 위 모서리는 SDK 가 넣는 AdChoices 아이콘 자리라 제목을 배지 아래 줄에서 시작한다.
            headlineLabel.topAnchor.constraint(equalTo: iconImageView.topAnchor),
            headlineLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10),
            headlineLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            bodyTop,
            bodyLabel.topAnchor.constraint(greaterThanOrEqualTo: iconImageView.bottomAnchor, constant: 4),
            bodyLabel.topAnchor.constraint(greaterThanOrEqualTo: headlineLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: adBadgeLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            bodyBottom,

            callToActionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            callToActionButton.bottomAnchor.constraint(equalTo: mediaContainerView.bottomAnchor),
            callToActionButton.heightAnchor.constraint(equalToConstant: 30),
            callToActionButton.widthAnchor.constraint(lessThanOrEqualToConstant: 160)
        ])
    }

    // MARK: - 사이드바 카드(K3)

    private func setupSidebarLayout() {
        // 사이드바 바탕(surface) 위에서 한 단계 밝은 종이색 카드로 목록과 구분한다.
        backgroundColor = ResourcesAsset.Theme.canvas.color
        layer.cornerRadius = CarveRadius.control
        clipsToBounds = true

        configureBadge(
            font: .systemFont(ofSize: 11, weight: .medium),
            textColor: ResourcesAsset.Theme.accent.color,
            backgroundColor: ResourcesAsset.Theme.selected.color,
            cornerRadius: 5
        )

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.layer.cornerRadius = 10
        iconImageView.clipsToBounds = true

        headlineLabel.numberOfLines = 2
        headlineLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        headlineLabel.textColor = ResourcesAsset.Theme.ink.color

        bodyLabel.numberOfLines = 1
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = ResourcesAsset.Theme.textSecondary.color

        configureCallToAction(
            font: .systemFont(ofSize: 13, weight: .semibold),
            background: ResourcesAsset.Theme.selected.color,
            insets: NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14),
            cornerRadius: nil
        )

        [adBadgeLabel, iconImageView, headlineLabel, bodyLabel, callToActionButton].forEach(addLayoutSubview)
        callToActionButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 자리가 아직 0 일 때 제약이 충돌하지 않도록 세로 연결 하나는 필수에서 내린다.
        let callToActionTop = callToActionButton.topAnchor.constraint(greaterThanOrEqualTo: iconImageView.bottomAnchor, constant: 6)
        callToActionTop.priority = .defaultHigh

        NSLayoutConstraint.activate([
            adBadgeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            adBadgeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            adBadgeLabel.widthAnchor.constraint(equalToConstant: 30),
            adBadgeLabel.heightAnchor.constraint(equalToConstant: 18),

            iconImageView.topAnchor.constraint(equalTo: adBadgeLabel.bottomAnchor, constant: 6),
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconImageView.widthAnchor.constraint(equalToConstant: 44),
            iconImageView.heightAnchor.constraint(equalToConstant: 44),

            headlineLabel.topAnchor.constraint(equalTo: iconImageView.topAnchor),
            headlineLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10),
            headlineLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),
            bodyLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: headlineLabel.trailingAnchor),

            callToActionTop,
            callToActionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            callToActionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            callToActionButton.heightAnchor.constraint(equalToConstant: 28),
            callToActionButton.widthAnchor.constraint(lessThanOrEqualToConstant: 120)
        ])
    }

    // MARK: - 헤더 줄(K2)

    private func setupHeaderStripLayout() {
        // 종이색 헤더 위 한 단계 어두운 표면. 44pt 정사각 유리 버튼과 모양이 달라 헤더 버튼으로 보이지 않는다.
        backgroundColor = ResourcesAsset.Theme.surface.color
        layer.cornerRadius = CarveRadius.control
        clipsToBounds = true

        configureBadge(
            font: .systemFont(ofSize: 9, weight: .medium),
            textColor: ResourcesAsset.Theme.accent.color,
            backgroundColor: ResourcesAsset.Theme.selected.color,
            cornerRadius: 3
        )

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.layer.cornerRadius = 7
        iconImageView.clipsToBounds = true

        // 폭이 184pt 로 좁다. 제목을 두 줄로 흘려 한글 12~13자가 잘리지 않게 한다.
        headlineLabel.numberOfLines = 2
        headlineLabel.lineBreakMode = .byTruncatingTail
        headlineLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headlineLabel.textColor = ResourcesAsset.Theme.ink.color

        configureCallToAction(
            font: .systemFont(ofSize: 11, weight: .semibold),
            background: ResourcesAsset.Theme.selected.color,
            insets: NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8),
            cornerRadius: nil
        )

        // 배지를 제목 위에 올려 가로 폭을 아낀다.
        let textStackView = UIStackView(arrangedSubviews: [adBadgeLabel, headlineLabel])
        textStackView.axis = .vertical
        textStackView.alignment = .leading
        textStackView.spacing = 2

        [iconImageView, textStackView, callToActionButton].forEach(addLayoutSubview)

        // 아이콘은 광고 높이를 따라 커지고 작아지되 32pt 를 넘지 않는다. 원본 이미지 크기가 제약을 이기지 않게 압축 저항을 낮추고,
        // 자리가 아직 0 일 때만 풀리도록 필수 바로 아래 우선순위를 준다.
        [NSLayoutConstraint.Axis.horizontal, .vertical].forEach { axis in
            iconImageView.setContentCompressionResistancePriority(.defaultLow, for: axis)
            iconImageView.setContentHuggingPriority(.defaultLow, for: axis)
        }
        let iconHeight = iconImageView.heightAnchor.constraint(equalTo: heightAnchor, constant: -16)
        iconHeight.priority = UILayoutPriority(999)

        // 제목은 두 줄로 흘리고 CTA 는 제 크기를 지킨다. 제목이 70pt(두 줄에 한글 12~13자) 밑으로 줄어야 하면 CTA 가 먼저 잘린다.
        headlineLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headlineLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let headlineMinimumWidth = headlineLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 70)
        headlineMinimumWidth.priority = UILayoutPriority(751)
        adBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        callToActionButton.setContentHuggingPriority(.required, for: .horizontal)
        callToActionButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconHeight,
            iconImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 32),
            iconImageView.widthAnchor.constraint(equalTo: iconImageView.heightAnchor),

            adBadgeLabel.widthAnchor.constraint(equalToConstant: 22),
            adBadgeLabel.heightAnchor.constraint(equalToConstant: 12),

            textStackView.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 6),
            textStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStackView.trailingAnchor.constraint(equalTo: callToActionButton.leadingAnchor, constant: -6),
            headlineMinimumWidth,

            // 오른쪽 위 모서리는 SDK 가 넣는 AdChoices 아이콘 자리라 비워 둔다.
            callToActionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            callToActionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            callToActionButton.heightAnchor.constraint(equalToConstant: 24),
            callToActionButton.widthAnchor.constraint(lessThanOrEqualToConstant: 96)
        ])
    }

    // MARK: - 공통

    private func addLayoutSubview(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
    }

    /// AdMob 네이티브 필수 표시. 앱 언어로 옮겨 쓸 수 있고 15px 이상이어야 한다.
    private func configureBadge(font: UIFont, textColor: UIColor, backgroundColor: UIColor?, cornerRadius: CGFloat) {
        adBadgeLabel.text = "광고"
        adBadgeLabel.font = font
        adBadgeLabel.textColor = textColor
        adBadgeLabel.backgroundColor = backgroundColor
        adBadgeLabel.textAlignment = .center
        adBadgeLabel.layer.cornerRadius = cornerRadius
        adBadgeLabel.clipsToBounds = true
    }

    /// CTA 모양. `cornerRadius` 가 없으면 캡슐로 그린다.
    private func configureCallToAction(
        font: UIFont,
        background: UIColor,
        insets: NSDirectionalEdgeInsets,
        cornerRadius: CGFloat?
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.baseForegroundColor = ResourcesAsset.Theme.accent.color
        configuration.baseBackgroundColor = background
        configuration.contentInsets = insets
        configuration.titleLineBreakMode = .byTruncatingTail
        if let cornerRadius {
            configuration.cornerStyle = .fixed
            configuration.background.cornerRadius = cornerRadius
        } else {
            configuration.cornerStyle = .capsule
        }
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font
            return attributes
        }
        callToActionButton.configuration = configuration
    }
}
