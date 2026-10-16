//
//  VerseDraftKey.swift
//  Domain
//
//  초안 하나를 가리키는 키와 초안 파일 이름 — `LocalPreservationWriter.swift` 에서 옮겼다(파일 길이, 2.2 필사책).
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 초안 하나를 가리키는 키 — 세션 · 필사책 · 번역 · 권 · 장 · 절 (정책 §12-6 구현 순서 ②, 2.2 필사책).
///
/// 초안은 동기화하지 않는 이 기기의 파일이라 `translation` 에 **실제 번역본**(`"NKRV"` · `"KJV"` · `"BSB"`)을 쓴다 — SwiftData 의
/// `translation` 열과 달리 구버전 기기가 읽지 않는다(영어 현지화 결정 1). 파일 이름도 번역본으로 시작한다(`KJV~1-01Genesis.txt~1~1.json`).
///
/// **필사책(2.2)** — 기본 필사책의 초안은 키 · 파일 이름 모두 2.2 이전과 같은 모양이다(파일 이름 `<번역~권~장~절>.json`).
/// 그 밖의 필사책은 파일 이름 앞에 `nb_<NotebookID.rawValue>~` 를 붙인다 — 행의 `titleName` 접두(`StoredBookKey`)와 같은 토큰이다.
/// JSON 에 `notebook` 이 없는 옛 초안은 기본 필사책이다.
public struct VerseDraftKey: Hashable, Codable, Sendable {
    public var sessionID: String
    /// 어느 필사책의 초안인가. 옛 초안(키 없음)은 기본 필사책이다.
    public var notebook: NotebookID
    public var translation: String
    public var title: String
    public var chapter: Int
    public var verse: Int

    /// 필사책 안의 장 그대로의 키 — 필사책 · 번역본 모두 page 를 따른다. 필사책에는 기본값이 없다(결정 12).
    public init(sessionID: String, page: NotebookChapter, verse: Int) {
        self.sessionID = sessionID
        self.notebook = page.notebook
        self.translation = page.chapter.translation.rawValue
        self.title = page.chapter.title.rawValue
        self.chapter = page.chapter.chapter
        self.verse = verse
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID, notebook, translation, title, chapter, verse
    }

    /// 옛 초안(2.2 이전 — `notebook` 이 없다)은 기본 필사책으로 읽는다. 있는데 형식이 틀리면 풀지 않는다 — 깨진 값을 기본 필사책에 붙이지 않는다
    /// (그 초안은 읽지 못한 초안으로 다뤄진다).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionID = try container.decode(String.self, forKey: .sessionID)
        self.notebook = try container.decodeIfPresent(NotebookID.self, forKey: .notebook) ?? .default
        self.translation = try container.decode(String.self, forKey: .translation)
        self.title = try container.decode(String.self, forKey: .title)
        self.chapter = try container.decode(Int.self, forKey: .chapter)
        self.verse = try container.decode(Int.self, forKey: .verse)
    }

    /// 키가 가리키는 장(번역본 포함). 이 판이 모르는 번역본 · 권이면 nil — 개역개정에 임의로 붙이지 않는다(정책 §8 「미상 판본을 임의 귀속하지 않음」).
    /// 필사책은 담지 않는다 — 필사책까지는 `page`.
    public var bibleChapter: BibleChapter? {
        guard let translation = Translation(rawValue: translation), let title = BibleTitle(rawValue: title) else { return nil }
        return BibleChapter(title: title, chapter: chapter, translation: translation)
    }

    /// 키가 가리키는 필사책 안의 장. 이 판이 모르는 번역본 · 권이면 nil(`bibleChapter` 와 같은 판정).
    public var page: NotebookChapter? {
        bibleChapter.map { NotebookChapter(notebook: notebook, chapter: $0) }
    }

    /// 파일 이름. 구성요소에 경로 구분자가 들어오지 않게 바꾼다. 기본 필사책은 2.2 이전과 같고, 그 밖은 앞에 `nb_<토큰>~` 이 붙는다.
    var fileName: String {
        Self.notebookFilePrefix(notebook) + Self.fileStem([translation, title, "\(chapter)", "\(verse)"]) + ".json"
    }

    /// 한 장의 초안 파일 이름이 모두 이것으로 시작한다 — 파일을 열지 않고 필사책 · 장으로 거른다.
    ///
    /// 기본 필사책의 앞머리(`KJV~1-01Genesis.txt~1~`)로는 다른 필사책의 파일(`nb_…~KJV~…`)이 걸리지 않는다 — 접두가 번역본보다 앞에 온다.
    static func chapterFilePrefix(notebook: NotebookID, translation: Translation, chapter: BibleChapter) -> String {
        notebookFilePrefix(notebook) + fileStem([translation.rawValue, chapter.title.rawValue, "\(chapter.chapter)"]) + "~"
    }

    /// 필사책 접두 — 기본 필사책은 빈 문자열(2.2 이전 이름 그대로), 그 밖은 `nb_<NotebookID.rawValue>~`.
    /// `StoredBookKey` 의 행 접두와 같은 모양이다. 토큰은 소문자 16진 32자리라 경로 구분자 · `~` 가 들지 않는다.
    private static func notebookFilePrefix(_ notebook: NotebookID) -> String {
        notebook.isDefault ? "" : notebookPrefix + notebook.rawValue + separator
    }

    /// 파일 이름 구성요소 사이 구분자.
    private static let separator = "~"
    /// 다른 필사책 파일 이름의 접두 시작 — `StoredBookKey` 의 행 접두와 같다.
    private static let notebookPrefix = "nb_"

    private static func fileStem(_ components: [String]) -> String {
        components.map { $0.replacingOccurrences(of: "/", with: "_") }.joined(separator: separator)
    }

    /// 파일 이름이 가리키는 장(번역본 포함) — 파일을 열지 않고 읽는다(깨진 초안도 어느 장인지는 안다). 두 형식(접두 없음 · `nb_<토큰>~`)을 모두 읽는다.
    /// 모양이 다르거나 이 판이 모르는 번역본이면 nil — 모르는 번역본을 개역개정 장으로 치지 않는다. 필사책까지는 `page(fromFileName:)`.
    static func chapter(fromFileName name: String) -> BibleChapter? {
        page(fromFileName: name)?.chapter
    }

    /// 파일 이름이 가리키는 필사책 안의 장 — 접두 없는 이름(2.2 이전 · 기본 필사책)은 기본 필사책, `nb_<토큰>~` 이름은 그 필사책이다.
    /// 모양이 다르거나(토큰 형식이 틀림 · `nb_default~` 포함) 이 판이 모르는 번역본이면 nil.
    static func page(fromFileName name: String) -> NotebookChapter? {
        guard let parts = FileNameParts(name), let translation = Translation(rawValue: parts.translation) else { return nil }
        return NotebookChapter(notebook: parts.notebook, chapter: BibleChapter(title: parts.title, chapter: parts.chapter, translation: translation))
    }

    /// 파일 이름이 가리키는 필사책 — 번역본은 보지 않는다(이 판이 모르는 번역본의 파일도 그 필사책을 지울 때 함께 지운다). 모양이 다르면 nil.
    static func notebook(fromFileName name: String) -> NotebookID? {
        FileNameParts(name)?.notebook
    }

    /// 파일 이름이 초안 파일의 모양(`[nb_<토큰>~]번역~권~장~절`)인가 — 번역본은 이 판이 모르는 값이어도 된다(옆으로 옮긴 파일을 세고 지울 때 쓴다).
    static func hasDraftFileShape(_ name: String) -> Bool {
        FileNameParts(name) != nil
    }

    /// 파일 이름의 필사책 · 번역 · 권 · 장. 번역은 문자열 그대로 둔다.
    private struct FileNameParts {
        let notebook: NotebookID
        let translation: String
        let title: BibleTitle
        let chapter: Int

        /// 모양(`[nb_<토큰>~]번역~권~장~절[.json]`)이 다르면 nil. 접두의 토큰은 소문자 16진 32자리만 받는다 — `nb_default~` 는 짓지 않으므로 풀지 않는다.
        init?(_ name: String) {
            var parts = name.replacingOccurrences(of: ".json", with: "").split(separator: "~", omittingEmptySubsequences: false)
            var notebook = NotebookID.default
            if parts.first?.hasPrefix(VerseDraftKey.notebookPrefix) == true {
                let token = parts.removeFirst().dropFirst(VerseDraftKey.notebookPrefix.count)
                guard NotebookID.isToken(token), let parsed = NotebookID(rawValue: String(token)) else { return nil }
                notebook = parsed
            }
            guard parts.count == 4, let title = BibleTitle(rawValue: String(parts[1])), let chapter = Int(parts[2]) else { return nil }
            self.notebook = notebook
            self.translation = String(parts[0])
            self.title = title
            self.chapter = chapter
        }
    }
}
