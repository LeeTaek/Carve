//
//  TitleVO.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import Common

public struct TitleVO: Equatable {
    public var title: BibleTitle
    public var chapter: Int

    public static let initialState = Self.init(title: .genesis, chapter: 1)
    
    public init(title: BibleTitle, chapter: Int) {
        self.title = title
        self.chapter = chapter
    }
}

public enum BibleTitle: String, Equatable, CaseIterable {
    case genesis = "1-01창세기.txt"
    case exodus = "1-02출애굽기.txt"
    case leviticus = "1-03레위기.txt"
    case numbers = "1-04민수기.txt"
    case deuteronomy = "1-05신명기.txt"
    case joshua = "1-06여호수아.txt"
    case judges = "1-07사사기.txt"
    case ruth = "1-08룻기.txt"
    case samuel1 = "1-09사무엘상.txt"
    case samuel2 = "1-10사무엘하.txt"
    case kings1 = "1-11열왕기상.txt"
    case kings2 = "1-12열왕기하.txt"
    case chronicles1 = "1-13역대상.txt"
    case chronicles2 = "1-14역대하.txt"
    case ezra = "1-15에스라.txt"
    case nehemiah = "1-16느헤미야.txt"
    case esther = "1-17에스더.txt"
    case job = "1-18욥기.txt"
    case psalms = "1-19시편.txt"
    case proverbs = "1-20잠언.txt"
    case ecclesiasters = "1-21전도서.txt"
    case songOfSongs = "1-22아가.txt"
    case isaiah = "1-23이사야.txt"
    case jeremiah = "1-24예레미야.txt"
    case lamentations = "1-25예레미야애가.txt"
    case ezekiel = "1-26에스겔.txt"
    case daniel = "1-27다니엘.txt"
    case hosea = "1-28호세아.txt"
    case joel = "1-29요엘.txt"
    case amos = "1-30아모스.txt"
    case obadiah = "1-31오바댜.txt"
    case jonah = "1-32요나.txt"
    case micah = "1-33미가.txt"
    case nahum = "1-34나훔.txt"
    case habakkuk = "1-35하박국.txt"
    case zephaniah = "1-36스바냐.txt"
    case haggai = "1-37학개.txt"
    case zechariah = "1-38스가랴.txt"
    case malachi = "1-39말라기.txt"

    case matthew = "2-01마태복음.txt"
    case mark = "2-02마가복음.txt"
    case luke = "2-03누가복음.txt"
    case john = "2-04요한복음.txt"
    case acts = "2-05사도행전.txt"
    case romans = "2-06로마서.txt"
    case corinthians1 = "2-07고린도전서.txt"
    case corinthians2 = "2-08고린도후서.txt"
    case galatians = "2-09갈라디아서.txt"
    case ephesians = "2-10에베소서.txt"
    case philippians = "2-11빌립보서.txt"
    case colossians = "2-12골로새서.txt"
    case thessalonians1 = "2-13데살로니가전서.txt"
    case thessalonians2 = "2-14데살로니가후서.txt"
    case timothy1 = "2-15디모데전서.txt"
    case timothy2 = "2-16디모데후서.txt"
    case titus = "2-17디도서.txt"
    case philemon = "2-18빌레몬서.txt"
    case hebrews = "2-19히브리서.txt"
    case james = "2-20야고보서.txt"
    case peter1 = "2-21베드로전서.txt"
    case peter2 = "2-22베드로후서.txt"
    case john1 = "2-23요한일서.txt"
    case john2 = "2-24요한이서.txt"
    case john3 = "2-25요한삼서.txt"
    case jude = "2-26유다서.txt"
    case revelation = "2-27요한계시록.txt"

    public mutating func next() {
        let allCases = type(of: self).allCases
        let currentIndex = allCases.firstIndex(of: self)!

        if self != .revelation {
            self = allCases[currentIndex + 1]
        }
    }

    public mutating func before() {
        let allCases = type(of: self).allCases
        let currentIndex = allCases.firstIndex(of: self)!

        if self != .genesis {
            self = allCases[currentIndex - 1]
        }
    }

    public func rawTitle() -> String {
        guard let title = self.rawValue.components(separatedBy: ".").first else { return "" }
        return title[4..<title.count]
    }

    public var lastChapter: Int {
        switch self {
        case .genesis:
            return 50
        case .exodus:
            return 40
        case .leviticus:
            return 27
        case .numbers:
            return 36
        case .deuteronomy:
            return 34
        case .joshua:
            return 24
        case .judges:
            return 21
        case .ruth:
            return 4
        case .samuel1:
            return 31
        case .samuel2:
            return 24
        case .kings1:
            return 22
        case .kings2:
            return 25
        case .chronicles1:
            return 29
        case .chronicles2:
            return 36
        case .ezra:
            return 10
        case .nehemiah:
            return 13
        case .esther:
            return 10
        case .job:
            return 42
        case .psalms:
            return 150
        case .proverbs:
            return 31
        case .ecclesiasters:
            return 12
        case .songOfSongs:
            return 8
        case .isaiah:
            return 66
        case .jeremiah:
            return 52
        case .lamentations:
            return 5
        case .ezekiel:
            return 48
        case .daniel:
            return 12
        case .hosea:
            return 14
        case .joel:
            return 3
        case .amos:
            return 9
        case .obadiah:
            return 1
        case .jonah:
            return 4
        case .micah:
            return 7
        case .nahum:
            return 3
        case .habakkuk:
            return 3
        case .zephaniah:
            return 3
        case .haggai:
            return 2
        case .zechariah:
            return 14
        case .malachi:
            return 4

        case .matthew:
            return 28
        case .mark:
            return 16
        case .luke:
            return 24
        case .john:
            return 21
        case .acts:
            return 28
        case .romans:
            return 16
        case .corinthians1:
            return 16
        case .corinthians2:
            return 13
        case .galatians:
            return 6
        case .ephesians:
            return 6
        case .philippians:
            return 4
        case .colossians:
            return 4
        case .thessalonians1:
            return 5
        case .thessalonians2:
            return 3
        case .timothy1:
            return 6
        case .timothy2:
            return 4
        case .titus:
            return 3
        case .philemon:
            return 1
        case .hebrews:
            return 13
        case .james:
            return 5
        case .peter1:
            return 5
        case .peter2:
            return 3
        case .john1:
            return 5
        case .john2:
            return 1
        case .john3:
            return 1
        case .jude:
            return 1
        case .revelation:
            return 22
        }
    }
    
    public static func getTitle(_ raw: String) -> Self {
        for title in Self.allCases where title.rawValue.contains(raw) {
            return title
        }
        return .genesis
    }
}
