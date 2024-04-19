//
//  TitleVO.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import Common

import RealmSwift

public class TitleVO: Object {
    @Persisted(primaryKey: true) public var key: RealmStorageKeyType
    @Persisted public var id: String
    @Persisted public var title: BibleTitle
    @Persisted public var chapter: Int
    
    public static let initialState = TitleVO.init(title: .genesis, chapter: 49)
    
    public convenience init(title: BibleTitle, chapter: Int) {
        self.init()
        self.key = RealmStorageKeyType.bibleTitle
        self.id = "\(title.rawValue).\(chapter)"
        self.title = title
        self.chapter = chapter
    }
}

public enum BibleTitle: String, Equatable, CaseIterable, Identifiable, PersistableEnum {
    public var id: Self { self }
    case genesis = "1-01Genesis.txt"
    case exodus = "1-02Exodus.txt"
    case leviticus = "1-03Leviticus.txt"
    case numbers = "1-04Numbers.txt"
    case deuteronomy = "1-05Deuteronomy.txt"
    case joshua = "1-06Joshua.txt"
    case judges = "1-07Judges.txt"
    case ruth = "1-08Ruth.txt"
    case samuel1 = "1-09Samuel1.txt"
    case samuel2 = "1-10Samuel2.txt"
    case kings1 = "1-11Kings1.txt"
    case kings2 = "1-12Kings2.txt"
    case chronicles1 = "1-13Chronicles1.txt"
    case chronicles2 = "1-14Chronicles2.txt"
    case ezra = "1-15Ezra.txt"
    case nehemiah = "1-16Nehemiah.txt"
    case esther = "1-17Esther.txt"
    case job = "1-18Job.txt"
    case psalms = "1-19Psalms.txt"
    case proverbs = "1-20Proverbs.txt"
    case ecclesiasters = "1-21Ecclesiastes.txt"
    case songOfSongs = "1-22SongOfSongs.txt"
    case isaiah = "1-23Isaiah.txt"
    case jeremiah = "1-24Jeremiah.txt"
    case lamentations = "1-25Lamentations.txt"
    case ezekiel = "1-26Ezekiel.txt"
    case daniel = "1-27Daniel.txt"
    case hosea = "1-28Hosea.txt"
    case joel = "1-29Joel.txt"
    case amos = "1-30Amos.txt"
    case obadiah = "1-31Obadiah.txt"
    case jonah = "1-32Jonah.txt"
    case micah = "1-33Micah.txt"
    case nahum = "1-34Nahum.txt"
    case habakkuk = "1-35Habakkuk.txt"
    case zephaniah = "1-36Zephaniah.txt"
    case haggai = "1-37Haggai.txt"
    case zechariah = "1-38Zechariah.txt"
    case malachi = "1-39Malachi.txt"

    case matthew = "2-01Matthew.txt"
    case mark = "2-02Mark.txt"
    case luke = "2-03Luke.txt"
    case john = "2-04John.txt"
    case acts = "2-05Acts.txt"
    case romans = "2-06Romans.txt"
    case corinthians1 = "2-07Corinthians1.txt"
    case corinthians2 = "2-08Corinthians2.txt"
    case galatians = "2-09Galatians.txt"
    case ephesians = "2-10Ephesians.txt"
    case philippians = "2-11Philippians.txt"
    case colossians = "2-12Colossians.txt"
    case thessalonians1 = "2-13Thessalonians1.txt"
    case thessalonians2 = "2-14Thessalonians2.txt"
    case timothy1 = "2-15Timothy1.txt"
    case timothy2 = "2-16Timothy2.txt"
    case titus = "2-17Titus.txt"
    case philemon = "2-18Philemon.txt"
    case hebrews = "2-19Hebrews.txt"
    case james = "2-20James.txt"
    case peter1 = "2-21Peter1.txt"
    case peter2 = "2-22Peter2.txt"
    case john1 = "2-23John1.txt"
    case john2 = "2-24John2.txt"
    case john3 = "2-25John3.txt"
    case jude = "2-26Jude.txt"
    case revelation = "2-27Revelation.txt"

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

    public func koreanTitle() -> String {
        let titles: [Self: String] = [
            .genesis: "창세기",
            .exodus: "출애굽기",
            .leviticus: "레위기",
            .numbers: "민수기",
            .deuteronomy: "신명기",
            .joshua: "여호수아",
            .judges: "사사기",
            .ruth: "룻기",
            .samuel1: "사무엘상",
            .samuel2: "사무엘하",
            .kings1: "열왕기상",
            .kings2: "열왕기하",
            .chronicles1: "역대상",
            .chronicles2: "역대하",
            .ezra: "에스라",
            .nehemiah: "느헤미야",
            .esther: "에스더",
            .job: "욥기",
            .psalms: "시편",
            .proverbs: "잠언",
            .ecclesiasters: "전도서",
            .songOfSongs: "아가",
            .isaiah: "이사야",
            .jeremiah: "예레미야",
            .lamentations: "예레미야 애가",
            .ezekiel: "에스겔",
            .daniel: "다니엘",
            .hosea: "호세아",
            .joel: "요엘",
            .amos: "아모스",
            .obadiah: "오바댜",
            .jonah: "요나",
            .micah: "미가",
            .nahum: "나훔",
            .habakkuk: "하박국",
            .zephaniah: "스바냐",
            .haggai: "학개",
            .zechariah: "스가랴",
            .malachi: "말라기",
            .matthew: "마태복음",
            .mark: "마가복음",
            .luke: "누가복음",
            .john: "요한복음",
            .acts: "사도행전",
            .romans: "로마서",
            .corinthians1: "고린도전서",
            .corinthians2: "고린도후서",
            .galatians: "갈라디아서",
            .ephesians: "에베소서",
            .philippians: "빌립보서",
            .colossians: "골로새서",
            .thessalonians1: "데살로니가전서",
            .thessalonians2: "데살로니가후서",
            .timothy1: "디모데전서",
            .timothy2: "디모데후서",
            .titus: "디도서",
            .philemon: "빌레몬서",
            .hebrews: "히브리서",
            .james: "야고보서",
            .peter1: "베드로전서",
            .peter2: "베드로후서",
            .john1: "요한일서",
            .john2: "요한이서",
            .john3: "요한삼서",
            .jude: "유다서",
            .revelation: "요한계시록"
        ]
        return titles[self] ?? ""
    }
}
