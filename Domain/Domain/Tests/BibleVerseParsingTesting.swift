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
}
