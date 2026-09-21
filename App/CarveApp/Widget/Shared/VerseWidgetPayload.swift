//
//  VerseWidgetPayload.swift
//  Carve · CarveWidget
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  앱과 위젯이 **함께 컴파일하는 유일한 파일**이다. 위젯은 Domain · SwiftData · CloudKit · TCA 를 링크하지 않고
//  App Group 컨테이너에 놓인 「지정 당시 사본」(작은 JSON 1 개 + 말씀마다 필기 PNG 1 장)만 읽는다 (WIDGET-0 §2).
//

import Foundation
import OSLog

/// 앱과 위젯이 공유하는 App Group 과 파일 이름.
public enum VerseWidgetSharing {
    /// 앱 · 위젯 entitlement 양쪽에 있어야 한다.
    public static let appGroupID = "group.kr.co.carve.leetaek"
    /// 위젯이 읽는 말씀 목록.
    public static let payloadFileName = "widget-verses.json"
    /// 필기 그림 파일 이름의 앞머리 — 남은 그림을 찾아 지울 때 쓴다.
    public static let handwritingPrefix = "widget-ink-"
    /// 말씀 하나만 담던 시절(2026-09-16 첫 구현)의 파일. 새로 쓸 때 지운다.
    static let legacyFileNames = ["widget-verse.json", "widget-verse-handwriting.png"]
    /// 위젯을 눌렀을 때 앱을 여는 URL 스킴.
    public static let deepLinkScheme = "carve"
    /// 위젯 하나뿐이라 kind 도 하나다.
    public static let widgetKind = "CarveVerseWidget"

    static let logger = Logger(subsystem: "kr.co.carve.leetaek", category: "Widget")

    /// App Group 컨테이너 루트. entitlement 가 없거나 그룹이 등록되지 않았으면 nil 이다.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
}

/// 위젯이 그리는 데 필요한 전부. 저장 행(row)을 참조하지 않고 **지정 당시 사본**만 담는다.
public struct VerseWidgetPayload: Codable, Equatable, Sendable {
    /// `BibleTitle.rawValue`(본문 파일명). 위젯을 눌러 그 절로 들어갈 때 쓴다.
    public var titleRawValue: String
    /// 사람이 읽는 권 이름. 위젯이 Domain 을 링크하지 않아도 되도록 문자열로 복사해 둔다.
    public var bookDisplayName: String
    public var chapter: Int
    public var verse: Int
    /// 번역본 식별자(`Translation.rawValue`).
    public var translation: String
    /// 번역본 이름(「개역개정」).
    public var translationDisplayName: String
    /// 지정 당시의 본문. 필기가 없는 말씀은 위젯이 이 글을 보여 준다.
    public var sentence: String
    /// 위젯에 담은 시각.
    public var designatedAt: Date

    public init(
        titleRawValue: String,
        bookDisplayName: String,
        chapter: Int,
        verse: Int,
        translation: String,
        translationDisplayName: String,
        sentence: String,
        designatedAt: Date
    ) {
        self.titleRawValue = titleRawValue
        self.bookDisplayName = bookDisplayName
        self.chapter = chapter
        self.verse = verse
        self.translation = translation
        self.translationDisplayName = translationDisplayName
        self.sentence = sentence
        self.designatedAt = designatedAt
    }

    /// 앱과 같은 출처 표기(「시편 23장 1절」).
    public var reference: String {
        "\(bookDisplayName) \(chapter)장 \(verse)절"
    }

    /// 위젯처럼 좁은 자리의 짧은 표기(「시편 23:1」, 시안 G4).
    public var compactReference: String {
        "\(bookDisplayName) \(chapter):\(verse)"
    }

    /// 이 말씀의 필기 그림 파일 이름.
    ///
    /// 절마다 따로 두어 한 말씀을 빼도 다른 말씀의 그림이 다치지 않는다.
    /// 파일 이름에 쓸 수 없는 글자가 섞이지 않도록 ASCII 낱자와 숫자만 남긴다.
    public var handwritingFileName: String {
        let raw = "\(titleRawValue)-\(chapter)-\(verse)-\(translation)"
        let safe = String(raw.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
        return "\(VerseWidgetSharing.handwritingPrefix)\(safe).png"
    }

    /// 위젯을 눌렀을 때 앱이 받는 URL.
    public var deepLinkURL: URL? {
        var components = URLComponents()
        components.scheme = VerseWidgetSharing.deepLinkScheme
        components.host = "verse"
        components.queryItems = [
            .init(name: "title", value: titleRawValue),
            .init(name: "chapter", value: String(chapter)),
            .init(name: "verse", value: String(verse)),
            .init(name: "translation", value: translation)
        ]
        return components.url
    }
}

/// 위젯이 읽어 간 한 벌.
public struct VerseWidgetContent: Equatable, Sendable {
    public let payload: VerseWidgetPayload
    /// 필기 그림(PNG). 필기 없는 말씀이면 nil.
    public let handwriting: Data?

    public init(payload: VerseWidgetPayload, handwriting: Data?) {
        self.payload = payload
        self.handwriting = handwriting
    }
}

/// App Group 컨테이너 읽기 · 쓰기. 앱이 쓰고 위젯이 읽는다.
public enum VerseWidgetStore {
    /// 위젯이 돌릴 말씀을 이 목록으로 맞춘다.
    /// - Parameters:
    ///   - payloads: 담을 말씀들. 순서가 곧 담은 순서다.
    ///   - handwriting: 새로 그린 필기(`handwritingFileName` → PNG). 여기에 없는 말씀은 이미 저장된 그림을 그대로 둔다.
    public static func write(_ payloads: [VerseWidgetPayload], handwriting: [String: Data] = [:]) throws {
        guard let root = VerseWidgetSharing.containerURL else { throw VerseWidgetStoreError.containerUnavailable }
        for (fileName, data) in handwriting {
            try data.write(to: root.appendingPathComponent(fileName), options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(payloads).write(to: root.appendingPathComponent(VerseWidgetSharing.payloadFileName), options: .atomic)
        removeUnusedFiles(in: root, keeping: Set(payloads.map(\.handwritingFileName)))
    }

    /// 지금 담긴 말씀들. 그림은 읽지 않는다 — 위젯은 보여 줄 말씀의 그림만 따로 읽는다.
    public static func readPayloads() -> [VerseWidgetPayload] {
        guard let root = VerseWidgetSharing.containerURL else {
            VerseWidgetSharing.logger.notice("App Group 컨테이너를 얻지 못했다")
            return []
        }
        guard let json = try? Data(contentsOf: root.appendingPathComponent(VerseWidgetSharing.payloadFileName)) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([VerseWidgetPayload].self, from: json)) ?? []
    }

    /// 그 말씀의 필기 그림. 필기 없이 담은 말씀이면 nil.
    public static func handwriting(for payload: VerseWidgetPayload) -> Data? {
        guard let root = VerseWidgetSharing.containerURL else { return nil }
        return try? Data(contentsOf: root.appendingPathComponent(payload.handwritingFileName))
    }

    /// 담긴 말씀과 그림을 함께 읽는다.
    public static func read() -> [VerseWidgetContent] {
        readPayloads().map { VerseWidgetContent(payload: $0, handwriting: handwriting(for: $0)) }
    }

    /// 전부 뺀다. 담긴 말씀이 없어도 오류가 아니다.
    public static func clear() throws {
        guard let root = VerseWidgetSharing.containerURL else { throw VerseWidgetStoreError.containerUnavailable }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(VerseWidgetSharing.payloadFileName))
        removeUnusedFiles(in: root, keeping: [])
    }

    /// 목록에서 빠진 말씀의 그림과 예전 구현이 남긴 파일을 지운다.
    private static func removeUnusedFiles(in root: URL, keeping keep: Set<String>) {
        let manager = FileManager.default
        for name in VerseWidgetSharing.legacyFileNames {
            try? manager.removeItem(at: root.appendingPathComponent(name))
        }
        let names = (try? manager.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasPrefix(VerseWidgetSharing.handwritingPrefix) && !keep.contains(name) {
            try? manager.removeItem(at: root.appendingPathComponent(name))
        }
    }
}

/// 위젯이 넘긴 URL 을 앱이 읽는다. 만드는 쪽은 `VerseWidgetPayload.deepLinkURL` 이다.
public enum VerseWidgetDeepLink {
    /// URL 이 가리키는 절.
    public struct Components: Equatable, Sendable {
        public let titleRawValue: String
        public let chapter: Int
        public let verse: Int
        public let translation: String
    }

    /// 위젯이 만든 URL 이면 절을 돌려준다. 다른 URL 이면 nil.
    public static func parse(_ url: URL) -> Components? {
        guard url.scheme == VerseWidgetSharing.deepLinkScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "verse" else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let title = value("title"),
              let chapter = value("chapter").flatMap(Int.init),
              let verse = value("verse").flatMap(Int.init) else { return nil }
        return Components(
            titleRawValue: title,
            chapter: chapter,
            verse: verse,
            translation: value("translation") ?? ""
        )
    }
}

public enum VerseWidgetStoreError: Error {
    /// App Group 컨테이너에 닿지 못했다 — entitlement 또는 그룹 등록 문제다.
    case containerUnavailable
}
