//
//  BibleVerseParsingTesting.swift
//  DomainTest
//
//  Created by Codex on 4/2/26.
//

@testable import Domain
import Testing

struct BibleVerseParsingTesting {
    @Test("문장에 소제목이 없으면 외부 기본 소제목을 유지한다")
    func keepsProvidedChapterTitleWhenSentenceHasNoEmbeddedTitle() {
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            chapterTitle: "기본 소제목",
            sentence: "3:16 하나님이 세상을 이처럼 사랑하사"
        )

        #expect(verse.chapterTitle == "기본 소제목")
        #expect(verse.verse == 16)
        #expect(verse.sentenceScript == "하나님이 세상을 이처럼 사랑하사")
    }

    @Test("문장 안 소제목이 있으면 외부 기본 소제목보다 우선한다")
    func prefersEmbeddedChapterTitleOverProvidedDefault() {
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            chapterTitle: "기본 소제목",
            sentence: "<하나님의 사랑> 3:16 하나님이 세상을 이처럼 사랑하사"
        )

        #expect(verse.chapterTitle == "하나님의 사랑")
        #expect(verse.verse == 16)
        #expect(verse.sentenceScript == "하나님이 세상을 이처럼 사랑하사")
    }

    @Test("장절 표기가 없으면 절 번호는 0으로 두고 본문은 유지한다")
    func defaultsVerseToZeroWhenReferenceIsMissing() {
        let verse = BibleVerse(
            title: BibleChapter(title: .psalms, chapter: 1),
            sentence: "<복 있는 사람> 오직 여호와의 율법을 즐거워하여"
        )

        #expect(verse.chapterTitle == "복 있는 사람")
        #expect(verse.verse == 0)
        #expect(verse.sentenceScript == "오직 여호와의 율법을 즐거워하여")
    }

    @Test("장절 표기가 먼저 나와도 뒤의 소제목을 계속 파싱한다")
    func parsesEmbeddedTitleEvenWhenItAppearsAfterReference() {
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            sentence: "3:16 <하나님의 사랑> 하나님이 세상을 이처럼 사랑하사"
        )

        #expect(verse.chapterTitle == "하나님의 사랑")
        #expect(verse.verse == 16)
        #expect(verse.sentenceScript == "하나님이 세상을 이처럼 사랑하사")
    }

    @Test("외부 기본 소제목과 장절만 있으면 기본 소제목을 유지한다")
    func keepsProvidedChapterTitleWhenOnlyReferenceExists() {
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            chapterTitle: "기본 소제목",
            sentence: "3:16 하나님이 세상을 이처럼 사랑하사"
        )

        #expect(verse.chapterTitle == "기본 소제목")
        #expect(verse.verse == 16)
        #expect(verse.sentenceScript == "하나님이 세상을 이처럼 사랑하사")
    }

    @Test("소제목과 장절 사이 공백이 없어도 본문을 분리한다")
    func parsesWithoutSpacesBetweenTitleReferenceAndSentence() {
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            sentence: "<하나님의 사랑>3:16하나님이 세상을 이처럼 사랑하사"
        )

        #expect(verse.chapterTitle == "하나님의 사랑")
        #expect(verse.verse == 16)
        #expect(verse.sentenceScript == "하나님이 세상을 이처럼 사랑하사")
    }

    @Test("장절만 있고 본문이 없으면 빈 문자열로 정리하고 기본 소제목을 유지한다")
    func keepsProvidedChapterTitleWhenReferenceHasNoBody() {
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            chapterTitle: "기본 소제목",
            sentence: "3:16"
        )

        #expect(verse.chapterTitle == "기본 소제목")
        #expect(verse.verse == 16)
        #expect(verse.sentenceScript.isEmpty)
    }

    @Test("소제목과 장절만 있으면 본문은 비우고 소제목과 절 번호는 유지한다")
    func parsesTitleAndReferenceWithoutBody() {
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            sentence: "<하나님의 사랑> 3:16"
        )

        #expect(verse.chapterTitle == "하나님의 사랑")
        #expect(verse.verse == 16)
        #expect(verse.sentenceScript.isEmpty)
    }

    @Test("줄바꿈으로 나뉜 소제목과 장절도 파싱한 뒤 본문 줄바꿈은 유지한다")
    func preservesInnerLineBreaksAfterParsingTitleAndReference() {
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            sentence: "<하나님의 사랑>\n3:16\n하나님이 세상을\n이처럼 사랑하사"
        )

        #expect(verse.chapterTitle == "하나님의 사랑")
        #expect(verse.verse == 16)
        #expect(verse.sentenceScript == "하나님이 세상을\n이처럼 사랑하사")
    }

    @Test("장절과 소제목이 모두 없으면 기본 소제목과 본문을 그대로 유지한다")
    func keepsProvidedChapterTitleAndBodyWhenReferenceIsMissing() {
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            chapterTitle: "기본 소제목",
            sentence: "하나님이 세상을 이처럼 사랑하사"
        )

        #expect(verse.chapterTitle == "기본 소제목")
        #expect(verse.verse == 0)
        #expect(verse.sentenceScript == "하나님이 세상을 이처럼 사랑하사")
    }

    @Test("소제목 안 참조(대상 1:5-23)는 절 번호로 읽지 않는다")
    func ignoresReferenceInsideHeading() {
        let verse = BibleVerse(
            title: BibleChapter(title: .genesis, chapter: 10),
            sentence: "10:1 <노아의 아들들의 족보(대상 1:5-23)> 노아의 아들 셈과 함과 야벳의 족보는 이러하니라"
        )

        #expect(verse.verse == 1)
        #expect(verse.chapterTitle == "노아의 아들들의 족보(대상 1:5-23)")
        #expect(verse.sentenceScript == "노아의 아들 셈과 함과 야벳의 족보는 이러하니라")
    }

    @Test("합쳐진 절(6:18-19)은 앞 번호를 절로, 뒤 번호를 끝 절로 두고 본문에 범위를 남기지 않는다")
    func parsesMergedVerseRange() {
        let verse = BibleVerse(
            title: BibleChapter(title: .deuteronomy, chapter: 6),
            sentence: "6:18-19 여호와께서 보시기에 정직하고 선량한 일을 행하라"
        )

        #expect(verse.verse == 18)
        #expect(verse.verseEnd == 19)
        #expect(verse.sentenceScript == "여호와께서 보시기에 정직하고 선량한 일을 행하라")
    }

    @Test("합쳐진 절 뒤의 소제목도 뽑는다(시 92:1-3)")
    func parsesHeadingAfterMergedVerseRange() {
        let verse = BibleVerse(
            title: BibleChapter(title: .psalms, chapter: 92),
            sentence: "92:1-3 <안식일의 찬송 시> 지존자여 십현금과 비파와 수금으로"
        )

        #expect(verse.verse == 1)
        #expect(verse.verseEnd == 3)
        #expect(verse.chapterTitle == "안식일의 찬송 시")
        #expect(verse.sentenceScript == "지존자여 십현금과 비파와 수금으로")
    }

    @Test("보통 절은 끝 절 번호가 없다")
    func singleVerseHasNoVerseEnd() {
        let verse = BibleVerse(title: BibleChapter(title: .john, chapter: 3), sentence: "3:16 하나님이 세상을 이처럼 사랑하사")

        #expect(verse.verseEnd == nil)
    }

    @Test("절 번호 없이 이어지는 줄은 장 접두어를 지우고, 가운데 소제목 양옆 본문을 공백 하나로 잇는다")
    func parsesContinuationLineWithoutVerseNumber() {
        let verse = BibleVerse(
            title: BibleChapter(title: .genesis, chapter: 35),
            sentence: "35:야곱의 <야곱의 아들들(대상 2:1-2)> 아들은 열둘이라"
        )

        #expect(verse.verse == 0)
        #expect(verse.chapterTitle == "야곱의 아들들(대상 2:1-2)")
        #expect(verse.sentenceScript == "야곱의 아들은 열둘이라")
    }

    @Test("장절 뒤 본문 안 참조 숫자는 본문으로 둔다")
    func keepsReferenceLikeTextInsideBody() {
        let verse = BibleVerse(title: BibleChapter(title: .john, chapter: 3), sentence: "3:16 3:17 에 이어진다")

        #expect(verse.verse == 16)
        #expect(verse.sentenceScript == "3:17 에 이어진다")
    }
}
