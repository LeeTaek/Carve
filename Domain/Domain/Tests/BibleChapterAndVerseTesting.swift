//
//  BibleChapterAndVerseTesting.swift
//  DomainTest
//
//  Created by Codex on 4/2/26.
//

@testable import Domain
import Testing

struct BibleChapterAndVerseTesting {
    @Test
    func beforeWrapsFromGenesisToRevelation() {
        // 첫 권에서 이전으로 이동할 때 마지막 권으로 순환해야 한다.
        #expect(BibleTitle.genesis.before() == .revelation)
    }

    @Test
    func nextWrapsFromRevelationToGenesis() {
        // 마지막 권은 배열 범위를 벗어나지 않고 첫 권으로 순환해야 한다.
        #expect(BibleTitle.revelation.next() == .genesis)
    }

    @Test
    func isOldTestamentUsesCanonBoundary() {
        // 말라기까지는 구약, 마태복음부터는 신약으로 구분돼야 한다.
        #expect(BibleTitle.malachi.isOldtestment)
        #expect(!BibleTitle.matthew.isOldtestment)
    }

    @Test
    func verseInitParsesChapterTitleVerseAndSentence() {
        // "<소제목> 장:절 본문" 형식이 한 줄에 함께 들어와도 각 필드가 분리돼야 한다.
        let verse = BibleVerse(
            title: BibleChapter(title: .john, chapter: 3),
            sentence: "<하나님의 사랑> 3:16 하나님이 세상을 이처럼 사랑하사"
        )

        #expect(verse.chapterTitle == "하나님의 사랑")
        #expect(verse.verse == 16)
        #expect(verse.sentenceScript == "하나님이 세상을 이처럼 사랑하사")
    }

    @Test
    func bibleTextClientFetchesOnlyRequestedChapterVerses() throws {
        let chapter = BibleChapter(title: .genesis, chapter: 1)

        // 리소스 파일 전체를 읽더라도 요청한 장 번호에 해당하는 절만 반환해야 한다.
        let verses = try ResourceBibleTextClient().fetch(chapter: chapter)

        #expect(!verses.isEmpty)
        #expect(verses.allSatisfy { $0.title == chapter })
        #expect(verses.allSatisfy { !$0.sentenceScript.isEmpty })
        #expect(verses.contains { $0.verse == 1 })
    }

    @Test
    func getTitleFallsBackToGenesisWhenNoMatchExists() {
        // 파일명 규칙이 깨진 입력이 들어와도 기본값은 안정적으로 창세기여야 한다.
        #expect(BibleTitle.getTitle("NotExistingBook.txt") == .genesis)
    }

    @Test
    func getTitleMatchesEmbeddedFilenameFragment() {
        // 리소스 경로 일부만 들어와도 해당 책을 안정적으로 찾아야 한다.
        #expect(BibleTitle.getTitle("2-04John") == .john)
    }

    @Test("대표 책의 마지막 장 수를 정경 기준으로 반환한다")
    func lastChapterReturnsCanonicalCountsForRepresentativeBooks() {
        #expect(BibleTitle.genesis.lastChapter == 50)
        #expect(BibleTitle.psalms.lastChapter == 150)
        #expect(BibleTitle.obadiah.lastChapter == 1)
        #expect(BibleTitle.revelation.lastChapter == 22)
    }

    @Test("대표 책의 한글 제목을 올바르게 반환한다")
    func koreanTitleReturnsLocalizedNameForRepresentativeBooks() {
        #expect(BibleTitle.genesis.koreanTitle() == "창세기")
        #expect(BibleTitle.john.koreanTitle() == "요한복음")
        #expect(BibleTitle.revelation.koreanTitle() == "요한계시록")
    }

    @Test("번호가 붙은 요한서신 파일명 조각도 정확한 책으로 매핑한다")
    func getTitleMatchesNumberedJohnEpistles() {
        #expect(BibleTitle.getTitle("2-23John1") == .john1)
        #expect(BibleTitle.getTitle("2-24John2") == .john2)
        #expect(BibleTitle.getTitle("2-25John3") == .john3)
    }
}
