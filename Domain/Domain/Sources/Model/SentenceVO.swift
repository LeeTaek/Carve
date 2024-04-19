//
//  SentenceVO.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

public struct SentenceVO: Equatable {
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

        if let index = sentence.firstIndex(of: " "),
           let chapterString = sentence.prefix(upTo: index).components(separatedBy: ":").last {

            self.section = Int(chapterString)!
            let restSentence = sentence.suffix(from: sentence.index(after: index))

            if let chapterTitleRange = restSentence.range(of: #"<(.*?)>"#, options: .regularExpression) {
                self.chapterTitle = String(restSentence[restSentence.startIndex..<chapterTitleRange.lowerBound])
                self.sentenceScript = String(restSentence[chapterTitleRange.upperBound...])
            } else {
                self.chapterTitle = nil
                self.sentenceScript = String(restSentence)
            }
        } else {
            self.chapterTitle = nil
            self.section = 0
            self.sentenceScript = "fetch error"
        }
    }

}
