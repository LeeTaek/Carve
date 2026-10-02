//
//  BackupFormat.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// 필사 백업 파일(`.carvebackup`)의 형식 상수와 JSON 인코딩 규칙 (설계 `docs/backup-import-design.md` §2-1 · §2-2).
///
/// 컨테이너(Apple Encrypted Archive)는 `BackupArchive` 가 다루고, 이 타입은 그 안의 이름 · JSON 규칙만 정한다.
public enum BackupFormat {
    /// 백업 형식 버전. 앱 버전 · 스키마 버전과 별개다(정책 §6-3). 읽을 때 이 값이 아니면 파일 전체를 거부한다.
    public static let formatVersion = 1
    /// 파일 확장자.
    public static let fileExtension = "carvebackup"
    /// 내보내는 형식 식별자 — 앱 Info.plist 의 `UTExportedTypeDeclarations` 와 짝이다.
    public static let typeIdentifier = "kr.co.carve.leetaek.backup"

    /// 아카이브 안 manifest 이름.
    public static let manifestFileName = "manifest.json"
    /// 아카이브 안 항목 목록 이름.
    public static let itemsFileName = "items.json"
    /// 아카이브 안 blob 폴더 이름. blob 경로는 `blobs/<소문자 SHA-256 hex 64자>` 다.
    public static let blobDirectoryName = "blobs"

    /// 백업 JSON 인코더 — 키를 정렬해 같은 내용이면 같은 바이트가 되고, 날짜는 2001-01-01 기준 초(Double)로 손실 없이 왕복한다.
    ///
    /// 부를 때마다 새로 만든다(인코더는 설정을 가진 참조 타입이라 공유하지 않는다).
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    /// 백업 JSON 디코더 — 날짜는 인코더와 같은 기준이다. 모르는 키는 무시한다(뒤 버전이 키를 더해도 읽힌다).
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    /// 바이트의 SHA-256 소문자 hex 64자 — blob 이름이자 manifest 의 `sha256` 이다.
    /// - Parameter data: blob 원본 바이트.
    /// - Returns: 소문자 hex 64자. 부작용 없음.
    public static func sha256Hex(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    /// blob 이름 형식인가 — 소문자 hex(`0-9` · `a-f`) 정확히 64자.
    ///
    /// 경로 구분자 · `..` · 대문자를 모두 거른다. 이름이 곧 파일 이름이라 이 검사가 경로 이탈도 막는다.
    public static func isBlobName(_ name: String) -> Bool {
        let utf8 = name.utf8
        guard utf8.count == 64 else { return false }
        return utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }

    /// 다이제스트를 소문자 hex 로 바꾼다.
    static func hex<Digest: Sequence>(_ digest: Digest) -> String where Digest.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

public extension UTType {
    /// 필사 백업 파일 형식(`kr.co.carve.leetaek.backup`, `public.data` · `public.content` 준수 — 준수 목록의 원본은 앱 Info.plist 선언이다).
    ///
    /// `fileImporter(allowedContentTypes: [.carveBackup])` · `fileExporter` 가 쓴다.
    static let carveBackup = UTType(exportedAs: BackupFormat.typeIdentifier, conformingTo: .data)
}
