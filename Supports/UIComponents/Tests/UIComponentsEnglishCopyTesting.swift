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
    @Test("다시 시도 · 광고 배지는 앱 언어(시험은 한국어)로 적고, 영어 카탈로그 값은 짧다")
    func componentDefaults() {
        #expect(CarveStatusMessage.defaultRetryTitle == "다시 시도")
        #expect(NativeAdContentView.adBadgeText == "광고")
        #expect(Self.english("다시 시도") == "Try Again")
        #expect(Self.english("광고") == "Ad")
    }

    /// 역할: 이 모듈 카탈로그의 문구를 영어로 꺼낸다.
    /// 입력 · 출력: 키(한국어 원문) → 영어 값. 부작용: 없음.
    private static func english(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, locale: Locale(identifier: "en"), bundle: .atURL(Bundle.module.bundleURL)))
    }
}
