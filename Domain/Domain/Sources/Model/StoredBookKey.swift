//
//  StoredBookKey.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//

import Foundation

/// SwiftData 행의 권 이름(`titleName`)과 번역본 · 필사책을 짓고 푸는 유일한 곳(영어 현지화 결정 1 · 2.2 필사책 결정 1).
///
/// | 행 | `titleName` | `translation` 열 |
/// |---|---|---|
/// | 개역개정 | `BibleTitle.rawValue`(예 `1-01Genesis.txt`) — 지금과 같다 | `.NKRV`(옛 행은 nil 일 수 있다) |
/// | KJV · BSB | `"<Translation.rawValue>-<BibleTitle.rawValue>"`(예 `KJV-1-01Genesis.txt`) — 본문 리소스 파일 이름과 같다 | 쓸 때 nil |
/// | 기본이 아닌 필사책(2.2) | `"nb_<NotebookID.rawValue>~<위 두 행의 titleName>"`(예 `nb_0f3a…~KJV-1-19Psalms.txt`) | 위 두 행과 같다 |
///
/// - **기본 필사책 행은 위 두 행 그대로다**(혼재 버전 규칙 ①) — 접두를 붙이지 않는다. 지금까지의 모든 필사가 기본 필사책이고,
///   옛 앱(2.0.0 · 2.1)은 `titleName ==` 로만 찾으므로 기본 필사책 행을 그대로 보고 쓴다.
/// - 필사책 접두 행은 옛 앱이 `BibleTitle(rawValue:)`(2.0.0) · `StoredBookKey.decode(_:)`(2.1 — 지금은 `decodeBook(_:)` 로 남은 규칙)로 풀지 못해
///   건너뛴다 — 이 동작에 기댄다.
///   접두는 소문자 `nb_` 로 시작해 어느 번역본 접두(`NKRV` · `KJV-` · `BSB-`)와도 겹치지 않고, 토큰에는 `.` 이 없다(business `id` 는 `.` 으로 잇는다).
/// - 필사책을 `translation` 등 기존 열로 가르지 않는다(혼재 버전 규칙 ②) — 옛 앱이 레코드에 없는 열을 기본값으로 채워 되올린다.
///
/// - 열에는 영어 값을 쓰지 않는다 — 이미 나간 2.0.0 기기가 모르는 열거값을 디코딩하다 죽을 수 있다.
///   구버전은 모르는 `titleName` 을 `BibleTitle(rawValue:)` 로 풀지 못해 건너뛴다.
/// - 행을 읽을 때 번역본은 `titleName` 접두로 정하고, 접두가 없으면 열이 nil 이든 `.NKRV` 든 개역개정이다.
/// - **영어 행의 열은 nil 로 남는다고 기대하지 않는다.** CloudKit 레코드에 없는 값은 받은 기기에서 스키마 기본값 `.NKRV` 로 채워지고,
///   2.0.0 기기를 거치면 처음 쓴 기기의 행도 `.NKRV` 로 돌아온다(2.1.0 출시 시험 EN-M4). 그래서 영어 행을 열로 거르거나 열로 번역본을 정하지 않는다.
/// - `"NKRV-"` 접두는 만들지 않는다 — 개역개정 행 형식이 지금과 같아야 구버전 · 이전 일치 검사 · 백업이 그대로다.
/// - `titleName` 문자열을 직접 이어 붙이거나 자르지 않는다. 조회 술어의 `titleName == …` 도 `titleName(for:)`(page) · `titleName(title:translation:notebook:)` 로 짓는다.
/// - 필사책 없이 짓거나 푸는 공개 함수는 없다(2.2 t4 에서 지웠다) — 기본 필사책도 `notebook: .default` 로 밝혀 짓고, 풀 때는 `decodeRow(_:)` 의 `notebook` 을 본다.
public enum StoredBookKey {
    /// 접두와 권 이름 사이 구분자.
    private static let separator = "-"
    /// 기본이 아닌 필사책 행의 접두 시작. 소문자라 번역본 접두(대문자)와 겹치지 않는다.
    private static let notebookPrefix = "nb_"
    /// 필사책 토큰과 그 뒤 `titleName` 사이 구분자. 권 이름 · 번역본 접두 · 토큰에 없는 글자다.
    private static let notebookTerminator: Character = "~"

    /// 역할: 필사책 안의 장이 놓일 행의 `titleName` 을 짓는다.
    /// 입력 · 출력: 필사책 + 장(번역본 포함) → 기본 필사책은 2.2 이전 형식 그대로, 그 밖은 `"nb_<토큰>~"` 을 앞에 붙인다.
    /// 부작용: 없음.
    public static func titleName(for page: NotebookChapter) -> String {
        titleName(title: page.chapter.title, translation: page.chapter.translation, notebook: page.notebook)
    }

    /// 역할: 권 · 번역본 · 필사책으로 행의 `titleName` 을 짓는다.
    /// 입력 · 출력: 기본 필사책은 2.2 이전 형식 그대로(개역개정 `rawValue` · 영어 `"<번역본>-<rawValue>"` — 행 형식을 바꾸지 않는다),
    ///   그 밖은 `"nb_<NotebookID.rawValue>~<그 값>"`.
    /// 부작용: 없음.
    public static func titleName(title: BibleTitle, translation: Translation, notebook: NotebookID) -> String {
        let bookName = bookTitleName(title: title, translation: translation)
        guard !notebook.isDefault else { return bookName }
        return notebookPrefix + notebook.rawValue + String(notebookTerminator) + bookName
    }

    /// 역할: 행의 `titleName` 을 권 · 번역본 · 필사책으로 푼다.
    /// 입력 · 출력: 접두 없는 행은 권 · 번역본으로 풀어(`decodeBook(_:)`) 기본 필사책, `"nb_"` 로 시작하면 토큰이 `NotebookID` 형식(소문자 16진 32자리)이고
    ///   `"~"` 뒤가 권 · 번역본으로 풀릴 때만 그 필사책. 그 밖(토큰 대문자 · 길이 다름 · `"default"` 토큰 · 구분자 없음 · 모르는 권)은 nil.
    /// 부작용: 없음.
    public static func decodeRow(_ titleName: String) -> StoredRowKey? {
        guard titleName.hasPrefix(notebookPrefix) else {
            return decodeBook(titleName).map { StoredRowKey(title: $0.title, translation: $0.translation, notebook: .default) }
        }
        let rest = titleName.dropFirst(notebookPrefix.count)
        guard let terminator = rest.firstIndex(of: notebookTerminator) else { return nil }
        let token = rest[..<terminator]
        // 접두 행에는 기본 필사책 토큰(`default`)을 짓지 않는다 — 형식 검사로 32자리만 받는다.
        guard NotebookID.isToken(token), let notebook = NotebookID(rawValue: String(token)) else { return nil }
        guard let decoded = decodeBook(String(rest[rest.index(after: terminator)...])) else { return nil }
        return StoredRowKey(title: decoded.title, translation: decoded.translation, notebook: notebook)
    }

    /// 역할: 권과 번역본으로 기본 필사책 행 형식의 `titleName` 을 짓는다 — 필사책 접두 행의 뒷부분도 이 값이다.
    /// 입력 · 출력: 권 · 번역본 → 개역개정은 `title.rawValue`, 그 밖은 `"<번역본>-<rawValue>"`(2.1 의 공개 함수 `titleName(title:translation:)` 과 같은 형식).
    /// 부작용: 없음.
    private static func bookTitleName(title: BibleTitle, translation: Translation) -> String {
        switch translation {
        case .NKRV: title.rawValue
        case .KJV, .BSB: translation.rawValue + separator + title.rawValue
        }
    }

    /// 역할: 기본 필사책 행 형식의 `titleName` 을 권과 번역본으로 푼다 — 필사책 접두 행은 접두를 뗀 뒤 이것으로 푼다.
    /// 입력 · 출력: `titleName` → 아는 번역본 접두 + 권 rawValue 면 그 번역본, 접두 없는 권 rawValue 면 `.NKRV`, 그 밖 nil.
    ///   `"NKRV-"` 접두는 짓지 않으므로 풀지 않는다(nil). 필사책 접두(`"nb_…~"`) 행도 nil 이다 — 2.1 의 공개 함수 `decode(_:)` 와 같다.
    /// 부작용: 없음.
    private static func decodeBook(_ titleName: String) -> (title: BibleTitle, translation: Translation)? {
        if let title = BibleTitle(rawValue: titleName) {
            return (title, .NKRV)
        }
        for translation in Translation.allCases where translation != .NKRV {
            let prefix = translation.rawValue + separator
            guard titleName.hasPrefix(prefix) else { continue }
            guard let title = BibleTitle(rawValue: String(titleName.dropFirst(prefix.count))) else { return nil }
            return (title, translation)
        }
        return nil
    }

    /// 역할: 행의 `translation` 열에 쓸 값을 정한다.
    /// 입력 · 출력: 번역본 → `.NKRV` 는 `.NKRV`, 그 밖 nil(열에는 영어 값을 쓰지 않는다).
    /// 부작용: 없음.
    public static func translationColumn(for translation: Translation) -> Translation? {
        switch translation {
        case .NKRV: .NKRV
        case .KJV, .BSB: nil
        }
    }
}

/// 행의 `titleName` 을 푼 값 — 권 · 번역본 · 필사책(`StoredBookKey.decodeRow(_:)`).
public struct StoredRowKey: Hashable, Sendable {
    public let title: BibleTitle
    public let translation: Translation
    public let notebook: NotebookID

    public init(title: BibleTitle, translation: Translation, notebook: NotebookID) {
        self.title = title
        self.translation = translation
        self.notebook = notebook
    }

    /// 역할: 이 행 키와 장 번호로 필사책 안의 장을 짓는다.
    /// 입력 · 출력: 장 번호(행의 `titleChapter`) → 같은 필사책 · 권 · 번역본의 `NotebookChapter`.
    /// 부작용: 없음.
    public func page(chapter: Int) -> NotebookChapter {
        NotebookChapter(notebook: notebook, chapter: BibleChapter(title: title, chapter: chapter, translation: translation))
    }
}
