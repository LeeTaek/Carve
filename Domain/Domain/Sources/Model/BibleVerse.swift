//
//  BibleVerse.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//


import Foundation
import RegexBuilder

/// 성경 제목/장, (선택적인) 소제목, 절 번호, 본문 텍스트 등 본문 데이터 모델.
public struct BibleVerse: Equatable, Sendable {
    /// 성경 이름/장.
    public var title: BibleChapter
    /// 장 앞에 붙는 소제목(예: "아브라함의 믿음")을 저장하는 필드.
    public var chapterTitle: String?
    /// 절(verse)
    public var verse: Int
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
        sentence: String
    ) {
        self.title = title
        self.chapterTitle = chapterTitle
        self.verse = verse
        self.sentenceScript = sentence
    }

    /// 한 줄의 원시 문자열에서 장 제목/절 번호/본문을 파싱하여 SentenceVO를 초기화.
    /// 문자열에서 "숫자:숫자" 패턴과 "<소제목>" 패턴을 인식하여 분리.
    /// - Parameters:
    ///   - title: 성경 책 정보를 담은 TitleVO.
    ///   - chapterTitle: 외부에서 전달받은 기본 소제목.
    ///   - sentence: 장/절/소제목 정보가 포함된 원본 문자열.
    public init(
        title: BibleChapter,
        chapterTitle: String? = nil,
        sentence: String
    ) {
        self.title = title
        var chapterTitle: String?
        var chapter: Int?
        var sentenceScript: String = sentence
        
        // <소제목> 형식의 문자열을 찾기 위한 정규식.
        let titlePattern = Regex {
            "<"
            Capture {
                ZeroOrMore(.any, .reluctant)
            }
            ">"
        }
        
        // "장:절" 형식에서 절 번호를 추출하기 위한 정규식. (예: 3:16 → 16)
        let chapterPattern = Regex {
            OneOrMore(.digit)
            ":"
            Capture {
                OneOrMore(.digit)
            }
        }
        
        // 먼저 "장:절" 패턴을 찾아 절 번호를 추출하고, 해당 부분을 문자열에서 제거.
        if let match = try? chapterPattern.firstMatch(in: sentenceScript) {
            let (_, chapterNum) = match.output
            chapter = Int(chapterNum)
            sentenceScript.removeSubrange(match.range)
            sentenceScript = sentenceScript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 이후 <소제목> 패턴을 찾아 소제목을 추출하고, 해당 부분을 문자열에서 제거.
        if let match = try? titlePattern.firstMatch(in: sentenceScript) {
            let (_, chapterTitleString) = match.output
            chapterTitle = String(chapterTitleString)
            sentenceScript.removeSubrange(match.range)
            sentenceScript = sentenceScript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
       
        self.chapterTitle = chapterTitle
        self.verse = chapter ?? 0
        self.sentenceScript = sentenceScript
    }

}
