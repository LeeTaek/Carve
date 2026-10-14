//
//  UIComponentsEnglishCopyTesting.swift
//  UIComponentsTest
//
//  Created by Claude on 10/12/26.
//

import Foundation
import Testing
import UIKit
@testable import UIComponents

/// 공용 컴포넌트가 스스로 적는 문구(다시 시도 · 광고 배지)가 영어로도 옮겨졌는지 본다(영어 현지화 결정 5 · 7).
/// 시험은 ko-KR 로 돌므로 앱 언어 경로는 한국어이고, 영어는 언어를 고르는 `LocalizedStringResource` 로 푼다.
struct UIComponentsEnglishCopyTesting {
    private static let englishLocale = Locale(identifier: "en")
    private static let koreanLocale = Locale(identifier: "ko")

    @Test("다시 시도 · 광고 배지는 앱 언어(시험은 한국어)로 적고, 영어 카탈로그 값은 짧다")
    func componentDefaults() {
        #expect(CarveStatusMessage.defaultRetryTitle == "다시 시도")
        #expect(NativeAdContentView.adBadgeText(locale: Self.koreanLocale) == "광고")
        #expect(NativeAdContentView.adBadgeText(locale: Self.englishLocale) == "Ad")
        #expect(Self.english("다시 시도") == "Try Again")
        #expect(Self.english("광고") == "Ad")
    }

    @Test("다시 시도 기본 제목은 문자열로 붙잡지 않아 화면 언어를 따르고, 부르는 쪽이 준 제목은 그대로 둔다")
    @MainActor
    func statusMessageKeepsOnlyCustomRetryTitle() {
        #expect(CarveStatusMessage(.failure, message: "저장하지 못했어요").retryTitle == nil)
        #expect(CarveStatusMessage(.failure, message: "저장하지 못했어요", retryTitle: CarveStatusMessage.defaultRetryTitle).retryTitle == nil)
        #expect(CarveStatusMessage(.success, message: "지웠어요", retryTitle: "실행 취소").retryTitle == "실행 취소")
    }

    @Test("광고 배지는 만들 때 앱 언어로 적고, 붙이는 호스트가 넣은 언어로 다시 적는다 — 컨테이너 안의 공용 레이아웃을 찾는다")
    @MainActor
    func adBadgeFollowsHostLocale() {
        let contentView = NativeAdContentView(style: .sidebar)
        #expect(contentView.adBadgeLabel.text == "광고")

        // 인프라 컨테이너(앱의 `NativeAdContainerView`)처럼 공용 레이아웃을 하위에 둔 뷰를 호스트(`AdSlotView`)가 받는다.
        let container = UIView()
        container.addSubview(contentView)

        NativeAdContentView.updateBadgeText(locale: Self.englishLocale, in: container)
        #expect(contentView.adBadgeLabel.text == "Ad")

        NativeAdContentView.updateBadgeText(locale: Self.koreanLocale, in: container)
        #expect(contentView.adBadgeLabel.text == "광고")
    }

    /// 역할: 이 모듈 카탈로그의 문구를 영어로 꺼낸다.
    /// 입력 · 출력: 키(한국어 원문) → 영어 값. 부작용: 없음.
    private static func english(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, locale: Locale(identifier: "en"), bundle: .atURL(Bundle.module.bundleURL)))
    }
}
