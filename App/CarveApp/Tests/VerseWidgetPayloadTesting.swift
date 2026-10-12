//
//  VerseWidgetPayloadTesting.swift
//  CarveAppTest
//
//  위젯 payload 의 참조 문자열 — 앱이 담을 때 만든 참조(앱 언어)를 쓰고, 2.1 전 앱이 쓴 payload 는 옛 한국어 형식으로 읽는다(영어 현지화 t4c).
//

import Foundation
import Testing

/// 이 파일이 막는 것:
/// - 영어 앱이 담은 말씀의 손쉬운 사용 레이블이 「Psalms 23장 1절」 처럼 영어 권 이름과 한국어 장절 형식으로 섞이는 것
/// - 참조 필드를 더하면서 2.0.x 앱이 App Group 에 남긴 payload 를 읽지 못해 위젯이 빈 칸이 되는 것
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

    // MARK: - 시험 자료

    /// `VerseWidgetStore` 와 같은 날짜 형식으로 읽는다.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
