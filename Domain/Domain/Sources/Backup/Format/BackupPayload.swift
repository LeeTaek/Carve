//
//  BackupPayload.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 풀린 백업 하나 — 디코딩 · 검증을 마친 manifest 와 항목, 그리고 blob 폴더 (설계 §4-1 4단계).
///
/// 이미 풀린 폴더(`BackupArchive.read` 가 돌려준 루트)에서 **읽기만** 한다. 암호 · 컨테이너는 모른다.
public struct BackupPayload: Codable, Equatable, Sendable {
    /// 검증을 마친 manifest.
    public let manifest: BackupManifest
    /// 검증을 마친 항목 목록(`items.json` 순서 그대로).
    public let items: [BackupItem]
    /// `blobs/` 폴더. blob 은 `blobDirectory/<name>` 이다.
    public let blobDirectory: URL

    /// 값을 그대로 묶는다(검증하지 않는다 — 파일에서 읽을 때는 `load(rootDirectory:limits:)` 를 쓴다).
    public init(manifest: BackupManifest, items: [BackupItem], blobDirectory: URL) {
        self.manifest = manifest
        self.items = items
        self.blobDirectory = blobDirectory
    }

    /// 풀린 루트에서 `manifest.json` · `items.json` 을 디코딩하고 `BackupPayloadValidator.validate` 로 검증한다.
    /// - Parameters:
    ///   - rootDirectory: 풀린 루트(`manifest.json` · `items.json` · `blobs/` 가 있는 폴더).
    ///   - limits: 상한.
    /// - Returns: 검증을 마친 payload.
    /// - Throws: `BackupFormatError` — 형식 버전이 다르면 `unsupportedFormat`, 파일이 없거나 디코딩되지 않으면 `malformed`,
    ///   색인 파일이 `maxIndexBytes` 를 넘으면 `limitExceeded(.indexBytes)`, 그 밖은 검증 오류.
    ///   부작용 없음(파일을 읽기만 한다).
    public static func load(rootDirectory: URL, limits: BackupLimits) throws -> BackupPayload {
        // manifest 를 먼저 읽는다 — 형식 버전이 다르면 items 의 모양을 보기 전에 거부한다.
        let manifest = try decode(BackupManifest.self, in: rootDirectory, fileName: BackupFormat.manifestFileName, limits: limits)
        let items = try decode([BackupItem].self, in: rootDirectory, fileName: BackupFormat.itemsFileName, limits: limits)
        let blobDirectory = rootDirectory.appendingPathComponent(BackupFormat.blobDirectoryName, isDirectory: true)
        try BackupPayloadValidator.validate(manifest: manifest, items: items, blobDirectory: blobDirectory, limits: limits)
        return BackupPayload(manifest: manifest, items: items, blobDirectory: blobDirectory)
    }

    /// blob 파일의 위치.
    public func blobURL(named name: String) -> URL {
        Self.blobURL(named: name, in: blobDirectory)
    }

    /// blob 바이트를 읽는다(검증을 마친 뒤 복원 · 판정이 쓴다).
    /// - Throws: 파일이 없으면 `BackupFormatError.missingBlob`.
    public func blob(named name: String) throws -> Data {
        do {
            return try Data(contentsOf: blobURL(named: name))
        } catch {
            throw BackupFormatError.missingBlob(name: name)
        }
    }

    /// `blobDirectory/<name>`.
    static func blobURL(named name: String, in blobDirectory: URL) -> URL {
        blobDirectory.appendingPathComponent(name, isDirectory: false)
    }

    /// JSON 파일 하나를 상한(`maxIndexBytes`) 안에서 읽어 디코딩한다. 형식 오류(`BackupFormatError`)는 그대로, 그 밖의 디코딩 실패는 `malformed` 로 바꾼다.
    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        in rootDirectory: URL,
        fileName: String,
        limits: BackupLimits
    ) throws -> Value {
        let data = try BackupPayloadValidator.readIndexFile(named: fileName, in: rootDirectory, limits: limits)
        do {
            return try BackupFormat.decoder.decode(type, from: data)
        } catch let error as BackupFormatError {
            throw error
        } catch {
            throw BackupFormatError.malformed(fileName: fileName)
        }
    }
}
