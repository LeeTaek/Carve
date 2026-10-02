//
//  BackupFormatError.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 백업 형식 · 검증 오류 — 모두 **파일 전체**를 거부한다 (설계 §4-2).
///
/// 항목 하나만 해석할 수 없는 경우(모르는 번역본 · 권 · 범위 밖 장 · 절 · 좌표 형식 · 풀리지 않는 메타데이터)는 오류가 아니라
/// `BackupItemSupport.reason` 의 `BackupUnsupportedReason` 으로 그 항목만 건너뛴다.
public enum BackupFormatError: Error, Equatable, Sendable {
    /// 넘은 상한.
    public enum Limit: String, Equatable, Sendable {
        /// 항목 수.
        case items
        /// blob 하나의 크기.
        case blobBytes
        /// blob 합계 크기.
        case totalBytes
        /// `manifest.json` · `items.json` 하나의 크기.
        case indexBytes
    }

    /// 무결성 오류의 종류.
    public enum Integrity: String, Equatable, Sendable {
        /// 같은 id 의 항목이 다른 `fingerprint` 를 든다.
        case conflictingFingerprint
        /// blob 바이트로 다시 계산한 내용 지문이 항목 `fingerprint` 와 다르다(잉크 없는 항목의 지문이 nil 이 아닌 것도 여기).
        case fingerprintMismatch
    }

    /// `formatVersion` 이 `BackupFormat.formatVersion` 이 아니다.
    case unsupportedFormat(formatVersion: Int)
    /// `manifest.json` · `items.json` 이 없거나 읽지 못했거나 디코딩되지 않는다.
    case malformed(fileName: String)
    /// 상한을 넘었다.
    case limitExceeded(Limit)
    /// manifest `counts` 가 실제 항목 · blob 수와 다르다.
    case countsMismatch
    /// blob 이름이 64자 소문자 hex 가 아니거나, manifest 항목의 `name` 과 `sha256` 이 다르거나, 크기가 음수다.
    case invalidBlobEntry(name: String)
    /// manifest 에 같은 blob 이 두 번 있다.
    case duplicateBlob(name: String)
    /// 항목이 manifest 에 없는 blob 을 가리키거나, manifest 의 blob 파일이 없다.
    case missingBlob(name: String)
    /// 어느 항목도 가리키지 않는 blob 이 manifest 에 있다(설계 §2-7).
    case unreferencedBlob(name: String)
    /// blob 파일의 실제 크기가 manifest 와 다르다.
    case blobSizeMismatch(name: String)
    /// blob 파일의 실제 SHA-256 이 manifest 와 다르다.
    case blobHashMismatch(name: String)
    /// 같은 id · 같은 내용의 항목이 둘 이상이다.
    case duplicateItemID(String)
    /// 무결성 오류 — 같은 id 다른 지문, 또는 blob 으로 다시 계산한 지문이 다르다.
    case integrity(itemID: String, Integrity)
}
