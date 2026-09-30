//
//  BibleTextClient.swift
//  Domain
//
//  Created by Codex on 4/2/26.
//

import Foundation
import Resources

import Dependencies

public protocol BibleTextClient: Sendable {
    func fetch(chapter: BibleChapter) throws -> [BibleVerse]
}

public enum BibleTextClientError: Error, Sendable, Equatable {
    case chapterConvertError
    case fetchSentenceError
}

private enum BibleTextClientKey: DependencyKey {
    static let liveValue: any BibleTextClient = ResourceBibleTextClient()
    static let testValue: any BibleTextClient = UnimplementedBibleTextClient()
    static let previewValue: any BibleTextClient = UnimplementedBibleTextClient()
}

public extension DependencyValues {
    var bibleTextClient: any BibleTextClient {
        get { self[BibleTextClientKey.self] }
        set { self[BibleTextClientKey.self] = newValue }
    }
}

struct ResourceBibleTextClient: BibleTextClient {
    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        let encodingEUCKR = CFStringConvertEncodingToNSStringEncoding(0x0422)

        guard let textPath = ResourcesResources.bundle.path(forResource: chapter.title.rawValue, ofType: nil) else {
            return []
        }

        do {
            let bible = try String(
                contentsOfFile: textPath,
                encoding: String.Encoding(rawValue: encodingEUCKR)
            )

            // 절 번호 없이 이어지는 줄 · 합쳐진 절 · 시편 권 표시는 파서가 앞 절 · 소제목으로 정리한다.
            return BibleChapterTextParser.verses(in: bible, chapter: chapter)
        } catch {
            throw BibleTextClientError.fetchSentenceError
        }
    }
}

private struct UnimplementedBibleTextClient: BibleTextClient {
    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        []
    }
}
