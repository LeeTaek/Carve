//
//  BackupArchiveEntry.swift
//  Domain
//
//  백업 파일 안 항목 이름 규칙 — manifest.json · items.json · blobs/<소문자 SHA-256 hex 64자> 뿐이다(설계 §2-1 · §2-7).
//  쓰기(준비 폴더 검사)와 풀기(아카이브 헤더 검사)가 같은 규칙을 쓴다.
//

import AppleArchive

/// 아카이브 안 항목 하나. 이 넷 밖의 이름은 만들지도 풀지도 않는다.
enum BackupArchiveEntry: Hashable, Sendable {
    /// `manifest.json`
    case manifest
    /// `items.json`
    case items
    /// `blobs` 폴더
    case blobDirectory
    /// `blobs/<소문자 SHA-256 hex 64자>` — 값은 이름(64자)이다.
    case blob(String)

    static let manifestPath = "manifest.json"
    static let itemsPath = "items.json"
    static let blobDirectoryPath = "blobs"
    /// blob 이름의 길이(SHA-256 hex)
    static let blobNameLength = 64

    /// 아카이브 안 경로 원문을 UTF-8 바이트 그대로 견줘 해석한다.
    /// 허용 밖(다른 이름 · `..` · 절대 경로 · 겹친 `/` · 대문자 hex · 길이가 다른 이름)이면 nil.
    init?(path: String) {
        let bytes = Array(path.utf8)
        switch bytes {
        case Array(Self.manifestPath.utf8):
            self = .manifest
        case Array(Self.itemsPath.utf8):
            self = .items
        case Array(Self.blobDirectoryPath.utf8):
            self = .blobDirectory
        default:
            let prefix = Array((Self.blobDirectoryPath + "/").utf8)
            let name = bytes.dropFirst(prefix.count)
            guard bytes.starts(with: prefix), Self.isBlobName(name) else { return nil }
            // 남은 바이트가 모두 ASCII 라 문자 수와 바이트 수가 같다.
            self = .blob(String(path.dropFirst(prefix.count)))
        }
    }

    /// 아카이브 안 경로 — 풀 폴더 기준 상대 경로이기도 하다.
    var path: String {
        switch self {
        case .manifest: Self.manifestPath
        case .items: Self.itemsPath
        case .blobDirectory: Self.blobDirectoryPath
        case .blob(let name): Self.blobDirectoryPath + "/" + name
        }
    }

    /// 폴더 항목인가(`blobs` 하나뿐)
    var isDirectory: Bool { self == .blobDirectory }

    /// 쓰는 순서 — manifest.json → items.json → blobs → blobs/* 이름순.
    var writeOrder: (Int, String) {
        switch self {
        case .manifest: (0, "")
        case .items: (1, "")
        case .blobDirectory: (2, "")
        case .blob(let name): (3, name)
        }
    }

    /// blob 이름 규칙 — 소문자 hex(0-9 · a-f) 64자.
    static func isBlobName<Bytes: Collection>(_ bytes: Bytes) -> Bool where Bytes.Element == UInt8 {
        bytes.count == blobNameLength && bytes.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}

/// 헤더 필드 키 — 이 형식은 TYP(종류) · PAT(경로) · DAT(바이트)만 쓴다.
/// `FieldKey` 가 Sendable 이 아니라 저장 프로퍼티 대신 계산 프로퍼티로 둔다(concurrency.md 관례 2).
enum BackupArchiveField {
    /// 항목 종류
    static var type: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("TYP") }
    /// 항목 경로
    static var path: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("PAT") }
    /// 파일 바이트(blob)
    static var data: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("DAT") }
}
