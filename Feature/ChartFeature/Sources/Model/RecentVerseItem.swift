//
//  RecentVerseItem.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import Domain

/// 주간 요약 「최근」 의 한 줄 — 최근에 고친 절. 누르면 **그 번역본**의 절로 연다.
public struct RecentVerseItem: Equatable, Identifiable, Sendable {
    /// 번역본 · 권 · 장 · 절 · 고친 시각. 권 자리는 저장 행과 같은 이름(`StoredBookKey`)이라 개역개정은 지금과 같고, 영어는 번역본 접두가 붙는다.
    public var id: String {
        "\(StoredBookKey.titleName(for: verse.title))|\(verse.title.chapter)|\(verse.verse)|\(updatedAt.timeIntervalSince1970)"
    }

    /// 고친 절 — 장(`verse.title`)에 번역본이 함께 든다.
    public let verse: BibleVerse
    public let updatedAt: Date
    public let drawingID: String?

    public init(verse: BibleVerse, updatedAt: Date, drawingID: String? = nil) {
        self.verse = verse
        self.updatedAt = updatedAt
        self.drawingID = drawingID
    }

    /// 화면에 적는 참조(「요한복음 3장 16절 · 개역개정」). 번역본이 섞이는 목록이라 약칭을 붙인다(영어 현지화 결정 11).
    public var message: String {
        BibleReference(chapter: verse.title, verse: verse.verse, showsTranslation: true).text
    }
}
