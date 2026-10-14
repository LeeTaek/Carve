//
//  BibleChapterTextParsingTesting.swift
//  DomainTest
//
//  Created by Claude on 9/30/26.
//

@testable import Domain
import Testing

/// 장 단위 본문 파싱. 필사는 (책, 장, 절 번호) 로 저장되므로 절 번호가 성경 절과 같고 한 장 안에서 겹치지 않아야 한다.
struct BibleChapterTextParsingTesting {
    private func verses(_ lines: [String], chapter: Int, title: BibleTitle = .genesis) -> [BibleVerse] {
        BibleChapterTextParser.verses(
            in: lines.joined(separator: "\r"),
            chapter: BibleChapter(title: title, chapter: chapter)
        )
    }

    @Test("절 번호 없이 이어지는 줄은 앞 절 본문에 잇고, 그 줄의 소제목은 다음 절 위로 옮긴다")
    func continuationLineJoinsPreviousVerseAndMovesHeadingToNextVerse() {
        let result = verses([
            "35:22 이스라엘이 이를 들었더라",
            "35:야곱의 <야곱의 아들들(대상 2:1-2)> 아들은 열둘이라",
            "35:23 레아의 아들들은"
        ], chapter: 35)

        #expect(result.map(\.verse) == [22, 23])
        #expect(result[0].sentenceScript == "이스라엘이 이를 들었더라 야곱의 아들은 열둘이라")
        #expect(result[0].chapterTitle == nil)
        #expect(result[1].chapterTitle == "야곱의 아들들(대상 2:1-2)")
    }

    @Test("한 장에 이어지는 줄이 여럿이어도 절 번호가 겹치지 않는다(사 21장)")
    func multipleContinuationLinesKeepVerseNumbersUnique() {
        let result = verses([
            "21:10 내가 타작하는 너여",
            "21:사람이 세일에서 나를 부르되",
            "21:11 두마에 관한 경고라",
            "21:드단 대상들이여"
        ], chapter: 21, title: .isaiah)

        #expect(result.map(\.verse) == [10, 11])
        #expect(result[0].sentenceScript == "내가 타작하는 너여 사람이 세일에서 나를 부르되")
        #expect(result[1].sentenceScript == "두마에 관한 경고라 드단 대상들이여")
    }

    @Test("시편 권 표시(1:제일권)는 행이 아니라 1절 소제목이 된다")
    func psalmBookLabelBecomesFirstVerseHeading() {
        let result = verses([
            "1:제일권",
            "1:1 복 있는 사람은",
            "1:2 오직 여호와의 율법을"
        ], chapter: 1, title: .psalms)

        #expect(result.map(\.verse) == [1, 2])
        #expect(result[0].chapterTitle == "제1권")
        #expect(result[0].sentenceScript == "복 있는 사람은")
    }

    @Test("권 표시 뒤 1절에 소제목이 있으면 권 표시를 앞에 둔 두 줄이 된다(시 42편)")
    func psalmBookLabelPrecedesExistingHeading() {
        let result = verses([
            "41:13 여호와를 송축할지로다 아멘 아멘",
            "42:제이권",
            "42:1 <고라 자손의 마스길, 인도자를 따라 부르는 노래> 하나님이여"
        ], chapter: 42, title: .psalms)

        #expect(result.count == 1)
        #expect(result[0].chapterTitle == "제2권\n고라 자손의 마스길, 인도자를 따라 부르는 노래")
    }

    @Test("합쳐진 절은 앞 번호로 저장하고 끝 번호를 따로 둔다")
    func mergedVerseKeepsStartNumberAsKey() {
        let result = verses([
            "6:17 너희의 하나님 여호와께서",
            "6:18-19 여호와께서 보시기에",
            "6:20 후일에 네 아들이"
        ], chapter: 6, title: .deuteronomy)

        #expect(result.map(\.verse) == [17, 18, 20])
        #expect(result[1].verseEnd == 19)
        #expect(result[1].sentenceScript == "여호와께서 보시기에")
    }

    @Test("다른 장의 줄과 그 장의 이어지는 줄은 섞이지 않는다")
    func excludesContinuationLinesOfOtherChapters() {
        let result = verses([
            "12:25 앞 장 끝",
            "12:앞 장에 이어지는 줄",
            "13:1 이 장 첫 절",
            "13:2 둘째 절",
            "14:1 다음 장"
        ], chapter: 13, title: .samuel1)

        #expect(result.map(\.verse) == [1, 2])
        #expect(result.map(\.sentenceScript) == ["이 장 첫 절", "둘째 절"])
    }

    @Test("장 접두어가 없는 줄은 바로 앞 줄의 장에 속한 이어지는 줄로 본다")
    func bareLineContinuesPreviousLineChapter() {
        let result = verses([
            "3:15 앞 절",
            "3:16 크도다 경건의 비밀이여",
            "그는 육신으로 나타난 바 되시고",
            "4:1 다음 장"
        ], chapter: 3, title: .timothy1)

        #expect(result.map(\.verse) == [15, 16])
        #expect(result[1].sentenceScript == "크도다 경건의 비밀이여 그는 육신으로 나타난 바 되시고")
    }

    @Test("절 안 줄바꿈(LF)은 본문에 그대로 둔다")
    func keepsLineFeedInsideVerse() {
        let result = verses(["3:16 크도다 경건의 비밀이여 \n그는 육신으로"], chapter: 3, title: .timothy1)

        #expect(result.first?.sentenceScript == "크도다 경건의 비밀이여 \n그는 육신으로")
    }

    @Test("빈 줄과 끝의 CR 은 무시한다")
    func ignoresEmptyLines() {
        let result = BibleChapterTextParser.verses(
            in: "1:1 첫 절\r\r1:2 둘째 절\r",
            chapter: BibleChapter(title: .genesis, chapter: 1)
        )

        #expect(result.map(\.verse) == [1, 2])
    }
}

/// 실제 개역개정 본문 66권 전체를 읽어 파싱 결과를 검사한다. 본문 파일을 바꾸거나 파서를 고칠 때의 회귀 방지선이다.
struct BibleTextCorpusTesting {
    /// 개역개정에 본문이 없는 절. 행 24:7 은 번역에서 빠져 있다.
    private static let omittedVerses: Set<String> = ["행 24:7"]

    private func fetch(_ title: BibleTitle, _ chapter: Int) throws -> [BibleVerse] {
        try ResourceBibleTextClient().fetch(chapter: BibleChapter(title: title, chapter: chapter))
    }

    @Test("모든 장의 절 번호가 1부터 빠짐없이 한 번씩 이어진다")
    func everyChapterHasContiguousUniqueVerseNumbers() throws {
        var problems: [String] = []
        for title in BibleTitle.allCases {
            for chapter in 1...title.lastChapter {
                let verses = try fetch(title, chapter)
                let name = "\(title.koreanTitle()) \(chapter)"
                guard let first = verses.first else {
                    problems.append("\(name): 절 없음")
                    continue
                }
                if first.verse != 1 { problems.append("\(name): 첫 절 \(first.verse)") }
                for (previous, next) in zip(verses, verses.dropFirst()) {
                    let expected = (previous.verseEnd ?? previous.verse) + 1
                    if next.verse != expected, !Self.omittedVerses.contains(omittedKey(title, chapter, expected)) {
                        problems.append("\(name): \(previous.verse) 다음 \(next.verse)")
                    }
                }
                for verse in verses where (verse.verseEnd ?? verse.verse + 1) <= verse.verse {
                    problems.append("\(name):\(verse.verse) 끝 절 \(verse.verseEnd ?? 0)")
                }
            }
        }
        #expect(problems.isEmpty, "\(problems.prefix(20))")
    }

    @Test("본문과 소제목에 참조 · 괄호 찌꺼기가 남지 않는다")
    func noLeftoverMarkupInSentencesOrHeadings() throws {
        var problems: [String] = []
        for title in BibleTitle.allCases {
            for chapter in 1...title.lastChapter {
                for verse in try fetch(title, chapter) {
                    let name = "\(title.koreanTitle()) \(chapter):\(verse.verse)"
                    let text = verse.sentenceScript
                    if text.isEmpty { problems.append("\(name) 빈 본문") }
                    if text.contains("<") || text.contains(">") { problems.append("\(name) 본문에 <>") }
                    if startsWithReference(text) { problems.append("\(name) 본문이 참조로 시작: \(text.prefix(20))") }
                    if let heading = verse.chapterTitle,
                       heading.isEmpty || heading.contains("<") || heading.contains(">") {
                        problems.append("\(name) 소제목: \(heading.prefix(20))")
                    }
                }
            }
        }
        #expect(problems.isEmpty, "\(problems.prefix(20))")
    }

    @Test("형식이 다른 실제 줄들을 기대대로 정리한다")
    func representativeIrregularLines() throws {
        // 시편 1편: 권 표시가 1절 소제목이 되고 00 행이 생기지 않는다.
        let psalm1 = try fetch(.psalms, 1)
        #expect(psalm1.first?.verse == 1)
        #expect(psalm1.first?.chapterTitle == "제1권")
        #expect(psalm1.first?.sentenceScript.hasPrefix("복 있는 사람은") == true)

        // 시편 42편: 권 표시와 원래 소제목이 두 줄.
        #expect(try fetch(.psalms, 42).first?.chapterTitle?.hasPrefix("제2권\n고라 자손의 마스길") == true)

        // 시편 60편: 긴 소제목(100자 이상)이 통째로 1절 소제목이다.
        let psalm60Heading = try fetch(.psalms, 60).first?.chapterTitle ?? ""
        #expect(psalm60Heading.hasPrefix("다윗이 교훈하기 위하여 지은 믹담"))
        #expect(psalm60Heading.hasSuffix("만 이천 명을 죽인 때에"))

        // 창세기 35장: 소제목 안 참조(대상 2:1-2)를 1절로 잡아 절이 사라지던 줄.
        let genesis35 = try fetch(.genesis, 35)
        let verse22 = try #require(genesis35.first { $0.verse == 22 })
        let verse23 = try #require(genesis35.first { $0.verse == 23 })
        #expect(verse22.sentenceScript.hasSuffix("이스라엘이 이를 들었더라 야곱의 아들은 열둘이라"))
        #expect(verse23.chapterTitle == "야곱의 아들들(대상 2:1-2)")
        #expect(genesis35.filter { $0.verse == 1 }.count == 1)

        // 느헤미야 1장: 이어지는 줄이 00 행이 아니라 1절 본문 뒤에 붙는다.
        let nehemiah1 = try fetch(.nehemiah, 1)
        #expect(nehemiah1.first?.verse == 1)
        #expect(nehemiah1.first?.sentenceScript.hasSuffix("아닥사스다 왕 제이십년 기슬르월에 내가 수산 궁에 있는데") == true)

        // 신명기 6장: 합쳐진 절.
        let deuteronomy18 = try #require(try fetch(.deuteronomy, 6).first { $0.verse == 18 })
        #expect(deuteronomy18.verseEnd == 19)
        #expect(deuteronomy18.sentenceScript.hasPrefix("여호와께서 보시기에"))

        // 오바댜: 이어지는 줄의 본문 순서가 그대로 이어진다.
        let obadiah1 = try fetch(.obadiah, 1).first?.sentenceScript ?? ""
        #expect(obadiah1.hasPrefix("오바댜의 묵시라 주 여호와께서 에돔에 대하여 이와 같이 말씀하시니라"))
        #expect(obadiah1.hasSuffix("우리가 일어나서 그와 싸우자 하는 것이니라"))
    }

    private func omittedKey(_ title: BibleTitle, _ chapter: Int, _ verse: Int) -> String {
        title == .acts ? "행 \(chapter):\(verse)" : ""
    }

    /// `12:`, `12:3`, `-19` 처럼 참조 조각으로 시작하는가.
    private func startsWithReference(_ text: String) -> Bool {
        let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
        if !digits.isEmpty, text.dropFirst(digits.count).first == ":" { return true }
        if text.first == "-", text.dropFirst().first?.isNumber == true { return true }
        return false
    }
}
