//
//  LanguageSettingsFeatureTesting.swift
//  SettingsFeatureTest
//
//  설정 › 화면 › 언어 — 앱 안에서 고르면 iOS 앱별 언어와 같은 값에 저장하고, 지금 실행의 화면 언어를 바로 바꾼다
//  (보관함 「Carve 앱 언어 즉시 전환」 단계 1 · 저장 정책 (1) 단일 진실).
//

@testable import SettingsFeature
import ClientInterfaces
import Foundation
import Testing
import UIKit

import ComposableArchitecture

/// 시험용 언어 저장 — 저장한 고르기를 남기고, 정해 둔 해석 언어를 돌려준다.
private struct AppLanguageClientSpy: AppLanguageClient {
    let stored: AppLanguageSelection
    let resolved: AppLanguage
    let saved = LockIsolated<[AppLanguageSelection]>([])

    func selection() -> AppLanguageSelection { stored }
    func save(_ selection: AppLanguageSelection) { saved.withValue { $0.append(selection) } }
    func resolvedLanguage() -> AppLanguage { resolved }
}

@Suite("앱 언어 설정")
@MainActor
struct LanguageSettingsFeatureTesting {
    // MARK: - 화면

    @Test("화면이 뜨면 저장된 고르기를 읽는다")
    func onAppearLoadsSelection() async {
        let store = TestStore(initialState: LanguageSettingsFeature.State()) {
            LanguageSettingsFeature()
        } withDependencies: {
            $0.appLanguageClient = AppLanguageClientSpy(stored: .english, resolved: .english)
        }

        await store.send(.view(.onAppear)) {
            $0.selection = .english
        }
    }

    @Test("언어를 고르면 저장하고, 지금 실행의 화면 언어를 바로 바꾼다")
    func selectionSavesAndOverridesLanguage() async {
        let storage = InMemoryStorage()
        let client = AppLanguageClientSpy(stored: .system, resolved: .english)
        let store = makeStore(selection: .system, client: client, storage: storage)

        await store.send(.view(.selectionChanged(.english))) {
            $0.selection = .english
        }

        #expect(client.saved.value == [.english])
        #expect(languageOverride(in: storage) == .english)
    }

    @Test("시스템 설정으로 돌아가면 그렇게 저장하고(키 삭제는 저장 구현이 한다), 기기 언어로 바꾼다")
    func systemSelectionUsesResolvedDeviceLanguage() async {
        let storage = InMemoryStorage()
        let client = AppLanguageClientSpy(stored: .english, resolved: .korean)
        let store = makeStore(selection: .english, client: client, storage: storage)

        await store.send(.view(.selectionChanged(.system))) {
            $0.selection = .system
        }

        #expect(client.saved.value == [.system])
        #expect(languageOverride(in: storage) == .korean)
    }

    @Test("이미 고른 언어를 다시 고르면 저장하지도, 화면 언어를 바꾸지도 않는다")
    func reselectingSameLanguageDoesNothing() async {
        let storage = InMemoryStorage()
        let client = AppLanguageClientSpy(stored: .korean, resolved: .korean)
        let store = makeStore(selection: .korean, client: client, storage: storage)

        await store.send(.view(.selectionChanged(.korean)))

        #expect(client.saved.value.isEmpty)
        #expect(languageOverride(in: storage) == nil)
    }

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

    // MARK: - 저장 모양 — 설정 앱과 같은 값

    @Test("고른 언어는 설정 앱과 같은 모양으로 저장한다 — 시스템 설정은 nil(키 삭제)")
    func appleLanguagesShape() {
        let preferred = ["ko-KR", "en-KR"]
        #expect(AppLanguageSelection.english.appleLanguages(preferredLanguages: preferred, region: "KR") == ["en-KR", "ko-KR"])
        #expect(AppLanguageSelection.korean.appleLanguages(preferredLanguages: ["en-KR", "ko-KR"], region: "KR") == ["ko-KR", "en-KR"])
        #expect(AppLanguageSelection.system.appleLanguages(preferredLanguages: preferred, region: "KR") == nil)
        // 지역을 모르면 언어 코드만 쓴다. 같은 언어의 다른 지역 항목은 빼서 겹치지 않게 한다.
        #expect(AppLanguageSelection.english.appleLanguages(preferredLanguages: ["en-US", "ko-KR"], region: nil) == ["en", "ko-KR"])
    }

    @Test(
        "저장값에서 고르기를 읽는다 — 키가 없거나 지원하지 않는 언어면 시스템 설정",
        arguments: [
            (nil, AppLanguageSelection.system),
            (["en-KR", "ko-KR"], .english),
            (["ko-KR"], .korean),
            (["ja-JP", "ko-KR"], .system)
        ] as [([String]?, AppLanguageSelection)]
    )
    func selectionFromStoredValue(stored: [String]?, expected: AppLanguageSelection) {
        #expect(AppLanguageSelection(appleLanguages: stored) == expected)
    }

    @Test("iOS 선호 언어에서 앞에서부터 처음 맞는 언어를 고른다 — 없으면 원문 언어(한국어)")
    func resolveFromPreferredLanguages() {
        #expect(AppLanguage.resolve(preferredLanguages: ["ko-KR", "en-KR"]) == .korean)
        #expect(AppLanguage.resolve(preferredLanguages: ["en-KR", "ko-KR"]) == .english)
        #expect(AppLanguage.resolve(preferredLanguages: ["ja-JP", "en-GB"]) == .english)
        #expect(AppLanguage.resolve(preferredLanguages: ["ja-JP"]) == .korean)
        #expect(AppLanguage.resolve(preferredLanguages: []) == .korean)
    }

    // MARK: - locale — 언어만 바꾸고 서식 선호는 둔다

    @Test("고른 언어의 locale 은 지역 · 달력 · 시간제 · 주 시작일을 기준 로케일 것으로 둔다")
    func localeKeepsRegionalPreferences() {
        let english = AppLanguage.english.locale(base: Locale(identifier: "ko_KR@calendar=buddhist;hours=h23"))
        #expect(english.language.languageCode?.identifier == "en")
        // ⚠️ 언어 구성요소를 통째로 바꾸면 여기서 지역이 사라진다(2026-10-13 iPadOS 17.5 · 26.2 에서 `ko_KR` → `en`).
        #expect(english.region?.identifier == "KR")
        #expect(english.calendar.identifier == .buddhist)
        #expect(english.hourCycle == .zeroToTwentyThree)

        let korean = AppLanguage.korean.locale(base: Locale(identifier: "en_GB"))
        #expect(korean.language.languageCode?.identifier == "ko")
        #expect(korean.region?.identifier == "GB")
        #expect(korean.firstDayOfWeek == .monday)
    }

    // MARK: - 리듀서 · effect · 인프라의 화면 언어(즉시 전환 단계 3)

    @Test("앱 안에서 고른 언어가 없으면 리듀서가 얻는 화면 언어는 iOS 선호 언어에서 앱이 옮긴 첫 언어다 — 시험은 ko-KR")
    func displayLocaleWithoutOverrideFollowsPreferredLanguages() {
        // Given: 고른 언어를 넣지 않은 저장소
        let locale = withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            // When
            AppLanguage.displayLocale()
        }

        // Then: 스킴이 시험 언어 · 지역을 ko-KR 로 고정한다(`Workspace.swift` 의 `testLanguage` · `testRegion`)
        #expect(locale.language.languageCode?.identifier == "ko")
        #expect(locale.region?.identifier == "KR")
    }

    @Test(
        "고른 언어가 없으면 선호 언어에서 앱이 옮긴 첫 언어로, 하나도 없으면 개발 언어 ko 로 — 번들과 같은 규칙이라 문구가 섞이지 않는다",
        arguments: [
            // 2026-10-13 iPadOS 26.2: 일본어 하나뿐인 기기는 번들이 ko 를 고르는데 `Locale.current` 는 en_JP 였다 — 그대로 쓰면 한 화면에 ko · en 이 섞였다.
            (["ja-JP"], "ko"),
            (["ja-JP", "en-JP"], "en"),
            (["en-US", "ko-KR"], "en"),
            (["ko-KR", "en-KR"], "ko")
        ] as [([String], String)]
    )
    func displayLocaleWithoutOverrideFollowsBundleRule(preferredLanguages: [String], expected: String) {
        let locale = AppLanguage.displayLocale(override: nil, preferredLanguages: preferredLanguages, base: Locale(identifier: "en_JP"))

        #expect(locale.language.languageCode?.identifier == expected)
        // 지역은 기준 로케일(기기) 것 그대로다.
        #expect(locale.region?.identifier == "JP")
    }

    @Test("앱 안에서 고른 언어가 있으면 선호 언어와 상관없이 그 언어다")
    func displayLocaleOverrideWinsOverPreferredLanguages() {
        let locale = AppLanguage.displayLocale(override: .english, preferredLanguages: ["ko-KR"], base: Locale(identifier: "ko_KR"))

        #expect(locale.language.languageCode?.identifier == "en")
        #expect(locale.region?.identifier == "KR")
    }

    @Test("앱 안에서 영어를 고르면 리듀서가 얻는 화면 언어는 en 이고, 지역은 기기 것 그대로다")
    func displayLocaleFollowsOverride() {
        let locale = withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            // Given: 설정 › 화면 › 언어(`LanguageSettingsFeature`)와 같은 키 · 같은 방식으로 영어를 넣는다
            @Shared(.appLanguageOverride) var languageOverride: AppLanguage?
            $languageOverride.withLock { $0 = .english }
            // When
            return AppLanguage.displayLocale()
        }

        // Then
        #expect(locale.language.languageCode?.identifier == "en")
        // 시험은 스킴이 한국 지역으로 고정한다(`Workspace.swift` 의 `testRegion`) — 언어만 바뀌고 지역 KR 은 남는다.
        #expect(locale.region == Locale.autoupdatingCurrent.region)
        #expect(locale.region?.identifier == "KR")
    }

    // MARK: - 이름 · 문구

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

    @Test("시험은 한국어로 돈다 — 시작 때 언어(모듈 번들이 고른 언어)도 한국어다(결정 6)")
    func launchLanguageIsKoreanInTests() {
        #expect(AppLanguage.launch == .korean)
    }

    @Test("언어 이름은 화면 언어와 상관없이 그 언어로 적고, 시스템 설정만 화면 언어로 옮긴다")
    func selectionTitles() {
        #expect(AppLanguageSelection.allCases.map { $0.title(locale: Locale(identifier: "en")) } == ["System", "한국어", "English"])
        #expect(AppLanguageSelection.allCases.map { $0.title(locale: Locale(identifier: "ko")) } == ["시스템 설정", "한국어", "English"])
    }

    @Test("미리 만드는 문구는 넘긴 locale 의 언어로 꺼낸다 — 뷰는 환경 locale 을 넘겨 다시 시작하지 않고 바뀐다(즉시 전환 단계 2)")
    func catalogStringFollowsGivenLocale() {
        let english = Locale(identifier: "en_KR")
        let korean = Locale(identifier: "ko_KR")
        #expect(SettingsCatalog.string("설정", locale: english) == "Settings")
        #expect(SettingsCatalog.string("설정", locale: korean) == "설정")
        #expect(SettingsCatalog.string("화면 모드", locale: english) == "Appearance")
        #expect(AppearanceMode.system.title(locale: english) == "System")
        #expect(AppearanceMode.system.title(locale: korean) == "시스템 설정")
        // 앱 안에서 고른 언어의 locale(지역 · 시간제 보존)로도 같은 문구가 나온다.
        #expect(SettingsCatalog.string("설정", locale: AppLanguage.english.locale(base: korean)) == "Settings")
    }

    @Test("언어 화면 문구는 영어로도 옮겨져 있다")
    func englishCopy() {
        let english = Locale(identifier: "en")
        #expect(SettingsCatalog.string("언어", locale: english) == "Language")
        #expect(SettingsCatalog.string("앱 언어", locale: english) == "App Language")
        #expect(SettingsCatalog.string("iPad 설정에서 바꾸기", locale: english) == "Change in Settings")
        #expect(SettingsCatalog.string("고른 언어는 바로 적용돼요. 일부 화면은 앱을 다시 열면 바뀌어요.", locale: english)
            == "Your choice applies right away. Some screens change the next time you open the app.")
    }

    // MARK: - 도우미

    private func makeStore(
        selection: AppLanguageSelection,
        client: AppLanguageClientSpy,
        storage: InMemoryStorage
    ) -> TestStoreOf<LanguageSettingsFeature> {
        TestStore(initialState: LanguageSettingsFeature.State(selection: selection)) {
            LanguageSettingsFeature()
        } withDependencies: {
            $0.appLanguageClient = client
            $0.defaultInMemoryStorage = storage
        }
    }

    /// 앱 루트(`AppCoordinatorView`)와 같은 키로 읽는다. 시험이 넣은 저장소에서 읽는다.
    private func languageOverride(in storage: InMemoryStorage) -> AppLanguage? {
        withDependencies {
            $0.defaultInMemoryStorage = storage
        } operation: {
            SharedReader<AppLanguage?>(.appLanguageOverride).wrappedValue
        }
    }
}
