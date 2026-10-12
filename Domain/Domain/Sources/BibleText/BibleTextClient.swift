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

/// 번들 본문 리소스에서 장을 읽는다.
///
/// 파일은 장의 번역본이 정한다 — 이름은 `Translation.resourceFileName(for:)`(개역개정 `1-01Genesis.txt`, 영어 `KJV-1-01Genesis.txt`),
/// 인코딩은 `Translation.textEncoding`(개역개정 CP949, 영어 UTF-8)이다. 리소스는 번들 루트에 평평하게 들어가므로 하위 폴더 없이 이름으로 찾는다.
/// 줄 문법은 번역본과 상관없이 같아(`장:절 [<소제목>] 본문`, 줄 CR) 파서는 하나다.
struct ResourceBibleTextClient: BibleTextClient {
    /// 역할: 장의 번역본 본문 파일을 읽어 그 장의 절 목록을 만든다.
    /// 입력 · 출력: 번역본이 든 장 → 절 목록. 리소스가 없으면 빈 목록, 읽기 · 디코딩에 실패하면 `fetchSentenceError`.
    /// 부작용: 번들 파일 읽기.
    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        let translation = chapter.translation

        guard let textPath = ResourcesResources.bundle.path(
            forResource: translation.resourceFileName(for: chapter.title),
            ofType: nil
        ) else {
            return []
        }

        do {
            let bible = try String(contentsOfFile: textPath, encoding: translation.textEncoding)

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
