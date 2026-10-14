//
//  VerseWidgetPayloadTesting.swift
//  CarveAppTest
//
//  위젯 payload 의 참조 문자열 — 앱이 담을 때 만든 참조(앱 언어)를 쓰고, 2.1 전 앱이 쓴 payload 는 옛 한국어 형식으로 읽는다(영어 현지화 t4c).
//  위젯 표시 locale — 앱이 App Group 에 적은 화면 언어로 만들고, 적힌 값이 없으면 위젯 자기 언어다(즉시 전환 단계 3 t1d).
//

import ClientInterfaces
import Foundation
import Testing

/// 이 파일이 막는 것:
/// - 영어 앱이 담은 말씀의 손쉬운 사용 레이블이 「Psalms 23장 1절」 처럼 영어 권 이름과 한국어 장절 형식으로 섞이는 것
/// - 참조 필드를 더하면서 2.0.x 앱이 App Group 에 남긴 payload 를 읽지 못해 위젯이 빈 칸이 되는 것
/// - 앱 안에서 English 를 골랐는데 위젯 문구(빈 상태 안내 · 「Carve · 번역본」)가 한국어로 남거나, 언어를 바꾸며 지역 · 시간제를 잃는 것
struct VerseWidgetPayloadTesting {
    @Test("앱이 담을 때 만든 참조가 있으면 위젯은 그 참조와 짧은 참조를 그대로 쓴다")
    func payloadUsesReferenceMadeByApp() {
        let payload = Self.payload(referenceText: "Psalm 23:1", compactReferenceText: "Psalm 23:1")

        #expect(payload.reference == "Psalm 23:1")
        #expect(payload.compactReference == "Psalm 23:1")
    }

    @Test("참조 필드가 없는 옛 payload(2.0.x)는 그대로 읽히고, 참조는 옛 한국어 형식으로 만든다")
    func legacyPayloadFallsBackToKoreanFormat() throws {
        let json = """
        [{"titleRawValue":"1-19Psalms.txt","bookDisplayName":"시편","chapter":23,"verse":1,"translation":"NKRV",\
        "translationDisplayName":"개역개정","sentence":"여호와는 나의 목자시니","designatedAt":"2026-09-16T00:00:00Z"}]
        """
        let payloads = try Self.decoder.decode([VerseWidgetPayload].self, from: Data(json.utf8))
        let payload = try #require(payloads.first)

        #expect(payload.referenceText == nil)
        #expect(payload.compactReferenceText == nil)
        #expect(payload.reference == "시편 23장 1절")
        #expect(payload.compactReference == "시편 23:1")
    }

    @Test("참조를 담은 payload 는 저장 · 읽기를 거쳐도 참조가 남는다")
    func referenceSurvivesRoundTrip() throws {
        let payload = Self.payload(referenceText: "Psalm 23:1", compactReferenceText: "Psalm 23:1")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoded = try Self.decoder.decode([VerseWidgetPayload].self, from: encoder.encode([payload]))

        #expect(decoded == [payload])
        #expect(decoded.first?.reference == "Psalm 23:1")
    }

    // MARK: - 위젯 화면 언어 (App Group → 표시 locale)

    @Test("App Group 에 en 이 적혀 있으면 위젯 표시 locale 은 영어이고, 기기의 지역 · 시간제는 그대로다")
    func englishAppLanguageKeepsRegion() throws {
        let locale = try Self.withSharedDefaults(appLanguage: AppLanguage.english.rawValue) {
            VerseWidgetSharing.displayLocale(in: $0, base: Locale(identifier: "ko_KR@hours=h23"))
        }

        #expect(locale.identifier == "en_KR@hours=h23")
        #expect(locale.language.languageCode == .english)
        #expect(locale.region == .southKorea)
        #expect(locale.hourCycle == .zeroToTwentyThree)
    }

    @Test("App Group 에 ko 가 적혀 있으면 영어 기기에서도 한국어이고, 지역(미국)은 그대로다")
    func koreanAppLanguageKeepsRegion() throws {
        let locale = try Self.withSharedDefaults(appLanguage: AppLanguage.korean.rawValue) {
            VerseWidgetSharing.displayLocale(in: $0, base: Locale(identifier: "en_US"))
        }

        #expect(locale.identifier == "ko_US")
        #expect(locale.language.languageCode == .korean)
        #expect(locale.region == .unitedStates)
    }

    @Test("App Group 에 적힌 언어가 없거나 App Group 을 열지 못하면 위젯 자기 언어(기준 locale) 그대로다")
    func missingAppLanguageKeepsWidgetLanguage() throws {
        let base = Locale(identifier: "en_GB")
        let unwritten = try Self.withSharedDefaults(appLanguage: nil) {
            VerseWidgetSharing.displayLocale(in: $0, base: base)
        }

        #expect(unwritten == base)
        #expect(VerseWidgetSharing.displayLocale(in: nil, base: base) == base)
    }

    @Test("위젯이 모르는 언어 코드는 적히지 않은 것으로 본다 — 위젯 자기 언어 그대로다")
    func unknownAppLanguageKeepsWidgetLanguage() {
        let base = Locale(identifier: "ja_JP")

        for code in ["ja", "", "en-US", "EN"] {
            #expect(VerseWidgetSharing.displayLocale(appLanguage: code, base: base) == base, "code: \(code)")
        }
    }

    @Test("문자 체계(script)는 비운다 — 번체 중국어 기기에서 영어를 골라도 Hant 가 남지 않고 지역은 그대로다")
    func scriptIsClearedAndRegionKept() {
        let locale = VerseWidgetSharing.displayLocale(appLanguage: AppLanguage.english.rawValue, base: Locale(identifier: "zh-Hant_TW"))

        #expect(locale.identifier == "en_TW")
        #expect(locale.region == .taiwan)
    }

    @Test("앱 화면 locale(AppLanguage.locale(base:))과 같은 규칙이다 — 앱 화면과 위젯이 같은 locale 이 된다")
    func widgetLocaleMatchesAppLanguageRule() {
        let bases = ["ko_KR", "en_US", "ko_KR@calendar=buddhist;hours=h23", "en_GB", "zh-Hant_TW", "ja_JP"].map(Locale.init(identifier:))

        for language in AppLanguage.allCases {
            for base in bases {
                #expect(
                    VerseWidgetSharing.displayLocale(appLanguage: language.rawValue, base: base) == language.locale(base: base),
                    "language: \(language.rawValue), base: \(base.identifier)"
                )
            }
        }
    }

    @Test("위젯이 아는 언어 코드는 앱 AppLanguage 와 같다 — 앱이 적는 값을 위젯이 모두 읽는다")
    func widgetLanguageCodesMatchAppLanguage() {
        #expect(VerseWidgetSharing.appLanguageCodes == Set(AppLanguage.allCases.map(\.rawValue)))
    }

    // MARK: - 시험 자료

    /// `VerseWidgetStore` 와 같은 날짜 형식으로 읽는다.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// App Group 대신 시험마다 새 UserDefaults 를 만들어 `body` 에 넘기고, 끝나면 지운다.
    /// 앱이 적는 것처럼 `appLanguageKey` 에 언어 코드를 적는다(nil 이면 적지 않는다). 실제 App Group(`VerseWidgetSharing.appGroupID`)은 건드리지 않는다.
    private static func withSharedDefaults<Value>(appLanguage: String?, _ body: (UserDefaults) -> Value) throws -> Value {
        let suiteName = "VerseWidgetPayloadTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        if let appLanguage {
            defaults.set(appLanguage, forKey: VerseWidgetSharing.appLanguageKey)
        }
        return body(defaults)
    }

    /// 영어 앱이 KJV 시편 23편 1절을 담은 payload.
    private static func payload(referenceText: String?, compactReferenceText: String?) -> VerseWidgetPayload {
        VerseWidgetPayload(
            titleRawValue: "1-19Psalms.txt",
            bookDisplayName: "Psalms",
            chapter: 23,
            verse: 1,
            translation: "KJV",
            translationDisplayName: "KJV",
            sentence: "The LORD is my shepherd; I shall not want.",
            designatedAt: Date(timeIntervalSince1970: 0),
            referenceText: referenceText,
            compactReferenceText: compactReferenceText
        )
    }
}
