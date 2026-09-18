//
//  DrawingQuarantine.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CryptoKit
import Dependencies
import Foundation

/// 격리할 절 필기 하나 — 무효가 된 편집 세션의 미저장분이다 (정책 §12-6 구현 순서 ①).
public struct DrawingQuarantineItem: Equatable, Sendable {
    public var chapter: BibleChapter
    public var verse: Int
    /// 이 내용을 만든 편집의 revision. 격리본 ID 에 들어가 **재시도해도 같은 항목**이 된다.
    public var revision: Int
    /// 그 절의 **완전한** 획 집합. 절을 비운 편집이면 nil 이다.
    public var lineData: Data?
    public var drawingVersion: Int?
    public var layoutMetadataData: Data?

    public init(chapter: BibleChapter, verse: Int, revision: Int, lineData: Data?, drawingVersion: Int?, layoutMetadataData: Data?) {
        self.chapter = chapter
        self.verse = verse
        self.revision = revision
        self.lineData = lineData
        self.drawingVersion = drawingVersion
        self.layoutMetadataData = layoutMetadataData
    }
}

/// 격리본 blob 의 형식 — **내용만** 담는다. 같은 내용 지문이면 같은 blob 이어야 복구 사본 저장소가 공유할 수 있다.
/// 어느 절 · 어느 계정의 것인지는 항목(`RecoveryCopyEntry`)이 든다.
public struct QuarantinedVerseContent: Codable, Equatable, Sendable {
    public var lineData: Data?
    public var drawingVersion: Int?
    public var layoutMetadataData: Data?
}

public protocol DrawingQuarantineClient: Sendable {
    /// 무효가 된 편집 세션의 미저장분을 격리본으로 남긴다. **돌아오면 내구성 있게 저장돼 있어야 한다** — 호출부는 그 뒤에만 화면을 정리한다.
    /// - Parameters:
    ///   - environment: 무효가 된 **세션의** 환경. 격리본은 만들 당시의 계정 범위 · K 를 든다.
    ///   - batchID: 닫는 세션의 ID. 같은 세션 · 절 · revision 이면 같은 격리본이다 — 일부만 저장하고 실패한 뒤 다시 해도 늘지 않는다.
    func quarantine(_ items: [DrawingQuarantineItem], environment: DrawingEditEnvironment, batchID: String) async throws
}

/// 복구 사본 저장소에 `.quarantined` 로 남기는 구현.
public struct FileDrawingQuarantine: DrawingQuarantineClient {
    private let store: FileRecoveryCopyStore
    private let deviceID: String
    private let now: @Sendable () -> Date

    public init(store: FileRecoveryCopyStore, deviceID: String, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.deviceID = deviceID
        self.now = now
    }

    public func quarantine(_ items: [DrawingQuarantineItem], environment: DrawingEditEnvironment, batchID: String) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for item in items {
            let content = QuarantinedVerseContent(
                lineData: item.lineData, drawingVersion: item.drawingVersion, layoutMetadataData: item.layoutMetadataData
            )
            let entry = RecoveryCopyEntry(
                entryID: Self.entryID(batchID: batchID, item: item),
                kind: .version,
                classification: .quarantined,
                accountScope: environment.accountState.scopeForLocalPreservation.key,
                verseKey: Self.verseKey(chapter: item.chapter, verse: item.verse),
                contentFingerprint: VerseContentFingerprint.make(
                    lineData: item.lineData, drawingVersion: item.drawingVersion, layoutMetadataBlob: item.layoutMetadataData
                ),
                drawingVersion: item.drawingVersion,
                // 세션의 K 를 읽지 못했으면 빈 집합으로 적는다. 격리본은 판정에 쓰지 않고, 사용자가 되살릴 때 그 시점 K 로 새 버전을 만든다.
                knownEpochs: environment.knowledge?.all ?? [],
                createdAt: now(),
                deviceID: deviceID
            )
            try store.save(entry, blob: try encoder.encode(content))
        }
    }

    /// 격리본 ID — 세션 · 권 · 장 · 절 · revision 이 같으면 같다. 구성요소 길이를 앞에 붙여 경계를 고정한다.
    static func entryID(batchID: String, item: DrawingQuarantineItem) -> String {
        let canonical = ["carve.quarantine/1", batchID, item.chapter.title.rawValue, "\(item.chapter.chapter)", "\(item.verse)", "\(item.revision)"]
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        return "quarantine-" + SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 절 키. 지금의 저장 경로는 번역본을 기록하지 않아(`BibleDrawing.translation` 기본값) 개역개정(NKRV)으로 적는다.
    public static func verseKey(chapter: BibleChapter, verse: Int) -> String {
        "\(Translation.NKRV.rawValue)/\(chapter.title.rawValue)/\(chapter.chapter)/\(verse)"
    }
}

public struct UnavailableDrawingQuarantine: DrawingQuarantineClient {
    public struct NotConfigured: Error {}

    public init() {}

    /// 주입하지 않았다 — 격리하지 못한 것으로 알린다. 호출부는 화면을 정리하지 않고 미저장분을 지킨다.
    public func quarantine(_ items: [DrawingQuarantineItem], environment: DrawingEditEnvironment, batchID: String) async throws {
        throw NotConfigured()
    }
}

private enum DrawingQuarantineKey: DependencyKey {
    /// 앱이 `FileDrawingQuarantine` 을 주입한다.
    static let liveValue: any DrawingQuarantineClient = UnavailableDrawingQuarantine()
    static let testValue: any DrawingQuarantineClient = UnavailableDrawingQuarantine()
}

public extension DependencyValues {
    /// 무효가 된 편집 세션의 미저장분 격리.
    var drawingQuarantine: any DrawingQuarantineClient {
        get { self[DrawingQuarantineKey.self] }
        set { self[DrawingQuarantineKey.self] = newValue }
    }
}
