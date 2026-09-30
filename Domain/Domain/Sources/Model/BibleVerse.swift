//
//  BibleVerse.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//


import Foundation

/// 성경 제목/장, (선택적인) 소제목, 절 번호, 본문 텍스트 등 본문 데이터 모델.
public struct BibleVerse: Equatable, Sendable {
    /// 성경 이름/장.
    public var title: BibleChapter
    /// 장 앞에 붙는 소제목(예: "아브라함의 믿음")을 저장하는 필드.
    public var chapterTitle: String?
    /// 절(verse). 필사 · 즐겨찾기의 저장 키다. 합쳐진 절(`18-19`)은 앞 번호다.
    public var verse: Int
    /// 두 절 이상이 한 줄로 합쳐진 절의 마지막 절 번호(`신 6:18-19` 의 19). 보통의 절은 nil.
    public var verseEnd: Int?
    /// 절 본문 텍스트.
    public var sentenceScript: String

    public static let initialState = Self(
        title: BibleChapter(title: .leviticus, chapter: 4),
        verse: 1,
        sentence: "이 일 후에 내가 보니"
    )

    public init(
        title: BibleChapter,
        chapterTitle: String? = nil,
        verse: Int,
        verseEnd: Int? = nil,
        sentence: String
    ) {
        self.title = title
        self.chapterTitle = chapterTitle
        self.verse = verse
        self.verseEnd = verseEnd
        self.sentenceScript = sentence
    }

    /// 한 줄의 원시 문자열에서 소제목/절 번호/본문을 파싱하여 BibleVerse를 초기화.
    /// 참조(`장:절`, `장:절-절`)는 줄 맨 앞(앞에 `<소제목>` 이 있으면 그 뒤)에서만 읽는다 — 소제목 안 `(대상 1:5-23)` 을 절 번호로 잡지 않는다.
    /// 장 단위로 이어지는 줄까지 다루려면 `BibleChapterTextParser` 를 쓴다.
    /// - Parameters:
    ///   - title: 성경 책 정보를 담은 TitleVO.
    ///   - chapterTitle: 외부에서 전달받은 기본 소제목.
    ///   - sentence: 장/절/소제목 정보가 포함된 원본 문자열.
    public init(
        title: BibleChapter,
        chapterTitle: String? = nil,
        sentence: String
    ) {
        let line = BibleTextLine(sentence)
        self.title = title
        self.chapterTitle = line.heading ?? chapterTitle
        self.verse = line.verse ?? 0
        self.verseEnd = line.verseEnd
        self.sentenceScript = line.text
    }

}
