//
//  VerseWidgetPayload.swift
//  WIDGET-0 스파이크 — 앱과 위젯이 함께 컴파일하는 유일한 파일.
//
//  앱이 App Group 컨테이너에 "지정 당시 이미지 1장 + 권·장·절"을 쓰고
//  위젯이 그것만 읽어 가는 최소 경로를 증명하기 위한 코드다.
//  SwiftData·CloudKit·TCA 를 위젯에서 열지 않는다는 설계 전제를 그대로 반영했다.
//

import Foundation
import OSLog

/// 앱과 위젯이 공유하는 App Group 식별자.
public enum VerseWidgetSharing {
    public static let appGroupID = "group.kr.co.carve.leetaek"
    public static let payloadFileName = "designated-verse.json"
    public static let imageFileName = "designated-verse.png"
    public static let deepLinkScheme = "carve"

    static let logger = Logger(subsystem: "kr.co.carve.leetaek", category: "WidgetSpike")

    /// App Group 컨테이너 루트. entitlement 가 없거나 그룹이 미등록이면 nil 이다.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
}

/// 위젯이 그리는 데 필요한 전부. 행(row)을 참조하지 않고 지정 시점 사본만 담는다.
public struct VerseWidgetPayload: Codable, Equatable, Sendable {
    /// `BibleTitle.rawValue` (현재 본문 파일명). WIDGET 본 구현에서 안정 키로 교체할 후보.
    public var titleRawValue: String
    /// 사람이 읽는 권 이름. 위젯이 Domain 을 링크하지 않아도 되도록 문자열로 복사해 둔다.
    public var bookDisplayName: String
    public var chapter: Int
    public var verse: Int
    /// 번역본 식별자. BIBLE-EN 이후를 위해 자리를 미리 잡아 둔다.
    public var translation: String
    public var designatedAt: Date

    public init(
        titleRawValue: String,
        bookDisplayName: String,
        chapter: Int,
        verse: Int,
        translation: String,
        designatedAt: Date
    ) {
        self.titleRawValue = titleRawValue
        self.bookDisplayName = bookDisplayName
        self.chapter = chapter
        self.verse = verse
        self.translation = translation
        self.designatedAt = designatedAt
    }

    /// 위젯 탭 시 앱이 받을 URL. `widgetURL(_:)` 에 그대로 넣는다.
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

/// App Group 컨테이너 읽기·쓰기. 앱은 write, 위젯은 read 만 쓴다.
public enum VerseWidgetStore {
    public static func write(payload: VerseWidgetPayload, imageData: Data) throws {
        guard let root = VerseWidgetSharing.containerURL else {
            throw VerseWidgetStoreError.containerUnavailable
        }
        try imageData.write(to: root.appendingPathComponent(VerseWidgetSharing.imageFileName), options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(payload).write(
            to: root.appendingPathComponent(VerseWidgetSharing.payloadFileName),
            options: .atomic
        )
    }

    public static func read() -> (payload: VerseWidgetPayload, imageData: Data)? {
        guard let root = VerseWidgetSharing.containerURL else {
            VerseWidgetSharing.logger.notice("WIDGET-0 read: App Group 컨테이너를 얻지 못했다")
            return nil
        }
        guard
            let json = try? Data(contentsOf: root.appendingPathComponent(VerseWidgetSharing.payloadFileName)),
            let imageData = try? Data(contentsOf: root.appendingPathComponent(VerseWidgetSharing.imageFileName))
        else {
            VerseWidgetSharing.logger.notice("WIDGET-0 read: 지정된 절이 없다 (\(root.path, privacy: .public))")
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(VerseWidgetPayload.self, from: json) else { return nil }
        return (payload, imageData)
    }
}

public enum VerseWidgetStoreError: Error {
    case containerUnavailable
}
