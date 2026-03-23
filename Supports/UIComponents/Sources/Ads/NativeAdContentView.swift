//
//  NativeAdContentView.swift
//  UIComponents
//
//  Created by 이택성 on 1/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import UIKit

public final class NativeAdContentView: UIView {
    public let adBadgeLabel = UILabel()
    public let mediaContainerView = UIView()
    public let iconImageView = UIImageView()
    public let headlineLabel = UILabel()
    public let bodyLabel = UILabel()
    public let callToActionButton = UIButton(type: .system)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayout()
    }

    private func setupLayout() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        clipsToBounds = true

        adBadgeLabel.text = "Ad"
        adBadgeLabel.font = .preferredFont(forTextStyle: .caption2)
        adBadgeLabel.textColor = .secondaryLabel
        adBadgeLabel.textAlignment = .center
        adBadgeLabel.layer.cornerRadius = 6
        adBadgeLabel.layer.borderWidth = 1
        adBadgeLabel.layer.borderColor = UIColor.separator.cgColor
        adBadgeLabel.clipsToBounds = true

        mediaContainerView.backgroundColor = .tertiarySystemFill
        mediaContainerView.layer.cornerRadius = 10
        mediaContainerView.clipsToBounds = true

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.layer.cornerRadius = 8
        iconImageView.clipsToBounds = true

        headlineLabel.numberOfLines = 2
        headlineLabel.font = .preferredFont(forTextStyle: .headline)

        bodyLabel.numberOfLines = 3
        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.textColor = .secondaryLabel

        callToActionButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        callToActionButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        callToActionButton.layer.cornerRadius = 10
        callToActionButton.backgroundColor = .tertiarySystemBackground

        let headerStackView = UIStackView(arrangedSubviews: [iconImageView, headlineLabel])
        headerStackView.axis = .horizontal
        headerStackView.alignment = .center
        headerStackView.spacing = 10
        headerStackView.translatesAutoresizingMaskIntoConstraints = false

        [
            adBadgeLabel,
            mediaContainerView,
            headerStackView,
            bodyLabel,
            callToActionButton
        ].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            adBadgeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            adBadgeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            adBadgeLabel.widthAnchor.constraint(equalToConstant: 34),
            adBadgeLabel.heightAnchor.constraint(equalToConstant: 18),

            mediaContainerView.topAnchor.constraint(equalTo: adBadgeLabel.bottomAnchor, constant: 10),
            mediaContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mediaContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mediaContainerView.heightAnchor.constraint(equalToConstant: 140),

            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),

            headerStackView.topAnchor.constraint(equalTo: mediaContainerView.bottomAnchor, constant: 12),
            headerStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            headerStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            bodyLabel.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: 6),
            bodyLabel.leadingAnchor.constraint(equalTo: headerStackView.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: headerStackView.trailingAnchor),

            callToActionButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 10),
            callToActionButton.leadingAnchor.constraint(equalTo: headerStackView.leadingAnchor),
            callToActionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        // 기본 상태(광고가 없을 때)
        headlineLabel.text = nil
        bodyLabel.text = nil
        iconImageView.image = nil
        callToActionButton.setTitle(nil, for: .normal)
    }
}
