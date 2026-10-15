//
//  RecentVerseItem.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import Domain

/// 주간 요약 「최근」 의 한 줄 — 최근에 고친 절. 누르면 **그 필사책 · 그 번역본**의 절로 연다.
public struct RecentVerseItem: Equatable, Identifiable, Sendable {
    /// 필사책 · 번역본 · 권 · 장 · 절 · 고친 시각. 권 자리는 저장 행과 같은 이름(`StoredBookKey`)이라 기본 필사책의 개역개정은 지금과 같고,
    /// 영어는 번역본 접두, 다른 필사책은 필사책 접두가 붙는다 — 같은 절을 두 필사책에서 고쳐도 항목이 겹치지 않는다.
    public var id: String {
        "\(StoredBookKey.titleName(for: page))|\(verse.title.chapter)|\(verse.verse)|\(updatedAt.timeIntervalSince1970)"
    }

    /// 고친 절 — 장(`verse.title`)에 번역본이 함께 든다.
    public let verse: BibleVerse
    public let updatedAt: Date
    public let drawingID: String?
    /// 그 절을 고친 필사책. 누르면 이 필사책으로 연다(2.2 결정 10).
    public let notebook: NotebookID

    /// 그 절이 든 필사책 · 장 — 누르면 여는 곳(`DrawingWeeklySummaryFeature.Action.openVerse`).
    public var page: NotebookChapter {
        NotebookChapter(notebook: notebook, chapter: verse.title)
    }

    /// - Parameter notebook: 그 절을 고친 필사책. 활동 행에서 필사책을 아직 풀지 않는 곳은 기본 필사책이다.
    public init(verse: BibleVerse, updatedAt: Date, drawingID: String? = nil, notebook: NotebookID = .default) {
        self.verse = verse
        self.updatedAt = updatedAt
        self.drawingID = drawingID
        self.notebook = notebook
    }

    /// 역할: 화면에 적는 참조를 만든다. 번역본이 섞이는 목록이라 영어 번역본만 약칭을 붙인다(사용자 결정 17).
    /// 입력 · 출력: 로케일(뷰는 환경 locale) → 「요한복음 3장 16절」 · 「요한복음 3장 16절 · KJV」 · 「John 3:16 · KJV」.
    /// 부작용: 없음.
    public func message(locale: Locale) -> String {
        BibleReference(chartChapter: verse.title, verses: .verse(verse.verse)).text(locale: locale)
    }
}

extension BibleReference {
    /// 차트 목록(최근 절 · 최근 장 · 가장 많이 쓴 장)의 참조 — 번역본이 섞이므로 KJV · BSB 는 약칭을 「 · KJV」 처럼 붙이고,
    /// 개역개정은 약칭을 생략한다(사용자 결정 17 — 2.0 까지 개역개정만 있던 목록의 표기를 그대로 둔다).
    /// - Parameters:
    ///   - chapter: 권 · 장 · 번역본.
    ///   - verses: 가리키는 절. 기본은 장 전체.
    init(chartChapter chapter: BibleChapter, verses: Verses = .wholeChapter) {
        self.init(chapter: chapter, verses: verses, showsTranslation: chapter.translation != .NKRV)
    }
}
