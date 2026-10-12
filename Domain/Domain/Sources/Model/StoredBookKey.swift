//
//  StoredBookKey.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//

import Foundation

/// SwiftData 행의 권 이름(`titleName`)과 번역본을 짓고 푸는 유일한 곳(영어 현지화 결정 1).
///
/// | 행 | `titleName` | `translation` 열 |
/// |---|---|---|
/// | 개역개정 | `BibleTitle.rawValue`(예 `1-01Genesis.txt`) — 지금과 같다 | `.NKRV`(옛 행은 nil 일 수 있다) |
/// | KJV · BSB | `"<Translation.rawValue>-<BibleTitle.rawValue>"`(예 `KJV-1-01Genesis.txt`) — 본문 리소스 파일 이름과 같다 | 늘 nil |
///
/// - 열에는 영어 값을 쓰지 않는다 — 이미 나간 2.0.0 기기가 모르는 열거값을 디코딩하다 죽을 수 있다.
///   구버전은 모르는 `titleName` 을 `BibleTitle(rawValue:)` 로 풀지 못해 건너뛴다.
/// - 행을 읽을 때 번역본은 `titleName` 접두로 정하고, 접두가 없으면 열이 nil 이든 `.NKRV` 든 개역개정이다.
/// - `"NKRV-"` 접두는 만들지 않는다 — 개역개정 행 형식이 지금과 같아야 구버전 · 이전 일치 검사 · 백업이 그대로다.
/// - `titleName` 문자열을 직접 이어 붙이거나 자르지 않는다. 조회 술어의 `titleName == …` 도 `titleName(for:)` 로 짓는다.
public enum StoredBookKey {
    /// 접두와 권 이름 사이 구분자.
    private static let separator = "-"

    /// 역할: 장이 놓일 행의 `titleName` 을 짓는다.
    /// 입력 · 출력: 장(번역본 포함) → 개역개정은 `title.rawValue`, 그 밖은 `"<번역본>-<rawValue>"`.
    /// 부작용: 없음.
    public static func titleName(for chapter: BibleChapter) -> String {
        titleName(title: chapter.title, translation: chapter.translation)
    }

    /// 역할: 권과 번역본으로 행의 `titleName` 을 짓는다.
    /// 입력 · 출력: 권 · 번역본 → 개역개정은 `title.rawValue`, 그 밖은 `"<번역본>-<rawValue>"`.
    /// 부작용: 없음.
    public static func titleName(title: BibleTitle, translation: Translation) -> String {
        switch translation {
        case .NKRV: title.rawValue
        case .KJV, .BSB: translation.rawValue + separator + title.rawValue
        }
    }

    /// 역할: 행의 `titleName` 을 권과 번역본으로 푼다.
    /// 입력 · 출력: `titleName` → 아는 번역본 접두 + 권 rawValue 면 그 번역본, 접두 없는 권 rawValue 면 `.NKRV`, 그 밖 nil.
    ///   `"NKRV-"` 접두는 짓지 않으므로 풀지 않는다(nil).
    /// 부작용: 없음.
    public static func decode(_ titleName: String) -> (title: BibleTitle, translation: Translation)? {
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
