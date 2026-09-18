//
//  LocalPreservationWriter.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Dependencies
import Foundation

/// 초안 하나를 가리키는 키 — 세션 · 번역 · 권 · 장 · 절 (정책 §12-6 구현 순서 ②).
public struct VerseDraftKey: Hashable, Codable, Sendable {
    public var sessionID: String
    public var translation: String
    public var title: String
    public var chapter: Int
    public var verse: Int

    public init(sessionID: String, translation: Translation = .NKRV, chapter: BibleChapter, verse: Int) {
        self.sessionID = sessionID
        self.translation = translation.rawValue
        self.title = chapter.title.rawValue
        self.chapter = chapter.chapter
        self.verse = verse
    }

    /// 파일 이름. 구성요소에 경로 구분자가 들어오지 않게 바꾼다.
    var fileName: String {
        [translation, title, "\(chapter)", "\(verse)"]
            .map { $0.replacingOccurrences(of: "/", with: "_") }
            .joined(separator: "~") + ".json"
    }
}

/// 절 하나의 초안 — 그 절의 **완전한** 획 집합과, 그것을 쓴 편집 문맥의 근거를 함께 든다.
public struct VerseDraft: Codable, Equatable, Sendable {
    public var key: VerseDraftKey
    public var revision: Int
    public var lineData: Data?
    public var drawingVersion: Int?
    public var layoutMetadataData: Data?
    /// 편집을 시작할 때 보던 기준과 그 내용 지문. 다시 열 때 저장소의 내용이 이 기준과 같을 때만 이어서 보여 준다.
    public var base: VerseEditBase
    public var baseFingerprint: String?
    public var account: VerseEditAccountBasis
    public var knownEpochs: Set<String>?
    public var storeOwnership: AccountScope?
    /// 이 초안이 기댄 로컬 삭제 세대. 그 뒤 전체 삭제가 있었으면 쓰지 않는다.
    public var eraseGeneration: UInt64
    public var savedAt: Date

    public init(
        key: VerseDraftKey,
        revision: Int,
        lineData: Data?,
        drawingVersion: Int?,
        layoutMetadataData: Data?,
        base: VerseEditBase,
        baseFingerprint: String?,
        account: VerseEditAccountBasis,
        knownEpochs: Set<String>?,
        storeOwnership: AccountScope?,
        eraseGeneration: UInt64,
        savedAt: Date
    ) {
        self.key = key
        self.revision = revision
        self.lineData = lineData
        self.drawingVersion = drawingVersion
        self.layoutMetadataData = layoutMetadataData
        self.base = base
        self.baseFingerprint = baseFingerprint
        self.account = account
        self.knownEpochs = knownEpochs
        self.storeOwnership = storeOwnership
        self.eraseGeneration = eraseGeneration
        self.savedAt = savedAt
    }
}

public extension VerseEditAccountBasis {
    /// 이 근거로 만든 로컬 보존의 묶음. 확인된 계정이면 그 계정 범위, 아니면 "계정 미확인" · "이 기기 전용" 묶음이다.
    var preservationScope: AccountScope {
        switch self {
        case .confirmed(let token): token.scope
        case .unverified: .unverified
        case .localOnly: .localOnly
        }
    }
}

/// 이 기기의 비동기화 보존 쓰기(초안 · 격리본)와 전체 삭제를 **한 줄로 세우는 곳** (정책 §12-6 구현 순서 ②).
///
/// - 모든 쓰기는 요청이 기댄 **로컬 삭제 세대**를 들고 온다. 세대 검사와 파일 반영 사이에 `await` 를 두지 않는다 — actor 는 `await`
///   사이에 재진입하므로, 검사와 쓰기를 한 동기 구간에서 한다. 전체 삭제 뒤의 늦은 쓰기는 거절된다.
/// - 삭제 세대는 메모리가 아니라 파일에 남는다(`EraseStateArea` — 전체 삭제가 지우지 않는 곳). 재시작 뒤의 늦은 쓰기도 거절한다.
/// - 전체 삭제는 **세대를 먼저 올리고 → 보존 폴더를 한 번에 옮긴 뒤 지운다.** 중간에 끊겨 남은 폴더는 표식의 세대가 낮아 다음 실행에서
///   지운다.
public actor LocalPreservationWriter {
    public enum WriteOutcome: Equatable, Sendable {
        case written
        /// 요청이 기댄 세대 뒤에 전체 삭제가 있었다. 쓰지 않았다.
        case rejectedByErase(current: UInt64)
    }

    public enum WriterError: Error, Equatable {
        /// 삭제 세대를 읽지 못했다. 늦은 쓰기를 가려낼 수 없으므로 쓰지 않는다.
        case generationUnreadable(String)
    }

    private static let generationFile = "local-erase-generation.json"
    private static let markerFile = "local-generation.json"
    private static let trashPrefix = ".erasing-"

    private let area: PreservationArea
    private let generationURL: URL
    private let fileManager: FileManager
    private var generation: UInt64?
    private let now: @Sendable () -> Date

    public init(area: PreservationArea, eraseState: EraseStateArea, fileManager: FileManager = .default,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.area = area
        self.generationURL = eraseState.root.appendingPathComponent(eraseState.storeFileName, isDirectory: true)
            .appendingPathComponent(Self.generationFile)
        self.fileManager = fileManager
        self.now = now
        let loaded = Self.loadGeneration(at: generationURL, fileManager: fileManager)
        self.generation = loaded
        Self.removeTrash(in: area.root, fileManager: fileManager)
        if let loaded {
            Self.removeLeftover(area: area, generation: loaded, fileManager: fileManager)
        }
    }

    /// 지금 로컬 삭제 세대. 읽지 못했으면 nil — 그동안 쓰기는 거절된다.
    public func currentGeneration() -> UInt64? {
        generation
    }

    // MARK: - 초안

    /// 초안을 저장한다. 같은 키에 더 새 revision 이 이미 있으면 덮지 않는다(늦게 도착한 옛 쓰기).
    public func saveDraft(_ draft: VerseDraft) throws -> WriteOutcome {
        let current = try requireGeneration()
        guard draft.eraseGeneration == current else { return .rejectedByErase(current: current) }
        try stampLiveDirectory(current)
        let url = draftURL(draft.key, scope: draft.account.preservationScope)
        if let existing = try? readDraft(at: url), existing.revision > draft.revision {
            return .written
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try DurableFile.write(try encoder.encode(draft), to: url)
        return .written
    }

    /// 확정 · 격리를 마친 초안을 지운다. **그 revision 일 때만** 지운다 — 그 사이 더 새 편집이 저장됐으면 남긴다.
    public func removeDraft(_ key: VerseDraftKey, scope: AccountScope, ifRevision revision: Int) throws {
        let url = draftURL(key, scope: scope)
        guard let existing = try? readDraft(at: url), existing.revision == revision else { return }
        try fileManager.removeItem(at: url)
    }

    /// 한 묶음의 초안들. 지금 세대의 것만 준다.
    public func drafts(in scope: AccountScope) throws -> [VerseDraft] {
        let current = try requireGeneration()
        let root = area.draftsDirectory.appendingPathComponent(scope.key, isDirectory: true)
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" }
            .compactMap { try? readDraft(at: $0) }
            .filter { $0.eraseGeneration == current }
            .sorted { ($0.key.sessionID, $0.key.chapter, $0.key.verse) < ($1.key.sessionID, $1.key.chapter, $1.key.verse) }
    }

    // MARK: - 격리

    /// 무효가 된 편집 세션의 미저장분을 격리본으로 남긴다. 세션이 기댄 세대 뒤에 전체 삭제가 있었으면 쓰지 않는다.
    public func quarantine(
        _ items: [DrawingQuarantineItem],
        environment: DrawingEditEnvironment,
        batchID: String,
        deviceID: String
    ) throws -> WriteOutcome {
        let current = try requireGeneration()
        guard environment.eraseGeneration == current else { return .rejectedByErase(current: current) }
        try stampLiveDirectory(current)
        try FileDrawingQuarantine.write(
            items, environment: environment, batchID: batchID, deviceID: deviceID,
            store: FileRecoveryCopyStore(root: area.recoveryCopiesDirectory, fileManager: fileManager), now: now()
        )
        return .written
    }

    // MARK: - 전체 삭제

    /// 이 기기의 보존 영역(원시 사본 · 복구 사본 · 격리본 · 초안)을 지운다. **사용자가 이 기기에서 전체 삭제를 요청했을 때만** 부른다.
    /// - Returns: 올린 뒤의 세대.
    @discardableResult
    public func eraseAllLocal() throws -> UInt64 {
        let next = try requireGeneration() + 1
        // ★ 세대를 먼저 올린다 — 폴더를 지우다 끊겨도 남은 것은 표식의 세대가 낮아 다음 실행에서 지워진다.
        try writeGeneration(next)
        generation = next
        try Self.moveToTrashAndDelete(area.storeDirectory, root: area.root, fileManager: fileManager)
        return next
    }

    // MARK: - 파일

    private func requireGeneration() throws -> UInt64 {
        guard let generation else { throw WriterError.generationUnreadable(generationURL.lastPathComponent) }
        return generation
    }

    private func writeGeneration(_ value: UInt64) throws {
        try fileManager.createDirectory(at: generationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DurableFile.write(try JSONEncoder().encode(value), to: generationURL)
    }

    /// 보존 폴더에 지금 세대 표식을 붙인다. 표식이 없으면(첫 실행 · 원시 사본만 있음) 지금 세대로 붙이고, 낮으면 지난 삭제의 잔여다.
    private func stampLiveDirectory(_ current: UInt64) throws {
        let marker = area.storeDirectory.appendingPathComponent(Self.markerFile)
        if let stamped = Self.readMarker(at: marker, fileManager: fileManager) {
            guard stamped < current else { return }
            try Self.moveToTrashAndDelete(area.storeDirectory, root: area.root, fileManager: fileManager)
        }
        try fileManager.createDirectory(at: area.storeDirectory, withIntermediateDirectories: true)
        try DurableFile.write(try JSONEncoder().encode(current), to: marker)
    }

    private func draftURL(_ key: VerseDraftKey, scope: AccountScope) -> URL {
        area.draftsDirectory
            .appendingPathComponent(scope.key, isDirectory: true)
            .appendingPathComponent(key.sessionID, isDirectory: true)
            .appendingPathComponent(key.fileName)
    }

    private func readDraft(at url: URL) throws -> VerseDraft {
        try JSONDecoder().decode(VerseDraft.self, from: Data(contentsOf: url))
    }

    private static func loadGeneration(at url: URL, fileManager: FileManager) -> UInt64? {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        do {
            return try JSONDecoder().decode(UInt64.self, from: Data(contentsOf: url))
        } catch {
            Log.error("로컬 보존 — 삭제 세대를 읽지 못했다. 쓰기를 멈춘다", "\(error)")
            return nil
        }
    }

    private static func readMarker(at url: URL, fileManager: FileManager) -> UInt64? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(UInt64.self, from: Data(contentsOf: url))
    }

    /// 지난 삭제가 끝내지 못한 보존 폴더(표식의 세대가 지금보다 낮음)를 지운다.
    private static func removeLeftover(area: PreservationArea, generation: UInt64, fileManager: FileManager) {
        let marker = area.storeDirectory.appendingPathComponent(markerFile)
        guard let stamped = readMarker(at: marker, fileManager: fileManager), stamped < generation else { return }
        do {
            try moveToTrashAndDelete(area.storeDirectory, root: area.root, fileManager: fileManager)
        } catch {
            Log.error("로컬 보존 — 지난 전체 삭제의 잔여를 지우지 못했다", "\(error)")
        }
    }

    private static func removeTrash(in root: URL, fileManager: FileManager) {
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for child in children where child.lastPathComponent.hasPrefix(trashPrefix) {
            try? fileManager.removeItem(at: child)
        }
    }

    /// 폴더를 같은 부모 안의 휴지통 이름으로 한 번에 옮긴 뒤 지운다. 옮기기는 원자적이라 반쯤 지운 폴더가 제자리에 남지 않는다.
    private static func moveToTrashAndDelete(_ directory: URL, root: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let trash = root.appendingPathComponent(trashPrefix + UUID().uuidString, isDirectory: true)
        try fileManager.moveItem(at: directory, to: trash)
        try? fileManager.removeItem(at: trash)
    }
}

private enum LocalPreservationWriterKey: DependencyKey {
    /// 앱이 주입한다. 없으면 초안 · 격리를 쓸 수 없다 — 호출부는 미저장분을 지킨 채 실패로 둔다.
    static let liveValue: LocalPreservationWriter? = nil
    static let testValue: LocalPreservationWriter? = nil
}

public extension DependencyValues {
    /// 이 기기의 비동기화 보존 쓰기와 전체 삭제의 직렬화 경계.
    var localPreservationWriter: LocalPreservationWriter? {
        get { self[LocalPreservationWriterKey.self] }
        set { self[LocalPreservationWriterKey.self] = newValue }
    }
}
