//
//  EnglishBibleTextParsingTesting.swift
//  DomainTest
//
//  Created by Claude on 10/12/26.
//

@testable import Domain
import Foundation
import Testing

/// 실제 KJV · BSB 본문 리소스를 번역본별 로더(`ResourceBibleTextClient`)로 읽어 검사한다.
///
/// 본문은 `scripts/bibletext/bible_en_convert.py` 로만 만든다 — 다시 만들거나 파서 · 로더를 고칠 때의 회귀 방지선이다.
/// 파서는 개역개정과 같은 것(줄 CR, 소제목 여럿은 `<…>` 안 LF)을 쓴다.
struct EnglishBibleTextParsingTesting {
    /// 한 절의 위치(권 · 장 · 절). 진단 문자열은 권 `rawValue` 로 적는다.
    private struct VerseLocation: Equatable, CustomStringConvertible {
        var title: BibleTitle
        var chapter: Int
        var verse: Int

        var description: String { "\(title.rawValue) \(chapter):\(verse)" }
    }

    /// 한 번역본 66권을 장마다 로더로 읽은 결과.
    private struct CorpusScan {
        var bookCount = 0
        var chapterCount = 0
        var verseCount = 0
        /// 장 안에서 절 번호가 건너뛴 곳 — 그 번역본에 없는 절.
        var missingVerses: [VerseLocation] = []
        /// 장 · 절 번호 · 본문 · 소제목 문제.
        var problems: [String] = []
    }

    /// 본문 · 소제목에 남으면 안 되는 표지 · 줄 구분 문자. 소제목은 여러 줄을 LF 로 잇으므로 소제목에서는 LF 를 허용한다.
    private static let sentenceMarkup = CharacterSet(charactersIn: "<>\\¶\r\n")
    private static let headingMarkup = CharacterSet(charactersIn: "<>\\¶\r")

    /// BSB(비평 본문)에 줄이 없는 16절. KJV 에는 있다. 성경 순서다.
    private static let versesMissingFromBSB: [VerseLocation] = [
        VerseLocation(title: .matthew, chapter: 17, verse: 21),
        VerseLocation(title: .matthew, chapter: 18, verse: 11),
        VerseLocation(title: .matthew, chapter: 23, verse: 14),
        VerseLocation(title: .mark, chapter: 7, verse: 16),
        VerseLocation(title: .mark, chapter: 9, verse: 44),
        VerseLocation(title: .mark, chapter: 9, verse: 46),
        VerseLocation(title: .mark, chapter: 11, verse: 26),
        VerseLocation(title: .mark, chapter: 15, verse: 28),
        VerseLocation(title: .luke, chapter: 17, verse: 36),
        VerseLocation(title: .luke, chapter: 23, verse: 17),
        VerseLocation(title: .john, chapter: 5, verse: 4),
        VerseLocation(title: .acts, chapter: 8, verse: 37),
        VerseLocation(title: .acts, chapter: 15, verse: 34),
        VerseLocation(title: .acts, chapter: 24, verse: 7),
        VerseLocation(title: .acts, chapter: 28, verse: 29),
        VerseLocation(title: .romans, chapter: 16, verse: 24)
    ]

    private func fetch(_ translation: Translation, _ title: BibleTitle, _ chapter: Int) throws -> [BibleVerse] {
        try ResourceBibleTextClient().fetch(chapter: BibleChapter(title: title, chapter: chapter, translation: translation))
    }

    // MARK: - 전체 본문

    @Test("KJV 는 31,102절, 66권 장 수가 개역개정과 같고(1,189장) 장마다 절 번호가 1부터 빠짐없이 이어진다")
    func kjvCorpusCountsAndVerseNumbers() throws {
        let scan = try scanCorpus(.KJV)

        #expect(scan.bookCount == 66)
        #expect(scan.chapterCount == 1_189)
        #expect(scan.verseCount == 31_102)
        #expect(scan.missingVerses.isEmpty, "\(scan.missingVerses.prefix(20))")
        #expect(scan.problems.isEmpty, "\(scan.problems.prefix(20))")
    }

    @Test("BSB 는 31,086절, 66권 장 수가 개역개정과 같고(1,189장) 빠진 절은 비평 본문 16절뿐이다")
    func bsbCorpusCountsAndVerseNumbers() throws {
        let scan = try scanCorpus(.BSB)

        #expect(scan.bookCount == 66)
        #expect(scan.chapterCount == 1_189)
        #expect(scan.verseCount == 31_086)
        #expect(scan.missingVerses == Self.versesMissingFromBSB)
        #expect(scan.problems.isEmpty, "\(scan.problems.prefix(20))")
    }

    // MARK: - 절 집합

    @Test("BSB 에 없는 16절(마 17:21 · 18:11 · 23:14, 막 7:16 · 9:44 · 9:46 · 11:26 · 15:28, 눅 17:36 · 23:17, 요 5:4, 행 8:37 · 15:34 · 24:7 · 28:29, 롬 16:24)은 KJV 에 있다")
    func versesMissingFromBSBExistInKJV() throws {
        for location in Self.versesMissingFromBSB {
            let bsbVerses = try fetch(.BSB, location.title, location.chapter).map(\.verse)
            let kjvVerses = try fetch(.KJV, location.title, location.chapter).map(\.verse)

            #expect(!bsbVerses.contains(location.verse), "BSB \(location)")
            #expect(bsbVerses.contains(location.verse + 1), "BSB \(location) 다음 절")
            #expect(kjvVerses.contains(location.verse), "KJV \(location)")
        }
    }

    @Test("KJV 는 요삼 1장이 14절까지, 고후 13:14 · 행 24:7 이 있다 — 개역개정과 절 집합이 다른 곳")
    func kjvVerseSetDiffersFromNKRVWhereExpected() throws {
        #expect(try fetch(.KJV, .john3, 1).map(\.verse) == Array(1...14))
        #expect(try fetch(.NKRV, .john3, 1).last?.verse == 15)

        #expect(try fetch(.KJV, .corinthians2, 13).last?.verse == 14)
        #expect(try fetch(.NKRV, .corinthians2, 13).last?.verse == 13)

        let kjvActs24 = try fetch(.KJV, .acts, 24).map(\.verse)
        let nkrvActs24 = try fetch(.NKRV, .acts, 24).map(\.verse)
        #expect(kjvActs24.contains(7))
        #expect(!nkrvActs24.contains(7))
    }

    @Test("빌레몬서 1:1 과 1:2 는 따로 있는 절이다")
    func philemonFirstTwoVersesAreSeparate() throws {
        let kjv = try fetch(.KJV, .philemon, 1)
        let bsb = try fetch(.BSB, .philemon, 1)

        #expect(kjv.map(\.verse) == Array(1...25))
        #expect(bsb.map(\.verse) == Array(1...25))
        #expect(kjv.first?.sentenceScript == "Paul, a prisoner of Jesus Christ, and Timothy our brother, unto Philemon our dearly beloved, and fellowlabourer,")
        #expect(kjv.dropFirst().first?.sentenceScript.hasPrefix("And to our beloved Apphia") == true)
        #expect(bsb.dropFirst().first?.sentenceScript.hasPrefix("to Apphia our sister") == true)
    }

    // MARK: - 소제목

    @Test("시편 표제 · 119편 자모는 절 소제목이다(시 3:1 · 119:1 · 119:9)")
    func psalmTitlesAndAcrosticLettersAreHeadings() throws {
        let kjvPsalm3 = try #require(try fetch(.KJV, .psalms, 3).first)
        #expect(kjvPsalm3.verse == 1)
        #expect(kjvPsalm3.chapterTitle == "A Psalm of David, when he fled from Absalom his son.")
        #expect(kjvPsalm3.sentenceScript.hasPrefix("LORD, how are they increased that trouble me!"))

        let bsbPsalm3 = try #require(try fetch(.BSB, .psalms, 3).first)
        #expect(bsbPsalm3.verse == 1)
        #expect(bsbPsalm3.chapterTitle == "Deliver Me, O LORD!\nA Psalm of David, when he fled from his son Absalom.")
        #expect(bsbPsalm3.sentenceScript.hasPrefix("O LORD, how my foes have increased!"))

        let kjvPsalm119 = try fetch(.KJV, .psalms, 119)
        #expect(kjvPsalm119.count == 176)
        #expect(kjvPsalm119.first { $0.verse == 1 }?.chapterTitle == "Aleph")
        #expect(kjvPsalm119.first { $0.verse == 8 }?.chapterTitle == nil)
        #expect(kjvPsalm119.first { $0.verse == 9 }?.chapterTitle == "Beth")

        let bsbPsalm119 = try fetch(.BSB, .psalms, 119)
        #expect(bsbPsalm119.count == 176)
        #expect(bsbPsalm119.first { $0.verse == 1 }?.chapterTitle == "Your Word Is a Lamp to My Feet\nAleph")
        #expect(bsbPsalm119.first { $0.verse == 9 }?.chapterTitle == "Beth")
    }

    @Test("BSB 시편 권 표시와 표제는 LF 로 이어진 한 소제목이다(시 1 · 42편)")
    func bsbPsalmBookLabelJoinsHeadingWithLineFeed() throws {
        let psalm1 = try #require(try fetch(.BSB, .psalms, 1).first)
        #expect(psalm1.chapterTitle == "Book I\nThe Two Paths")
        #expect(psalm1.sentenceScript.hasPrefix("Blessed is the man who does not walk"))

        let psalm42 = try #require(try fetch(.BSB, .psalms, 42).first)
        #expect(psalm42.chapterTitle == "Book II\nAs the Deer Pants for the Water\nFor the choirmaster. A Maskil of the sons of Korah.")
    }

    @Test("BSB 단락 소제목은 그 절 위에 붙는다 — 마 17:22, KJV 같은 절에는 소제목이 없다")
    func bsbSectionHeadingSitsOnVerse() throws {
        let bsbVerse22 = try #require(try fetch(.BSB, .matthew, 17).first { $0.verse == 22 })
        #expect(bsbVerse22.chapterTitle == "The Second Prediction of the Passion")
        #expect(bsbVerse22.sentenceScript.hasPrefix("When they gathered together in Galilee, Jesus told them,"))

        let kjvVerse22 = try #require(try fetch(.KJV, .matthew, 17).first { $0.verse == 22 })
        #expect(kjvVerse22.chapterTitle == nil)
        #expect(kjvVerse22.sentenceScript.hasPrefix("And while they abode in Galilee"))
    }

    // MARK: - 로더 · 인코딩

    @Test("같은 장도 번역본마다 자기 파일 · 인코딩으로 읽고, 절의 장에 번역본이 남는다")
    func loaderReadsFileAndEncodingOfChapterTranslation() throws {
        let nkrv = try #require(try fetch(.NKRV, .genesis, 1).first)
        let kjv = try #require(try fetch(.KJV, .genesis, 1).first)
        let bsb = try #require(try fetch(.BSB, .genesis, 1).first)

        #expect(nkrv.chapterTitle == "천지 창조")
        #expect(nkrv.sentenceScript == "태초에 하나님이 천지를 창조하시니라")
        #expect(kjv.chapterTitle == nil)
        #expect(kjv.sentenceScript == "In the beginning God created the heaven and the earth.")
        #expect(bsb.chapterTitle == "The Creation")
        #expect(bsb.sentenceScript == "In the beginning God created the heavens and the earth.")

        #expect(nkrv.title == BibleChapter(title: .genesis, chapter: 1, translation: .NKRV))
        #expect(kjv.title == BibleChapter(title: .genesis, chapter: 1, translation: .KJV))
        #expect(bsb.title == BibleChapter(title: .genesis, chapter: 1, translation: .BSB))
    }

    @Test("둥근 따옴표 · 작은따옴표 · 대시가 깨지지 않고 그대로 읽힌다")
    func typographicPunctuationSurvivesDecoding() throws {
        let genesis1 = try fetch(.BSB, .genesis, 1)
        #expect(genesis1.first { $0.verse == 3 }?.sentenceScript == "And God said, “Let there be light,” and there was light.")
        #expect(genesis1.first { $0.verse == 5 }?.sentenceScript
            == "God called the light “day,” and the darkness He called “night.” And there was evening, and there was morning — the first day.")

        let genesis4 = try fetch(.BSB, .genesis, 4)
        #expect(genesis4.first { $0.verse == 2 }?.sentenceScript.hasPrefix("Later she gave birth to Cain’s brother Abel.") == true)

        let matthew17 = try fetch(.BSB, .matthew, 17)
        #expect(matthew17.first { $0.verse == 20 }?.sentenceScript.contains("‘Move from here to there,’") == true)
    }

    // MARK: - 도우미

    /// 역할: 한 번역본 66권의 모든 장(개역개정 장 수 `lastChapter` 까지)을 로더로 읽어 수 · 빠진 절 · 문제를 모은다.
    /// 입력 · 출력: 번역본 → `CorpusScan`. 부작용: 번들 파일 읽기.
    private func scanCorpus(_ translation: Translation) throws -> CorpusScan {
        var scan = CorpusScan()
        for title in BibleTitle.allCases {
            scan.bookCount += 1
            for chapter in 1...title.lastChapter {
                let verses = try fetch(translation, title, chapter)
                let name = "\(title.rawValue) \(chapter)"
                guard let first = verses.first else {
                    scan.problems.append("\(name): 절 없음")
                    continue
                }
                scan.chapterCount += 1
                scan.verseCount += verses.count
                if first.verse != 1 { scan.problems.append("\(name): 첫 절 \(first.verse)") }
                for (previous, next) in zip(verses, verses.dropFirst()) {
                    if next.verse <= previous.verse { scan.problems.append("\(name): \(previous.verse) 다음 \(next.verse)") }
                    for missing in stride(from: previous.verse + 1, to: next.verse, by: 1) {
                        scan.missingVerses.append(VerseLocation(title: title, chapter: chapter, verse: missing))
                    }
                }
                let expectedChapter = BibleChapter(title: title, chapter: chapter, translation: translation)
                for verse in verses {
                    scan.problems += problems(in: verse, name: "\(name):\(verse.verse)", expectedChapter: expectedChapter)
                }
            }
            // 장 수가 개역개정과 같다 — 마지막 장 다음 장은 없다.
            if try !fetch(translation, title, title.lastChapter + 1).isEmpty {
                scan.problems.append("\(title.rawValue): \(title.lastChapter + 1)장이 있다")
            }
        }
        return scan
    }

    /// 한 절의 본문 · 소제목에 남은 표지 · 참조 조각 · 깨진 문자를 찾는다.
    private func problems(in verse: BibleVerse, name: String, expectedChapter: BibleChapter) -> [String] {
        var problems: [String] = []
        let text = verse.sentenceScript
        if verse.title != expectedChapter { problems.append("\(name) 장 \(verse.title)") }
        if verse.verseEnd != nil { problems.append("\(name) 합쳐진 절") }
        if text.isEmpty { problems.append("\(name) 빈 본문") }
        if text != text.trimmingCharacters(in: .whitespacesAndNewlines) { problems.append("\(name) 본문 양끝 공백") }
        if text.rangeOfCharacter(from: Self.sentenceMarkup) != nil { problems.append("\(name) 본문 표지: \(text.prefix(30))") }
        if isMojibake(text) { problems.append("\(name) 본문 깨진 문자: \(text.prefix(30))") }
        if startsWithReference(text) { problems.append("\(name) 본문이 참조로 시작: \(text.prefix(20))") }
        if let heading = verse.chapterTitle {
            if heading.isEmpty || heading.rangeOfCharacter(from: Self.headingMarkup) != nil { problems.append("\(name) 소제목: \(heading.prefix(30))") }
            if isMojibake(heading) { problems.append("\(name) 소제목 깨진 문자: \(heading.prefix(30))") }
        }
        return problems
    }

    /// 대체 문자(U+FFFD)나 UTF-8 을 Latin-1 로 잘못 읽은 흔적(`â€`)이 있는가.
    private func isMojibake(_ text: String) -> Bool {
        text.contains("\u{FFFD}") || text.contains("â€")
    }

    /// `12:`, `12:3` 처럼 참조 조각으로 시작하는가.
    private func startsWithReference(_ text: String) -> Bool {
        let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
        return !digits.isEmpty && text.dropFirst(digits.count).first == ":"
    }
}
