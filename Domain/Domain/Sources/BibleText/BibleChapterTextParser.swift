//
//  BibleChapterTextParser.swift
//  Domain
//
//  Created by Claude on 9/30/26.
//

import Foundation

/// 한 권의 본문 파일에서 한 장의 절 목록을 만든다.
///
/// 필사는 (책, 장, **절 번호**) 로 저장되므로 절 번호는 성경 절과 같아야 하고 한 장 안에서 겹치면 안 된다.
/// 절 번호 없이 이어지는 줄(`장:본문`)은 따로 행을 만들지 않고 앞 절 본문에 잇는다. 그 줄에 낀 소제목은 다음 절 위로 옮긴다.
/// 장 첫 절 앞에 오는 이어지는 줄(시편의 `1:제일권` 등)은 첫 절의 소제목이 된다.
public enum BibleChapterTextParser {
    /// 시편 권 표시를 소제목 표기로 바꾼다.
    static let psalmBookLabels = [
        "제일권": "제1권",
        "제이권": "제2권",
        "제삼권": "제3권",
        "제사권": "제4권",
        "제오권": "제5권"
    ]

    /// - Parameters:
    ///   - text: 파일 전체. 줄은 CR 로 나뉘고, 절 안 줄바꿈은 LF 다.
    ///   - chapter: 뽑을 장.
    public static func verses(in text: String, chapter: BibleChapter) -> [BibleVerse] {
        var verses: [BibleVerse] = []
        var pendingHeadings: [String] = []
        var currentChapter: Int?

        for rawLine in text.components(separatedBy: "\r") {
            // 다른 장의 줄은 장 번호만 읽고 넘긴다 — 시편은 2천 줄이 넘는다.
            if let lineChapter = BibleTextLine.leadingChapter(of: rawLine), lineChapter != chapter.chapter {
                currentChapter = lineChapter
                continue
            }
            let line = BibleTextLine(rawLine)
            guard line.chapter != nil || !line.text.isEmpty || line.heading != nil else { continue }
            // 장 접두어가 없는 줄은 바로 앞 줄의 장에 속한다.
            currentChapter = line.chapter ?? currentChapter
            guard currentChapter == chapter.chapter else { continue }

            if let verse = line.verse {
                let headings = pendingHeadings + [line.heading].compactMap { $0 }
                verses.append(BibleVerse(
                    title: chapter,
                    chapterTitle: headings.isEmpty ? nil : headings.joined(separator: "\n"),
                    verse: verse,
                    verseEnd: line.verseEnd,
                    sentence: line.text
                ))
                pendingHeadings = []
            } else if verses.isEmpty {
                // 첫 절 앞: 권 표시 · 소제목은 첫 절 위로.
                if !line.text.isEmpty {
                    pendingHeadings.append(psalmBookLabels[line.text] ?? line.text)
                }
                if let heading = line.heading {
                    pendingHeadings.append(heading)
                }
            } else {
                if !line.text.isEmpty {
                    let previous = verses[verses.count - 1].sentenceScript
                    verses[verses.count - 1].sentenceScript = previous.isEmpty ? line.text : previous + " " + line.text
                }
                if let heading = line.heading {
                    pendingHeadings.append(heading)
                }
            }
        }
        return verses
    }
}
