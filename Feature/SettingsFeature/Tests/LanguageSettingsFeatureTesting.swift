//
//  LanguageSettingsFeatureTesting.swift
//  SettingsFeatureTest
//
//  설정 › 언어 — 지금 앱 언어와 iPad 설정의 이 앱 화면 열기(영어 현지화 결정 20).
//

@testable import SettingsFeature
import Foundation
import Testing
import UIKit

import ComposableArchitecture

@Suite("앱 언어 설정")
@MainActor
struct LanguageSettingsFeatureTesting {
    @Test("「iPad 설정에서 바꾸기」 는 설정 앱의 이 앱 화면을 연다 — 언어 항목이 거기 있다")
    func openSystemSettingsOpensAppSettings() async throws {
        let openedURLs = LockIsolated<[URL]>([])
        let store = TestStore(initialState: LanguageSettingsFeature.State()) {
            LanguageSettingsFeature()
        } withDependencies: {
            $0.openURL = OpenURLEffect { url in
                openedURLs.withValue { $0.append(url) }
                return true
            }
        }
        let settingsURL = try #require(URL(string: UIApplication.openSettingsURLString))

        await store.send(.view(.openSystemSettingsTapped))
        await store.finish()

        #expect(openedURLs.value == [settingsURL])
    }

    @Test(
        "앱 언어는 번들이 고른 첫 현지화를 따르고, 지역이 붙어도 언어로 읽는다",
        arguments: [
            (["ko"], AppLanguage.korean),
            (["en"], .english),
            (["en-GB", "ko"], .english),
            (["ko-KR", "en"], .korean)
        ]
    )
    func currentLanguageFollowsPreferredLocalization(localizations: [String], expected: AppLanguage) {
        #expect(AppLanguage.current(preferredLocalizations: localizations) == expected)
    }

    @Test("고른 현지화가 없거나 모르는 언어면 원문 언어인 한국어로 본다")
    func unknownLocalizationFallsBackToKorean() {
        #expect(AppLanguage.current(preferredLocalizations: []) == .korean)
        #expect(AppLanguage.current(preferredLocalizations: ["ja"]) == .korean)
    }

    @Test("시험은 한국어로 돈다 — 모듈 번들이 고른 언어도 한국어다(결정 6)")
    func moduleBundleLanguageIsKoreanInTests() {
        #expect(AppLanguage.current() == .korean)
    }

    @Test("언어 이름은 화면 언어와 상관없이 그 언어로 적는다")
    func nativeNamesStayInTheirOwnLanguage() {
        let names = SettingsCatalog.$locale.withValue(Locale(identifier: "en")) {
            AppLanguage.allCases.map(\.nativeName)
        }
        #expect(names == ["한국어", "English"])
    }

    @Test("언어 화면 문구는 영어로도 옮겨져 있다")
    func englishCopy() {
        SettingsCatalog.$locale.withValue(Locale(identifier: "en")) {
            #expect(SettingsCatalog.string("언어") == "Language")
            #expect(SettingsCatalog.string("앱 언어") == "App Language")
            #expect(SettingsCatalog.string("iPad 설정에서 바꾸기") == "Change in Settings")
        }
    }
}
