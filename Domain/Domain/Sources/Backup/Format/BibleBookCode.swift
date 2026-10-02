//
//  BibleBookCode.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// USFM 권 코드 — `BibleTitle` 66권과 1:1, 양방향 (설계 §2-6, 결정 9).
///
/// 백업 파일은 권을 앱 안 파일 이름(`BibleTitle.rawValue`)이 아니라 이 코드로 식별한다 — 번역본 · 앱 버전과 무관한 표준 이름이다.
/// 두 방향 모두 `switch` 로 적어 컴파일러가 66권 전수를 확인한다. 원시값이 코드(`"GEN"` …)다.
public enum BibleBookCode: String, CaseIterable, Codable, Sendable {
    case genesis = "GEN"
    case exodus = "EXO"
    case leviticus = "LEV"
    case numbers = "NUM"
    case deuteronomy = "DEU"
    case joshua = "JOS"
    case judges = "JDG"
    case ruth = "RUT"
    case samuel1 = "1SA"
    case samuel2 = "2SA"
    case kings1 = "1KI"
    case kings2 = "2KI"
    case chronicles1 = "1CH"
    case chronicles2 = "2CH"
    case ezra = "EZR"
    case nehemiah = "NEH"
    case esther = "EST"
    case job = "JOB"
    case psalms = "PSA"
    case proverbs = "PRO"
    case ecclesiastes = "ECC"
    case songOfSongs = "SNG"
    case isaiah = "ISA"
    case jeremiah = "JER"
    case lamentations = "LAM"
    case ezekiel = "EZK"
    case daniel = "DAN"
    case hosea = "HOS"
    case joel = "JOL"
    case amos = "AMO"
    case obadiah = "OBA"
    case jonah = "JON"
    case micah = "MIC"
    case nahum = "NAM"
    case habakkuk = "HAB"
    case zephaniah = "ZEP"
    case haggai = "HAG"
    case zechariah = "ZEC"
    case malachi = "MAL"

    case matthew = "MAT"
    case mark = "MRK"
    case luke = "LUK"
    case john = "JHN"
    case acts = "ACT"
    case romans = "ROM"
    case corinthians1 = "1CO"
    case corinthians2 = "2CO"
    case galatians = "GAL"
    case ephesians = "EPH"
    case philippians = "PHP"
    case colossians = "COL"
    case thessalonians1 = "1TH"
    case thessalonians2 = "2TH"
    case timothy1 = "1TI"
    case timothy2 = "2TI"
    case titus = "TIT"
    case philemon = "PHM"
    case hebrews = "HEB"
    case james = "JAS"
    case peter1 = "1PE"
    case peter2 = "2PE"
    case john1 = "1JN"
    case john2 = "2JN"
    case john3 = "3JN"
    case jude = "JUD"
    case revelation = "REV"

    /// 권의 코드.
    public init(title: BibleTitle) {
        self = Self.code(for: title)
    }

    /// 코드가 가리키는 권.
    public var title: BibleTitle {
        switch self {
        case .genesis: .genesis
        case .exodus: .exodus
        case .leviticus: .leviticus
        case .numbers: .numbers
        case .deuteronomy: .deuteronomy
        case .joshua: .joshua
        case .judges: .judges
        case .ruth: .ruth
        case .samuel1: .samuel1
        case .samuel2: .samuel2
        case .kings1: .kings1
        case .kings2: .kings2
        case .chronicles1: .chronicles1
        case .chronicles2: .chronicles2
        case .ezra: .ezra
        case .nehemiah: .nehemiah
        case .esther: .esther
        case .job: .job
        case .psalms: .psalms
        case .proverbs: .proverbs
        case .ecclesiastes: .ecclesiasters
        case .songOfSongs: .songOfSongs
        case .isaiah: .isaiah
        case .jeremiah: .jeremiah
        case .lamentations: .lamentations
        case .ezekiel: .ezekiel
        case .daniel: .daniel
        case .hosea: .hosea
        case .joel: .joel
        case .amos: .amos
        case .obadiah: .obadiah
        case .jonah: .jonah
        case .micah: .micah
        case .nahum: .nahum
        case .habakkuk: .habakkuk
        case .zephaniah: .zephaniah
        case .haggai: .haggai
        case .zechariah: .zechariah
        case .malachi: .malachi
        case .matthew: .matthew
        case .mark: .mark
        case .luke: .luke
        case .john: .john
        case .acts: .acts
        case .romans: .romans
        case .corinthians1: .corinthians1
        case .corinthians2: .corinthians2
        case .galatians: .galatians
        case .ephesians: .ephesians
        case .philippians: .philippians
        case .colossians: .colossians
        case .thessalonians1: .thessalonians1
        case .thessalonians2: .thessalonians2
        case .timothy1: .timothy1
        case .timothy2: .timothy2
        case .titus: .titus
        case .philemon: .philemon
        case .hebrews: .hebrews
        case .james: .james
        case .peter1: .peter1
        case .peter2: .peter2
        case .john1: .john1
        case .john2: .john2
        case .john3: .john3
        case .jude: .jude
        case .revelation: .revelation
        }
    }

    /// 권 → 코드. `title` 의 역방향이다(시험이 66권 왕복을 확인한다).
    private static func code(for title: BibleTitle) -> BibleBookCode {
        switch title {
        case .genesis: .genesis
        case .exodus: .exodus
        case .leviticus: .leviticus
        case .numbers: .numbers
        case .deuteronomy: .deuteronomy
        case .joshua: .joshua
        case .judges: .judges
        case .ruth: .ruth
        case .samuel1: .samuel1
        case .samuel2: .samuel2
        case .kings1: .kings1
        case .kings2: .kings2
        case .chronicles1: .chronicles1
        case .chronicles2: .chronicles2
        case .ezra: .ezra
        case .nehemiah: .nehemiah
        case .esther: .esther
        case .job: .job
        case .psalms: .psalms
        case .proverbs: .proverbs
        case .ecclesiasters: .ecclesiastes
        case .songOfSongs: .songOfSongs
        case .isaiah: .isaiah
        case .jeremiah: .jeremiah
        case .lamentations: .lamentations
        case .ezekiel: .ezekiel
        case .daniel: .daniel
        case .hosea: .hosea
        case .joel: .joel
        case .amos: .amos
        case .obadiah: .obadiah
        case .jonah: .jonah
        case .micah: .micah
        case .nahum: .nahum
        case .habakkuk: .habakkuk
        case .zephaniah: .zephaniah
        case .haggai: .haggai
        case .zechariah: .zechariah
        case .malachi: .malachi
        case .matthew: .matthew
        case .mark: .mark
        case .luke: .luke
        case .john: .john
        case .acts: .acts
        case .romans: .romans
        case .corinthians1: .corinthians1
        case .corinthians2: .corinthians2
        case .galatians: .galatians
        case .ephesians: .ephesians
        case .philippians: .philippians
        case .colossians: .colossians
        case .thessalonians1: .thessalonians1
        case .thessalonians2: .thessalonians2
        case .timothy1: .timothy1
        case .timothy2: .timothy2
        case .titus: .titus
        case .philemon: .philemon
        case .hebrews: .hebrews
        case .james: .james
        case .peter1: .peter1
        case .peter2: .peter2
        case .john1: .john1
        case .john2: .john2
        case .john3: .john3
        case .jude: .jude
        case .revelation: .revelation
        }
    }
}
