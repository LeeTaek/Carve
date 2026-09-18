//
//  EraseStateStore.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 삭제 판정 상태를 두는 곳 — `K(기기)` 와 삭제 작업 기록 (정책 §12-6 C11).
///
/// **보존 영역(`PreservationArea`)과 따로 둔다.** 전체 삭제 단계 ④ 는 보존 영역을 지우지만 이 둘은 남겨야 한다 —
/// 완료를 적기 전에 종료돼도 재개할 근거가 있어야 하고, 한 번 안 기준점은 잊으면 안 된다.
public struct EraseStateArea: Equatable, Sendable {
    public let root: URL
    public let storeFileName: String

    public init(root: URL, storeFileName: String) {
        self.root = root
        self.storeFileName = storeFileName
    }

    /// 앱이 쓰는 위치. CloudKit 으로 동기화되지 않는 Application Support 아래다.
    public static func live(localDBPath: String) -> EraseStateArea {
        EraseStateArea(
            root: URL.applicationSupportDirectory.appending(path: "EraseState", directoryHint: .isDirectory),
            storeFileName: localDBPath
        )
    }

    func scopeDirectory(_ scope: String) -> URL {
        root.appendingPathComponent(storeFileName, isDirectory: true).appendingPathComponent(scope, isDirectory: true)
    }
}

/// `K(기기)` 와 삭제 작업 기록의 파일 저장소 (정책 §12-6 C11).
///
/// - `K(기기)` 는 **추가만 한다.** 쓰기는 늘 디스크의 값과 합친 뒤에 한다 — 오래된 값을 들고 있던 쪽이 써도 줄지 않는다.
/// - 판정 · 정리보다 **먼저** 기록하고, 기록한 값(합친 결과)을 돌려준다. 호출부는 그 값으로 판정한다.
/// - 계정 범위마다 따로 둔다. 다른 범위의 값은 읽지도 섞지도 않는다.
public final class FileEraseStateStore: @unchecked Sendable {
    private let area: EraseStateArea
    private let fileManager: FileManager
    /// 같은 프로세스 안의 읽기-합치기-쓰기를 한 줄로 세운다.
    private let lock = NSLock()

    private static let knowledgeFile = "erase-knowledge.json"
    private static let jobFile = "erase-job.json"
    private static let lastConfirmedScopeFile = "last-confirmed-scope.json"

    public init(area: EraseStateArea, fileManager: FileManager = .default) {
        self.area = area
        self.fileManager = fileManager
    }

    // MARK: - K(기기)

    public func knowledge(for scope: AccountScope) throws -> EraseEpochKnowledge {
        lock.lock()
        defer { lock.unlock() }
        return try loadKnowledge(scope)
    }

    /// 기준점 레코드를 받았다.
    @discardableResult
    public func recordReceived(_ epochID: String, knownAtCreation: Set<String>, for scope: AccountScope) throws -> EraseEpochKnowledge {
        try update(scope) { $0.receive(epochID, knownAtCreation: knownAtCreation) }
    }

    /// 레코드의 `K` 에서 참조만 봤다.
    @discardableResult
    public func recordReferenced(_ ids: Set<String>, for scope: AccountScope) throws -> EraseEpochKnowledge {
        try update(scope) { $0.note(referenced: ids) }
    }

    private func update(_ scope: AccountScope, _ change: (inout EraseEpochKnowledge) -> Void) throws -> EraseEpochKnowledge {
        lock.lock()
        defer { lock.unlock() }
        var knowledge = try loadKnowledge(scope)
        change(&knowledge)
        // 다른 인스턴스가 그 사이 더 쓴 값이 있어도 줄지 않게, 쓰기 직전에 한 번 더 합친다.
        let merged = knowledge.merging(try loadKnowledge(scope))
        try write(merged, to: url(scope, Self.knowledgeFile))
        return merged
    }

    private func loadKnowledge(_ scope: AccountScope) throws -> EraseEpochKnowledge {
        try read(EraseEpochKnowledge.self, from: url(scope, Self.knowledgeFile)) ?? EraseEpochKnowledge()
    }

    // MARK: - 마지막으로 확인한 계정 범위

    /// **참고 정보일 뿐이다** — 저장소 내용의 소유를 정하는 근거로 쓰지 않는다(`AccountScopeState.unconfirmed`).
    public func lastConfirmedScope() throws -> AccountScope? {
        lock.lock()
        defer { lock.unlock() }
        return try read(AccountScope.self, from: lastConfirmedScopeURL)
    }

    public func rememberConfirmedScope(_ scope: AccountScope) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(scope, to: lastConfirmedScopeURL)
    }

    private var lastConfirmedScopeURL: URL {
        area.root.appendingPathComponent(area.storeFileName, isDirectory: true).appendingPathComponent(Self.lastConfirmedScopeFile)
    }

    // MARK: - 삭제 작업 기록

    public func job(for scope: AccountScope) throws -> EraseJobRecord? {
        lock.lock()
        defer { lock.unlock() }
        return try read(EraseJobRecord.self, from: url(scope, Self.jobFile))
    }

    /// 작업 기록을 쓴다. 단계 완료 표시는 **실제 작업을 끝낸 뒤에** 이 함수로 적는다.
    public func save(_ job: EraseJobRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(job, to: url(AccountScope(key: job.accountScope), Self.jobFile))
    }

    /// 작업 기록을 지운다. **확실히 실패한 작업(`EraseEpochWriteDecision.discardJob`)에만** 쓴다.
    /// 끝난 작업은 지우지 않고 완료로 남긴다.
    public func discardJob(for scope: AccountScope) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = url(scope, Self.jobFile)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// 끝나지 않은 작업 — 모든 계정 범위에서 찾는다. 이어 할지는 `EraseJobRule.resume` 이 현재 계정으로 정한다.
    public func unfinishedJobs() throws -> [EraseJobRecord] {
        lock.lock()
        defer { lock.unlock() }
        let storeDirectory = area.root.appendingPathComponent(area.storeFileName, isDirectory: true)
        guard fileManager.fileExists(atPath: storeDirectory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent)
            .sorted()
            .compactMap { try read(EraseJobRecord.self, from: url(AccountScope(key: $0), Self.jobFile)) }
            .filter { !$0.isFinished }
    }

    // MARK: - 파일

    private func url(_ scope: AccountScope, _ name: String) -> URL {
        area.scopeDirectory(scope.key).appendingPathComponent(name)
    }

    private func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try DurableFile.write(try encoder.encode(value), to: url)
    }
}
