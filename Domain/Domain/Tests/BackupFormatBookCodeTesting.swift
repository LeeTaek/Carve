//
//  BackupFormatBookCodeTesting.swift
//  DomainTest
//
//  필사 백업 형식 — USFM 권 코드(설계 §2-6)가 BibleTitle 66권과 1:1 양방향인가.
//

import Foundation
import Testing

@testable import Domain

@Suite("백업 형식 — USFM 권 코드")
struct BackupFormatBookCodeTesting {

    /// 설계 §2-6 표를 `BibleTitle` 파일 이름 번호 순서 그대로 옮긴 것.
    private let expectedCodes = [
        "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA",
        "1KI", "2KI", "1CH", "2CH", "EZR", "NEH", "EST", "JOB", "PSA", "PRO",
        "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS", "JOL", "AMO",
        "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL",
        "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH",
        "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS",
        "1PE", "2PE", "1JN", "2JN", "3JN", "JUD", "REV"
    ]

    @Test("66권 전수가 설계 표의 순서대로 코드가 된다")
    func everyTitleMapsToTheDesignTable() {
        #expect(BibleTitle.allCases.count == 66)
        #expect(BibleBookCode.allCases.count == 66)
        #expect(Set(expectedCodes).count == 66)
        #expect(BibleTitle.allCases.map { BibleBookCode(title: $0).rawValue } == expectedCodes)
        #expect(BibleBookCode.allCases.map(\.rawValue) == expectedCodes)
    }

    @Test("권 → 코드 → 권, 코드 → 권 → 코드가 66권 모두 제자리로 돌아온다")
    func bothDirectionsRoundTrip() {
        for title in BibleTitle.allCases {
            #expect(BibleBookCode(title: title).title == title)
        }
        for code in BibleBookCode.allCases {
            #expect(BibleBookCode(title: code.title) == code)
            #expect(BibleBookCode(rawValue: code.rawValue) == code)
        }
        #expect(Set(BibleBookCode.allCases.map(\.title)).count == 66)
    }

    @Test("이름이 헷갈리는 권")
    func easilyConfusedBooks() {
        #expect(BibleBookCode(title: .ecclesiasters) == .ecclesiastes)
        #expect(BibleBookCode(title: .ecclesiasters).rawValue == "ECC")
        #expect(BibleBookCode(title: .songOfSongs).rawValue == "SNG")
        #expect(BibleBookCode(title: .john).rawValue == "JHN")
        #expect(BibleBookCode(title: .john1).rawValue == "1JN")
        #expect(BibleBookCode(title: .philippians).rawValue == "PHP")
        #expect(BibleBookCode(title: .philemon).rawValue == "PHM")
        #expect(BibleBookCode(title: .ezekiel).rawValue == "EZK")
        #expect(BibleBookCode(title: .joel).rawValue == "JOL")
        #expect(BibleBookCode(title: .nahum).rawValue == "NAM")
        #expect(BibleBookCode(title: .mark).rawValue == "MRK")
    }

    @Test("모르는 코드 · 소문자는 권이 없다")
    func unknownCodesHaveNoTitle() {
        #expect(BibleBookCode(rawValue: "XYZ") == nil)
        #expect(BibleBookCode(rawValue: "gen") == nil)
        #expect(BibleBookCode(rawValue: "") == nil)
        #expect(BackupVerseKey(translation: nil, book: "TOB", chapter: 1, verse: 1).title == nil)
    }

    @Test("절 키는 권을 코드로 담고 다시 권으로 읽는다")
    func verseKeyUsesTheBookCode() {
        let key = BackupVerseKey(translation: nil, title: .revelation, chapter: 22, verse: 21)
        #expect(key.book == "REV")
        #expect(key.title == .revelation)
        #expect(key.translation == nil)
    }
}
