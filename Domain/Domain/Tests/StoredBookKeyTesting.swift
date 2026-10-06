//
//  StoredBookKeyTesting.swift
//  DomainTest
//
//  Created by Claude on 10/6/26.
//

@testable import Domain
import Testing

/// SwiftData 행의 권 이름(`titleName`) · 번역본 열 규칙(영어 현지화 결정 1)을 본다.
struct StoredBookKeyTesting {
    @Test("모든 번역본 · 권의 titleName 은 같은 권 · 번역본으로 풀린다")
    func titleNameRoundTripsForEveryTranslationAndBook() throws {
        for translation in Translation.allCases {
            for title in BibleTitle.allCases {
                // When
                let decoded = try #require(StoredBookKey.decode(StoredBookKey.titleName(title: title, translation: translation)))

                // Then
                #expect(decoded.title == title)
                #expect(decoded.translation == translation)
            }
        }
    }

    @Test("개역개정 행은 rawValue 그대로, 영어 행은 번역본 접두를 붙이고 본문 리소스 파일 이름과 같다")
    func titleNameFollowsTranslationPrefixRule() {
        #expect(StoredBookKey.titleName(title: .genesis, translation: .NKRV) == "1-01Genesis.txt")
        #expect(StoredBookKey.titleName(title: .genesis, translation: .KJV) == "KJV-1-01Genesis.txt")
        #expect(StoredBookKey.titleName(title: .revelation, translation: .BSB) == "BSB-2-27Revelation.txt")
        for translation in Translation.allCases {
            for title in BibleTitle.allCases {
                #expect(StoredBookKey.titleName(title: title, translation: translation) == translation.resourceFileName(for: title))
            }
        }
    }

    @Test("장으로 지을 때는 장의 번역본을 쓴다")
    func titleNameForChapterUsesChapterTranslation() {
        #expect(StoredBookKey.titleName(for: BibleChapter(title: .psalms, chapter: 119)) == "1-19Psalms.txt")
        #expect(StoredBookKey.titleName(for: BibleChapter(title: .psalms, chapter: 119, translation: .KJV)) == "KJV-1-19Psalms.txt")
        #expect(StoredBookKey.titleName(for: BibleChapter(title: .john, chapter: 3, translation: .BSB)) == "BSB-2-04John.txt")
    }

    @Test("접두 없는 행은 개역개정이다")
    func unprefixedTitleNameDecodesAsNKRV() throws {
        // Given — 지금까지 저장된 개역개정 행(열이 nil 이든 .NKRV 든 titleName 은 같다)
        let decoded = try #require(StoredBookKey.decode("1-01Genesis.txt"))

        // Then
        #expect(decoded.title == .genesis)
        #expect(decoded.translation == .NKRV)
    }

    @Test("모르는 접두 · 모르는 권 · 빈 이름은 풀지 못한다")
    func unknownPrefixOrBookDecodesAsNil() {
        #expect(Self.decoded("ESV-1-01Genesis.txt") == nil)
        #expect(Self.decoded("kjv-1-01Genesis.txt") == nil)
        #expect(Self.decoded("KJV-NotABook.txt") == nil)
        #expect(Self.decoded("KJV-") == nil)
        #expect(Self.decoded("KJV1-01Genesis.txt") == nil)
        #expect(Self.decoded("NotABook.txt") == nil)
        #expect(Self.decoded("") == nil)
    }

    @Test("translation 열에는 개역개정만 쓰고 영어 번역본은 nil 이다")
    func translationColumnKeepsOnlyNKRV() {
        #expect(StoredBookKey.translationColumn(for: .NKRV) == .NKRV)
        #expect(StoredBookKey.translationColumn(for: .KJV) == nil)
        #expect(StoredBookKey.translationColumn(for: .BSB) == nil)
    }

    @Test("NKRV- 접두는 짓지 않고, 그런 이름은 풀지도 않는다")
    func nkrvPrefixIsNeverProduced() {
        for title in BibleTitle.allCases {
            let titleName = StoredBookKey.titleName(title: title, translation: .NKRV)
            #expect(!titleName.hasPrefix("NKRV-"))
            #expect(titleName == title.rawValue)
        }
        #expect(Self.decoded("NKRV-1-01Genesis.txt") == nil)
    }

    /// 역할: 푼 결과를 비교하기 쉬운 문자열로 바꾼다(튜플은 Equatable 이 아니다).
    /// 입력 · 출력: `titleName` → `"<권 rawValue>|<번역본 rawValue>"`, 풀지 못하면 nil.
    /// 부작용: 없음.
    private static func decoded(_ titleName: String) -> String? {
        StoredBookKey.decode(titleName).map { "\($0.title.rawValue)|\($0.translation.rawValue)" }
    }
}
