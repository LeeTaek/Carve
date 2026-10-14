//
//  BibleTextLine.swift
//  Domain
//
//  Created by Claude on 9/30/26.
//

import Foundation

/// 개역개정 본문 파일(CR 로 나뉜 줄) 한 줄을 장 · 절 · 소제목 · 본문으로 나눈 결과.
///
/// 파일의 줄은 다음 형태가 섞여 있다(2026-09-30 66권 전수 확인).
/// - `장:절 본문`, `장:절 <소제목> 본문` — 보통의 절.
/// - `장:절-절 본문` — 두 절 이상이 한 줄로 합쳐진 절(신 6:18-19 등 11곳).
/// - `장:본문`, `장:본문 <소제목> 본문` — 절 번호 없이 앞 절에 이어지는 줄. 절 중간에 소제목이 끼어 둘로 나뉜 절의 뒷부분이다(창 35:22 등 43곳).
///   시편의 권 표시(`1:제일권` 등)도 이 형태다.
/// - 소제목 안에는 `(대상 1:5-23)` 같은 참조가 있다. 참조는 **줄 맨 앞에서만** 읽어야 소제목 안 숫자를 절 번호로 잡지 않는다.
struct BibleTextLine: Equatable {
    /// 줄 앞 `장:` 의 장 번호. 접두어가 없으면 nil.
    var chapter: Int?
    /// 절 번호. `장:본문` 처럼 절 번호가 없으면 nil.
    var verse: Int?
    /// 합쳐진 절의 마지막 절 번호(`18-19` 의 19).
    var verseEnd: Int?
    /// `<소제목>` 의 안쪽 문자열.
    var heading: String?
    /// 참조와 소제목을 뺀 본문. 안쪽 줄바꿈은 유지한다.
    var text: String

    init(chapter: Int? = nil, verse: Int? = nil, verseEnd: Int? = nil, heading: String? = nil, text: String) {
        self.chapter = chapter
        self.verse = verse
        self.verseEnd = verseEnd
        self.heading = heading
        self.text = text
    }

    /// 한 줄을 나눈다. 소제목은 참조 앞(`<소제목> 3:16 …`)에 와도 읽는다.
    init(_ line: String) {
        var rest = Substring(line).trimmingLeadingWhitespace()
        var heading: String?

        if rest.first == "<", let extracted = Self.extractHeading(from: rest) {
            heading = extracted.heading
            rest = Substring(extracted.text)
        }

        var chapter: Int?
        var verse: Int?
        var verseEnd: Int?
        if let reference = Self.reference(in: rest) {
            chapter = reference.chapter
            verse = reference.verse
            verseEnd = reference.verseEnd
            rest = reference.rest
        }

        if heading == nil, let extracted = Self.extractHeading(from: rest) {
            heading = extracted.heading
            rest = Substring(extracted.text)
        }

        self.init(
            chapter: chapter,
            verse: verse,
            verseEnd: verseEnd,
            heading: heading,
            text: rest.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// 줄 맨 앞 `장:` 의 장 번호만 읽는다.
    static func leadingChapter(of line: String) -> Int? {
        let digits = line.prefix(while: \.isASCIIDigit)
        guard digits.endIndex < line.endIndex, line[digits.endIndex] == ":" else { return nil }
        return Int(digits)
    }

    /// 줄 맨 앞의 `장:`, `장:절`, `장:절-절` 과 그 뒤 공백을 읽는다.
    private static func reference(in line: Substring) -> Reference? {
        let chapterDigits = line.prefix(while: \.isASCIIDigit)
        guard let chapter = Int(chapterDigits), chapterDigits.endIndex < line.endIndex,
              line[chapterDigits.endIndex] == ":" else {
            return nil
        }
        var rest = line[line.index(after: chapterDigits.endIndex)...]

        let verseDigits = rest.prefix(while: \.isASCIIDigit)
        let verse = Int(verseDigits)
        var verseEnd: Int?
        rest = rest[verseDigits.endIndex...]
        if verse != nil, rest.first == "-" {
            let endDigits = rest.dropFirst().prefix(while: \.isASCIIDigit)
            if let end = Int(endDigits) {
                verseEnd = end
                rest = rest[endDigits.endIndex...]
            }
        }
        return Reference(chapter: chapter, verse: verse, verseEnd: verseEnd, rest: rest.trimmingLeadingWhitespace())
    }

    private struct Reference {
        var chapter: Int
        var verse: Int?
        var verseEnd: Int?
        /// 참조와 그 뒤 공백을 뺀 나머지.
        var rest: Substring
    }

    /// 처음 나오는 `<…>` 를 소제목으로 떼어 내고, 양옆 본문을 공백 하나로 잇는다.
    private static func extractHeading(from text: Substring) -> (heading: String, text: String)? {
        guard let open = text.firstIndex(of: "<"),
              let close = text[open...].firstIndex(of: ">") else {
            return nil
        }
        let heading = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        let before = text[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        let after = text[text.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = [before, after].filter { !$0.isEmpty }.joined(separator: " ")
        return (heading, joined)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

private extension Substring {
    func trimmingLeadingWhitespace() -> Substring {
        drop(while: { $0.isWhitespace || $0.isNewline })
    }
}
