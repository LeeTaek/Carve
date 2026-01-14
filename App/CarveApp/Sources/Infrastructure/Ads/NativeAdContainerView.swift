//
//  NativeAdContainerView.swift
//  CarveApp
//
//  Created by 이택성 on 1/13/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import UIKit
import GoogleMobileAds
import UIComponents


/// AdMob Native 광고를 표시하기 위한 컨테이너 뷰.
/// - `NativeAdView(GMA)`에 asset view들을 등록하고, `populate(with:)`에서 광고 내용을 주입.
/// - `MediaView(GMA)`는 GoogleMobileAds 타입이므로 이 컨테이너에서만 생성/관리.
final class NativeAdContainerView: NativeAdView {
    /// 앱 공용 레이아웃(순수 UIKit)
    private let contentView = NativeAdContentView()
    /// 동영상/이미지 등 미디어 영역
    private let mediaAssetView = MediaView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // MediaView는 컨테이너 만든 뒤 contentView의 자리뷰에 붙임
        contentView.mediaContainerView.addSubview(mediaAssetView)
        mediaAssetView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mediaAssetView.topAnchor.constraint(equalTo: contentView.mediaContainerView.topAnchor),
            mediaAssetView.leadingAnchor.constraint(equalTo: contentView.mediaContainerView.leadingAnchor),
            mediaAssetView.trailingAnchor.constraint(equalTo: contentView.mediaContainerView.trailingAnchor),
            mediaAssetView.bottomAnchor.constraint(equalTo: contentView.mediaContainerView.bottomAnchor)
        ])

        // asset view 등록
        mediaView = mediaAssetView
        headlineView = contentView.headlineLabel
        bodyView = contentView.bodyLabel
        iconView = contentView.iconImageView
        callToActionView = contentView.callToActionButton
    }

    func populate(with nativeAd: NativeAd) {
        self.nativeAd = nil

        contentView.headlineLabel.text = nativeAd.headline

        if let body = nativeAd.body {
            contentView.bodyLabel.text = body
            contentView.bodyLabel.isHidden = false
        } else {
            contentView.bodyLabel.text = nil
            contentView.bodyLabel.isHidden = true
        }

        if let iconImage = nativeAd.icon?.image {
            contentView.iconImageView.image = iconImage
            contentView.iconImageView.isHidden = false
        } else {
            contentView.iconImageView.image = nil
            contentView.iconImageView.isHidden = true
        }

        mediaAssetView.mediaContent = nativeAd.mediaContent
        if let callToAction = nativeAd.callToAction {
            contentView.callToActionButton.setTitle(callToAction, for: .normal)
            contentView.callToActionButton.isHidden = false
        } else {
            contentView.callToActionButton.setTitle(nil, for: .normal)
            contentView.callToActionButton.isHidden = true
        }

        // SDK가 터치를 처리하도록(버튼 터치 이벤트를 앱이 가로채지 않게)
        contentView.callToActionButton.isUserInteractionEnabled = false

        // 클릭/노출 측정 등이 정상 동작하도록 마지막에 연결.
        self.nativeAd = nativeAd
    }
}
