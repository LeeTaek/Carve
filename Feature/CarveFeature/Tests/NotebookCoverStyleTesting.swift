//
//  NotebookCoverStyleTesting.swift
//  CarveFeatureTest
//
//  Created by Claude on 10/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

@testable import CarveFeature
import Domain
import Foundation
import Testing

/// 책장 표지(시안 P1) — 이름의 서수 풀기 · 표지 고르기 · 번호 글자 · 표지 아래 기록 한 줄.
@Suite("책장 표지")
struct NotebookCoverStyleTesting {
    private static let korean = Locale(identifier: "ko")
    private static let english = Locale(identifier: "en")

    private static func notebook(
        _ id: NotebookID,
        name: String?,
        createdAt: Date? = nil,
        writtenVerseCount: Int = 0
    ) -> NotebookSnapshot {
        NotebookSnapshot(
            id: id,
            name: name,
            status: .active,
            createdAt: createdAt,
            completedAt: nil,
            writtenVerseCount: writtenVerseCount,
            hasMetadata: name != nil
        )
    }

    private static let otherID = NotebookID.make(uuid: UUID(uuidString: "0F3A2B4C-5D6E-4F70-8192-A3B4C5D6E7F8")!)

    @Test("서수 꼴 이름은 한국어 · 영어 모두 그 서수로 풀린다")
    func ordinalNames() {
        #expect(NotebookNaming.ordinal(inName: "첫 번째 필사") == 1)
        #expect(NotebookNaming.ordinal(inName: "세 번째 필사") == 3)
        #expect(NotebookNaming.ordinal(inName: "열 번째 필사") == 10)
        #expect(NotebookNaming.ordinal(inName: "11번째 필사") == 11)
        #expect(NotebookNaming.ordinal(inName: "99번째 필사") == 99)
        #expect(NotebookNaming.ordinal(inName: "First Notebook") == 1)
        #expect(NotebookNaming.ordinal(inName: "Notebook 3") == 3)
        // 앞뒤 공백은 무시한다.
        #expect(NotebookNaming.ordinal(inName: "  두 번째 필사 ") == 2)
    }

    @Test("서수 꼴이 아닌 이름은 번호가 없다")
    func nonOrdinalNames() {
        #expect(NotebookNaming.ordinal(inName: "시편 묵상") == nil)
        #expect(NotebookNaming.ordinal(inName: "두번째 필사") == nil)
        #expect(NotebookNaming.ordinal(inName: "이름 없는 필사책") == nil)
        #expect(NotebookNaming.ordinal(inName: "Notebook 100") == nil)
        #expect(NotebookNaming.ordinal(inName: "") == nil)
    }

    @Test("번호가 있는 표지는 번호 순서의 표지 — 01 회색 · 02 따뜻한 회색 · 03 세이지, 6 부터 다시")
    func numberedCovers() {
        let unnamedDefault = NotebookCoverStyle.make(for: Self.notebook(.default, name: nil), locale: Self.korean)
        #expect(unnamedDefault == NotebookCoverStyle(theme: .stone, number: 1))

        let second = NotebookCoverStyle.make(for: Self.notebook(Self.otherID, name: "두 번째 필사"), locale: Self.korean)
        #expect(second == NotebookCoverStyle(theme: .linen, number: 2))

        let third = NotebookCoverStyle.make(for: Self.notebook(Self.otherID, name: "Notebook 3"), locale: Self.korean)
        #expect(third == NotebookCoverStyle(theme: .sage, number: 3))

        let sixth = NotebookCoverStyle.make(for: Self.notebook(Self.otherID, name: "여섯 번째 필사"), locale: Self.english)
        #expect(sixth == NotebookCoverStyle(theme: .stone, number: 6))
    }

    @Test("이름을 지은 표지는 번호 없이 필사책 ID 의 고정 해시로 고른다 — 같은 ID 는 늘 같은 표지")
    func namedCovers() {
        let style = NotebookCoverStyle.make(for: Self.notebook(Self.otherID, name: "시편 묵상"), locale: Self.korean)
        let index = Int(NotebookCoverStyle.stableHash(Self.otherID.rawValue) % UInt32(NotebookCoverTheme.allCases.count))
        #expect(style == NotebookCoverStyle(theme: NotebookCoverTheme.allCases[index], number: nil))
        // 이름만 바꿔도(서수 꼴이 아니면) 표지는 같다.
        let renamed = NotebookCoverStyle.make(for: Self.notebook(Self.otherID, name: "복음서 필사"), locale: Self.korean)
        #expect(renamed == style)
        // 메타데이터에 이름이 없는 다른 필사책(「이름 없는 필사책」)도 해시로 고른다.
        let untitled = NotebookCoverStyle.make(for: Self.notebook(Self.otherID, name: nil), locale: Self.korean)
        #expect(untitled == style)
    }

    @Test("고정 해시는 실행과 상관없는 FNV-1a 32비트다")
    func stableHash() {
        #expect(NotebookCoverStyle.stableHash("") == 2_166_136_261)
        #expect(NotebookCoverStyle.stableHash("a") == 0xE40C_292C)
    }

    @Test("표지 번호는 두 자리로 채운다")
    func numberText() {
        #expect(NotebookCoverStyle.numberText(1) == "01")
        #expect(NotebookCoverStyle.numberText(12) == "12")
        #expect(NotebookCoverStyle.numberText(100) == "100")
    }

    @Test("표지 아래 기록 한 줄 — 시작 월 · 쓴 절 수, 만든 시각을 모르면 쓴 절 수만")
    func metadataText() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        let october = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9)))
        let notebook = Self.notebook(Self.otherID, name: "세 번째 필사", createdAt: october, writtenVerseCount: 128)

        #expect(NotebookShelfView.metadataText(of: notebook, calendar: calendar, locale: Self.korean) == "2026년 10월 시작 · 128절 필사")
        #expect(NotebookShelfView.metadataText(of: notebook, calendar: calendar, locale: Self.english) == "Started October 2026 · 128 verses written")

        let undated = Self.notebook(Self.otherID, name: nil, writtenVerseCount: 1)
        #expect(NotebookShelfView.metadataText(of: undated, calendar: calendar, locale: Self.english) == "1 verse written")
    }
}
