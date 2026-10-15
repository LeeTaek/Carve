//
//  NotebookID.swift
//  Domain
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Sharing

/// 필사책 하나를 가리키는 값 (2.2 「회차별 필사책」).
///
/// 같은 말씀을 여러 번 쓰고 필사책마다 독립된 필기로 보관한다. 잉크 행(`BibleDrawing`)은 그대로 두고, 필사책은 행의 `titleName` 접두로 가른다
/// (`StoredBookKey.titleName(for: NotebookChapter)`). 지금까지의 모든 필사는 **기본 필사책**(`default`)이고, 기본 필사책 행은 접두가 없다.
///
/// | 값 | `rawValue` | 행의 `titleName` |
/// |---|---|---|
/// | 기본 필사책 | `"default"` | 지금 형식 그대로 — 옛 앱과 같은 행 |
/// | 그 밖 | 소문자 16진 32자리(UUID 에서 `-` 를 빼고 소문자) | `"nb_<rawValue>~<지금 titleName>"` |
///
/// - 형식이 맞지 않는 문자열은 만들지 않는다(`init?(rawValue:)` 가 nil) — 행 접두 · 저장한 지금 필사책 · 백업에서 같은 검사를 쓴다.
/// - 토큰에는 `.` 이 없다 — 행의 business `id` 가 `"<titleName>.<장>.<절>.<시각>"` 이라 `.` 이 들면 옛 코드가 다르게 자를 수 있다.
public struct NotebookID: Hashable, Sendable, Codable {
    /// `"default"` 또는 소문자 16진 32자리.
    public let rawValue: String

    /// 기본 필사책의 `rawValue`.
    private static let defaultRawValue = "default"
    /// 기본이 아닌 필사책 토큰의 길이 — UUID 128비트의 16진 표기.
    private static let tokenLength = 32

    /// 처음부터 있던 필사책 — 2.2 이전의 모든 필사가 여기에 든다. 지울 수 없고 이름은 바꿀 수 있다.
    public static let `default` = NotebookID(validated: defaultRawValue)

    /// 역할: 저장한 문자열을 필사책 ID 로 푼다.
    /// 입력 · 출력: `"default"` 또는 소문자 16진 32자리면 그 ID, 그 밖(대문자 · 길이 다름 · `-` 포함 · 빈 문자열)은 nil.
    /// 부작용: 없음.
    public init?(rawValue: String) {
        guard rawValue == Self.defaultRawValue || Self.isToken(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// 검사를 마친 값으로 만든다.
    private init(validated rawValue: String) {
        self.rawValue = rawValue
    }

    /// 역할: 새 필사책 ID 를 UUID 에서 짓는다.
    /// 입력 · 출력: UUID → `uuidString` 에서 `-` 를 빼고 소문자로 바꾼 32자리.
    /// 부작용: 없음. UUID 는 호출부가 `@Dependency(\.uuid)` 로 받아 넘긴다(시험에서 고정).
    public static func make(uuid: UUID) -> NotebookID {
        NotebookID(validated: uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased())
    }

    /// 기본 필사책인가.
    public var isDefault: Bool {
        rawValue == Self.defaultRawValue
    }

    /// 역할: 기본이 아닌 필사책의 토큰 형식인지 본다.
    /// 입력 · 출력: 문자열 → 소문자 16진(`0-9` · `a-f`) 정확히 32자리면 true.
    /// 부작용: 없음.
    static func isToken(_ text: some StringProtocol) -> Bool {
        text.utf8.count == tokenLength && text.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }

    /// 문자열 하나로 쓴다(`"default"` 또는 32자리).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// 형식이 맞지 않는 문자열은 받지 않는다 — 깨진 값을 기본 필사책으로 바꿔 읽지 않는다(읽는 쪽이 정한다).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let notebook = NotebookID(rawValue: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "필사책 ID 형식이 아니다: \(text)")
        }
        self = notebook
    }
}

/// 필사책 안의 장 하나 — 저장 경로가 나르는 주소다(결정 12).
///
/// 저장 · 조회 경로는 이 값을 **기본값 없는 인자**로 받는다. 필사책을 빠뜨리면 컴파일이 막혀야 한다 — 기본값을 두면
/// 지금 필사책이 아닌 기본 필사책에 조용히 써진다.
public struct NotebookChapter: Hashable, Sendable, Codable {
    /// 어느 필사책인가.
    public var notebook: NotebookID
    /// 권 · 장 · 번역본.
    public var chapter: BibleChapter

    public init(notebook: NotebookID, chapter: BibleChapter) {
        self.notebook = notebook
        self.chapter = chapter
    }
}

public extension SharedReaderKey where Self == AppStorageKey<String>.Default {
    /// 지금 필사책의 `NotebookID.rawValue`(UserDefaults · 기기마다, 결정 13).
    ///
    /// - 읽을 때 `NotebookID(rawValue:)` 가 nil 이면(깨진 값) 기본 필사책으로 읽는다. 목록에 없는 필사책(다른 기기에서 지움)도 기본 필사책으로 돌린다.
    /// - iCloud 로 나르지 않는다 — 기기마다 다른 필사책을 펴 둘 수 있다.
    /// ⚠️ `appStorage` 는 키가 없으면 첫 로드 때 기본값을 저장한다 — 기본값을 바꿔도 이미 앱을 연 사용자에게는 닿지 않는다.
    static var currentNotebookID: Self {
        Self[.appStorage("currentNotebookID"), default: NotebookID.default.rawValue]
    }
}
