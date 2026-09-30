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
///   이미지를 그리지 않는 레이아웃(사이드바 · 헤더)에는 두지 않는다.
final class NativeAdContainerView: NativeAdView {
    /// 앱 공용 레이아웃(순수 UIKit)
    private let contentView: NativeAdContentView
    /// 동영상/이미지 등 미디어 영역
    private let mediaAssetView: MediaView?

    init(style: NativeAdContentView.Style) {
        contentView = NativeAdContentView(style: style)
        mediaAssetView = style.showsMedia ? MediaView() : nil
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
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
        if let mediaAssetView {
            contentView.mediaContainerView.addSubview(mediaAssetView)
            mediaAssetView.translatesAutoresizingMaskIntoConstraints = false
            // 소재의 고유 크기가 자리 크기(16:9 · 120pt)를 밀어내지 않게 한다.
            [NSLayoutConstraint.Axis.horizontal, .vertical].forEach { axis in
                mediaAssetView.setContentHuggingPriority(.defaultLow, for: axis)
                mediaAssetView.setContentCompressionResistancePriority(.defaultLow, for: axis)
            }
            NSLayoutConstraint.activate([
                mediaAssetView.topAnchor.constraint(equalTo: contentView.mediaContainerView.topAnchor),
                mediaAssetView.leadingAnchor.constraint(equalTo: contentView.mediaContainerView.leadingAnchor),
                mediaAssetView.trailingAnchor.constraint(equalTo: contentView.mediaContainerView.trailingAnchor),
                mediaAssetView.bottomAnchor.constraint(equalTo: contentView.mediaContainerView.bottomAnchor)
            ])
            mediaView = mediaAssetView
        }

        // SDK가 터치를 처리하도록(버튼 터치 이벤트를 앱이 가로채지 않게). 등록하기 전에 꺼야 SDK 경고가 나지 않는다.
        contentView.callToActionButton.isUserInteractionEnabled = false

        // asset view 등록
        headlineView = contentView.headlineLabel
        if contentView.style.showsBody {
            bodyView = contentView.bodyLabel
        }
        iconView = contentView.iconImageView
        callToActionView = contentView.callToActionButton
    }

    func populate(with nativeAd: NativeAd) {
        self.nativeAd = nil

        contentView.headlineLabel.text = nativeAd.headline

        if contentView.style.showsBody, let body = nativeAd.body {
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

        mediaAssetView?.mediaContent = nativeAd.mediaContent
        contentView.setCallToAction(nativeAd.callToAction)

        // SDK가 터치를 처리하도록(버튼 터치 이벤트를 앱이 가로채지 않게)
        contentView.callToActionButton.isUserInteractionEnabled = false

        // 클릭/노출 측정 등이 정상 동작하도록 마지막에 연결.
        self.nativeAd = nativeAd
    }
}
