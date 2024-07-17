//
//  SentenceVO.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import RegexBuilder

public struct SentenceVO: Equatable, Sendable {
    public var title: TitleVO
    public var chapterTitle: String?
    public var section: Int
    public var sentenceScript: String

    public static let initialState = Self(
        title: TitleVO(title: .leviticus, chapter: 4),
        section: 1,
        sentence: "이 일 후에 내가 보니"
    )

    public init(title: TitleVO,
                chapterTitle: String? = nil,
                section: Int,
                sentence: String) {
        self.title = title
        self.chapterTitle = chapterTitle
        self.section = section
        self.sentenceScript = sentence
    }

    public init(title: TitleVO,
                chapterTitle: String? = nil,
                sentence: String) {
        self.title = title
        var chapterTitle: String?
        var chapter: Int?
        var sentenceScript: String = sentence
        
        let titlePattern = Regex {
            "<"
            Capture {
                ZeroOrMore(.any, .reluctant)
            }
            ">"
        }
        let chapterPattern = Regex {
            OneOrMore(.digit)
            ":"
            Capture {
                OneOrMore(.digit)
            }
        }
        if let match = try? chapterPattern.firstMatch(in: sentenceScript) {
            let (_, chapterNum) = match.output
            chapter = Int(chapterNum)
            sentenceScript.removeSubrange(match.range)
            sentenceScript = sentenceScript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let match = try? titlePattern.firstMatch(in: sentenceScript) {
            let (_, chapterTitleString) = match.output
            chapterTitle = String(chapterTitleString)
            sentenceScript.removeSubrange(match.range)
            sentenceScript = sentenceScript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
       
        self.chapterTitle = chapterTitle
        self.section = chapter ?? 0
        self.sentenceScript = sentenceScript
    }
    

}
