//
//  BibleChapter.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import SwiftData

/// 성경의 한 위치(번역본 + 책 + 장) 모델.
///
/// 지금 번역본은 `@Shared(.appStorage("title"))` 에 저장된 장의 `translation` 이다 — 별도 저장 키는 없다.
/// 장을 여는 경로 · 즐겨찾기 · 위젯 · 차트 · 초안은 번역본을 따로 받지 않고 장과 함께 나른다.
public struct BibleChapter: Sendable, Codable, Hashable {
    /// 같은 번역본의 같은 권 · 장일 때만 같다.
    public static func == (lhs: BibleChapter, rhs: BibleChapter) -> Bool {
        (lhs.title == rhs.title) && (lhs.chapter == rhs.chapter) && (lhs.translation == rhs.translation)
    }

    /// 성경 책(창세기, 출애굽기 등).
    public var title: BibleTitle
    /// 장(chapter) 번호.
    public var chapter: Int
    /// 번역본. 옛 JSON(키 없음)은 개역개정이다.
    public var translation: Translation

    /// 개역개정 창세기 1장. 저장값이 없을 때의 옛 기본값이다 — 처음 설치 기본값은 `initial(preferredLanguages:)` 다.
    public static let initialState = BibleChapter.init(title: .genesis, chapter: 1)

    public init(title: BibleTitle, chapter: Int, translation: Translation = .NKRV) {
        self.title = title
        self.chapter = chapter
        self.translation = translation
    }

    /// 역할: 처음 설치했을 때 열 장을 정한다(영어 현지화 결정 4).
    /// 입력 · 출력: 기기 선호 언어 목록(`Locale.preferredLanguages`) → 첫 언어가 `"ko"` 로 시작하면 개역개정 창세기 1장,
    ///   아니면(빈 목록 포함) BSB 창세기 1장. 저장값이 있으면 호출부가 그 값을 그대로 쓴다.
    /// 부작용: 없음.
    public static func initial(preferredLanguages: [String]) -> BibleChapter {
        let isKorean = preferredLanguages.first?.lowercased().hasPrefix("ko") ?? false
        return BibleChapter(title: .genesis, chapter: 1, translation: isKorean ? .NKRV : .BSB)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(chapter)
        hasher.combine(translation)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case chapter
        case translation
    }

    /// `translation` 키가 없으면 개역개정이다 — 옛 `@Shared("title")` JSON · `-UITestChapter` JSON(`{"title":"1-19Psalms.txt","chapter":119}`)을 그대로 읽는다.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try container.decode(BibleTitle.self, forKey: .title),
            chapter: try container.decode(Int.self, forKey: .chapter),
            translation: try container.decodeIfPresent(Translation.self, forKey: .translation) ?? .NKRV
        )
    }

    /// 세 키를 모두 쓴다. 구버전은 모르는 `translation` 키를 무시하고 읽는다(합성 Decodable).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(chapter, forKey: .chapter)
        try container.encode(translation, forKey: .translation)
    }
}

/// 성경 66권(구약/신약).
public enum BibleTitle: String, CaseIterable, Identifiable, Codable, Sendable {
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

    /// 현재 책 기준으로 다음 책을 반환.
    /// - 마지막 책(요한계시록)일 경우 다시 창세기로 순환.
    public func next() -> Self {
        let allCases = type(of: self).allCases
        let currentIndex = allCases.firstIndex(of: self)!

        if self != .revelation {
            return allCases[currentIndex + 1]
        } else {
            return .genesis
        }
    }

    /// 현재 책 기준으로 이전 책을 반환합니다.
    /// - 첫 책(창세기)일 경우 요한계시록으로 순환.
    public func before() -> Self {
        let allCases = type(of: self).allCases
        let currentIndex = allCases.firstIndex(of: self)!

        if self != .genesis {
            return allCases[currentIndex - 1]
        } else {
            return .revelation
        }
    }

    /// 각 성경 책이 갖는 마지막 장.
    /// - 예: 창세기 50장, 마태복음 28장 등.
    public var lastChapter: Int {
        switch self {
        case .genesis: return 50
        case .exodus: return 40
        case .leviticus: return 27
        case .numbers: return 36
        case .deuteronomy: return 34
        case .joshua: return 24
        case .judges: return 21
        case .ruth: return 4
        case .samuel1: return 31
        case .samuel2: return 24
        case .kings1: return 22
        case .kings2: return 25
        case .chronicles1: return 29
        case .chronicles2: return 36
        case .ezra: return 10
        case .nehemiah: return 13
        case .esther: return 10
        case .job: return 42
        case .psalms: return 150
        case .proverbs: return 31
        case .ecclesiasters: return 12
        case .songOfSongs: return 8
        case .isaiah: return 66
        case .jeremiah: return 52
        case .lamentations: return 5
        case .ezekiel: return 48
        case .daniel: return 12
        case .hosea: return 14
        case .joel: return 3
        case .amos: return 9
        case .obadiah: return 1
        case .jonah: return 4
        case .micah: return 7
        case .nahum: return 3
        case .habakkuk: return 3
        case .zephaniah: return 3
        case .haggai: return 2
        case .zechariah: return 14
        case .malachi: return 4

        case .matthew: return 28
        case .mark: return 16
        case .luke: return 24
        case .john: return 21
        case .acts: return 28
        case .romans: return 16
        case .corinthians1: return 16
        case .corinthians2: return 13
        case .galatians: return 6
        case .ephesians: return 6
        case .philippians: return 4
        case .colossians: return 4
        case .thessalonians1: return 5
        case .thessalonians2: return 3
        case .timothy1: return 6
        case .timothy2: return 4
        case .titus: return 3
        case .philemon: return 1
        case .hebrews: return 13
        case .james: return 5
        case .peter1: return 5
        case .peter2: return 3
        case .john1: return 5
        case .john2: return 1
        case .john3: return 1
        case .jude: return 1
        case .revelation: return 22
        }
    }

    /// 텍스트 리소스 파일명 일부 문자열로부터 대응되는 BibleTitle.
    /// - Parameter raw: 파일명에 포함된 문자열.
    /// - Returns: 일치하는 책이 없을 경우 기본값으로 창세기를 반환.
    public static func getTitle(_ raw: String) -> Self {
        for title in Self.allCases where title.rawValue.contains(raw) {
            return title
        }
        return .genesis
    }

    /// 각 성경 책의 한글 제목을 반환. (예: .genesis → "창세기")
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
    
    /// 현재 책이 구약(Old Testament)에 속하는지 여부.
    /// allCases 배열에서의 인덱스를 기준으로 39권 이전이면 구약으로 간주.
    public var isOldtestment: Bool {
        if let index = Self.allCases.firstIndex(of: self) {
            return index < 39
        }
        return false
    }
}

// MARK: - 권 이름

extension BibleTitle {
    /// 권 이름(앱 언어). ko 「창세기」 · en 「Genesis」. 권 목록 · 참조(`BibleReference`)에 쓴다.
    /// 번역본이 아니라 앱(기기) 언어를 따른다 — 한국어 기기는 KJV 를 봐도 「창세기」 다.
    public var localizedName: String { localizedName(locale: nil) }

    /// 권 이름을 한 언어로 꺼낸다. 카탈로그 키는 `koreanTitle()` 의 한국어 원문이다.
    /// - Parameter locale: 언어를 정할 로케일. nil 이면 앱(기기) 언어다.
    public func localizedName(locale: Locale?) -> String {
        switch self {
        case .genesis: DomainCatalog.string("창세기", locale: locale)
        case .exodus: DomainCatalog.string("출애굽기", locale: locale)
        case .leviticus: DomainCatalog.string("레위기", locale: locale)
        case .numbers: DomainCatalog.string("민수기", locale: locale)
        case .deuteronomy: DomainCatalog.string("신명기", locale: locale)
        case .joshua: DomainCatalog.string("여호수아", locale: locale)
        case .judges: DomainCatalog.string("사사기", locale: locale)
        case .ruth: DomainCatalog.string("룻기", locale: locale)
        case .samuel1: DomainCatalog.string("사무엘상", locale: locale)
        case .samuel2: DomainCatalog.string("사무엘하", locale: locale)
        case .kings1: DomainCatalog.string("열왕기상", locale: locale)
        case .kings2: DomainCatalog.string("열왕기하", locale: locale)
        case .chronicles1: DomainCatalog.string("역대상", locale: locale)
        case .chronicles2: DomainCatalog.string("역대하", locale: locale)
        case .ezra: DomainCatalog.string("에스라", locale: locale)
        case .nehemiah: DomainCatalog.string("느헤미야", locale: locale)
        case .esther: DomainCatalog.string("에스더", locale: locale)
        case .job: DomainCatalog.string("욥기", locale: locale)
        case .psalms: DomainCatalog.string("시편", locale: locale)
        case .proverbs: DomainCatalog.string("잠언", locale: locale)
        case .ecclesiasters: DomainCatalog.string("전도서", locale: locale)
        case .songOfSongs: DomainCatalog.string("아가", locale: locale)
        case .isaiah: DomainCatalog.string("이사야", locale: locale)
        case .jeremiah: DomainCatalog.string("예레미야", locale: locale)
        case .lamentations: DomainCatalog.string("예레미야 애가", locale: locale)
        case .ezekiel: DomainCatalog.string("에스겔", locale: locale)
        case .daniel: DomainCatalog.string("다니엘", locale: locale)
        case .hosea: DomainCatalog.string("호세아", locale: locale)
        case .joel: DomainCatalog.string("요엘", locale: locale)
        case .amos: DomainCatalog.string("아모스", locale: locale)
        case .obadiah: DomainCatalog.string("오바댜", locale: locale)
        case .jonah: DomainCatalog.string("요나", locale: locale)
        case .micah: DomainCatalog.string("미가", locale: locale)
        case .nahum: DomainCatalog.string("나훔", locale: locale)
        case .habakkuk: DomainCatalog.string("하박국", locale: locale)
        case .zephaniah: DomainCatalog.string("스바냐", locale: locale)
        case .haggai: DomainCatalog.string("학개", locale: locale)
        case .zechariah: DomainCatalog.string("스가랴", locale: locale)
        case .malachi: DomainCatalog.string("말라기", locale: locale)
        case .matthew: DomainCatalog.string("마태복음", locale: locale)
        case .mark: DomainCatalog.string("마가복음", locale: locale)
        case .luke: DomainCatalog.string("누가복음", locale: locale)
        case .john: DomainCatalog.string("요한복음", locale: locale)
        case .acts: DomainCatalog.string("사도행전", locale: locale)
        case .romans: DomainCatalog.string("로마서", locale: locale)
        case .corinthians1: DomainCatalog.string("고린도전서", locale: locale)
        case .corinthians2: DomainCatalog.string("고린도후서", locale: locale)
        case .galatians: DomainCatalog.string("갈라디아서", locale: locale)
        case .ephesians: DomainCatalog.string("에베소서", locale: locale)
        case .philippians: DomainCatalog.string("빌립보서", locale: locale)
        case .colossians: DomainCatalog.string("골로새서", locale: locale)
        case .thessalonians1: DomainCatalog.string("데살로니가전서", locale: locale)
        case .thessalonians2: DomainCatalog.string("데살로니가후서", locale: locale)
        case .timothy1: DomainCatalog.string("디모데전서", locale: locale)
        case .timothy2: DomainCatalog.string("디모데후서", locale: locale)
        case .titus: DomainCatalog.string("디도서", locale: locale)
        case .philemon: DomainCatalog.string("빌레몬서", locale: locale)
        case .hebrews: DomainCatalog.string("히브리서", locale: locale)
        case .james: DomainCatalog.string("야고보서", locale: locale)
        case .peter1: DomainCatalog.string("베드로전서", locale: locale)
        case .peter2: DomainCatalog.string("베드로후서", locale: locale)
        case .john1: DomainCatalog.string("요한일서", locale: locale)
        case .john2: DomainCatalog.string("요한이서", locale: locale)
        case .john3: DomainCatalog.string("요한삼서", locale: locale)
        case .jude: DomainCatalog.string("유다서", locale: locale)
        case .revelation: DomainCatalog.string("요한계시록", locale: locale)
        }
    }

    /// 권 검색용 고정 영문 이름(Genesis … 1 Samuel … Song of Solomon … Revelation). 앱 언어와 상관없이 같다.
    public var englishName: String {
        switch self {
        case .genesis: "Genesis"
        case .exodus: "Exodus"
        case .leviticus: "Leviticus"
        case .numbers: "Numbers"
        case .deuteronomy: "Deuteronomy"
        case .joshua: "Joshua"
        case .judges: "Judges"
        case .ruth: "Ruth"
        case .samuel1: "1 Samuel"
        case .samuel2: "2 Samuel"
        case .kings1: "1 Kings"
        case .kings2: "2 Kings"
        case .chronicles1: "1 Chronicles"
        case .chronicles2: "2 Chronicles"
        case .ezra: "Ezra"
        case .nehemiah: "Nehemiah"
        case .esther: "Esther"
        case .job: "Job"
        case .psalms: "Psalms"
        case .proverbs: "Proverbs"
        case .ecclesiasters: "Ecclesiastes"
        case .songOfSongs: "Song of Solomon"
        case .isaiah: "Isaiah"
        case .jeremiah: "Jeremiah"
        case .lamentations: "Lamentations"
        case .ezekiel: "Ezekiel"
        case .daniel: "Daniel"
        case .hosea: "Hosea"
        case .joel: "Joel"
        case .amos: "Amos"
        case .obadiah: "Obadiah"
        case .jonah: "Jonah"
        case .micah: "Micah"
        case .nahum: "Nahum"
        case .habakkuk: "Habakkuk"
        case .zephaniah: "Zephaniah"
        case .haggai: "Haggai"
        case .zechariah: "Zechariah"
        case .malachi: "Malachi"
        case .matthew: "Matthew"
        case .mark: "Mark"
        case .luke: "Luke"
        case .john: "John"
        case .acts: "Acts"
        case .romans: "Romans"
        case .corinthians1: "1 Corinthians"
        case .corinthians2: "2 Corinthians"
        case .galatians: "Galatians"
        case .ephesians: "Ephesians"
        case .philippians: "Philippians"
        case .colossians: "Colossians"
        case .thessalonians1: "1 Thessalonians"
        case .thessalonians2: "2 Thessalonians"
        case .timothy1: "1 Timothy"
        case .timothy2: "2 Timothy"
        case .titus: "Titus"
        case .philemon: "Philemon"
        case .hebrews: "Hebrews"
        case .james: "James"
        case .peter1: "1 Peter"
        case .peter2: "2 Peter"
        case .john1: "1 John"
        case .john2: "2 John"
        case .john3: "3 John"
        case .jude: "Jude"
        case .revelation: "Revelation"
        }
    }
}
