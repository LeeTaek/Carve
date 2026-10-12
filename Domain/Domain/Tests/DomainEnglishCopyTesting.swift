//
//  DomainEnglishCopyTesting.swift
//  DomainTest
//
//  Created by Claude on 10/12/26.
//

@testable import Domain
import Foundation
import Testing

/// Domain 이 화면 · 파일 이름에 내놓는 문구(글꼴 이름 · 의견 종류 · 백업 파일 이름)가 영어로도 옮겨졌는지 본다(영어 현지화 결정 5 · 7 · 8).
/// 언어는 로케일로 명시한다 — 시험은 ko-KR 로 돌므로 로케일 없는 경로는 한국어다.
struct DomainEnglishCopyTesting {
    private static let english = Locale(identifier: "en")

    @Test("백업 파일 기본 이름은 영어에서 「Carve Backup YYYY-MM-DD.carvebackup」 이고, 날짜 표기는 언어와 무관하다")
    func backupFileNameInEnglish() throws {
        let seoul = try #require(TimeZone(identifier: "Asia/Seoul"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSinceReferenceDate: 813_009_600) // 2026-10-06 20:00 UTC = 2026-10-07 05:00 KST

        #expect(BackupExportFileName.prefix(locale: Self.english) == "Carve Backup")
        #expect(BackupExportFileName.defaultName(for: date, timeZone: seoul, locale: Self.english) == "Carve Backup 2026-10-07.carvebackup")
        #expect(BackupExportFileName.defaultName(for: date, timeZone: utc, locale: Self.english) == "Carve Backup 2026-10-06.carvebackup")
        // 로케일 없는 경로는 앱 언어(시험은 한국어)다 — 원문 상수와 같다.
        #expect(BackupExportFileName.prefix(locale: nil) == BackupExportFileName.prefix)
        #expect(BackupExportFileName.defaultName(for: date, timeZone: seoul) == "새기다 필사 백업 2026-10-07.carvebackup")
    }

    @Test("글꼴 이름은 영어에서 Nanum 로마자 이름이고, 한국어는 실제 글꼴 패밀리대로 「나눔고딕」 · 「나눔손글씨 꽃내음」 이다")
    func fontNamesInEnglish() {
        #expect(FontCase.myeongjo.title(locale: Self.english) == "Nanum Myeongjo")
        #expect(FontCase.gothic.title(locale: Self.english) == "Nanum Gothic")
        #expect(FontCase.flower.title(locale: Self.english) == "Nanum Flower Scent")
        #expect(FontCase.allCases.map(\.title) == ["나눔명조", "나눔고딕", "나눔손글씨 꽃내음"])
        // 표시 이름만 바뀌고 저장값(rawValue)은 그대로다.
        #expect(FontCase.allCases.map(\.rawValue) == ["NanumMyeongjo", "NanumGothic", "NanumFlowerScent"])
    }

    @Test("의견 종류는 화면 이름만 영어로 옮기고, 메일 제목에 쓰는 rawValue 는 한국어 그대로다")
    func feedbackTypesInEnglish() {
        #expect(UserFeedback.FeedbackType.allCases.map { $0.localizedName(locale: Self.english) } == ["General Inquiry", "Suggestion", "Other"])
        #expect(UserFeedback.FeedbackType.allCases.map(\.localizedName) == ["일반 문의", "개선 및 제안", "기타"])
        #expect(UserFeedback.FeedbackType.allCases.map(\.rawValue) == ["일반 문의", "개선 및 제안", "기타"])
    }

    @Test("의견 본문의 처음 머리는 앱 언어(시험은 한국어)다")
    func feedbackTemplateFollowsAppLanguage() {
        #expect(UserFeedback.initialState.body == "- 문의 내용:")
    }
}
