//
//  BackupManifest.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 백업의 `manifest.json` (설계 §2-3).
///
/// **넣지 않는 것:** 계정 식별자 · 계정 해시(`AccountScope`) · 기기 이름 · 설정 · 즐겨찾기 · 위젯 · 구매 상태 · CloudKit 메타데이터.
/// 불러오기의 대상 계정 범위(`targetScope`)도 파일에는 없고 기기 안 작업 기록에만 있다.
public struct BackupManifest: Codable, Equatable, Sendable {
    /// 백업 형식 버전(`BackupFormat.formatVersion`). 디코딩할 때 1 이 아니면 `unsupportedFormat` 으로 거부한다.
    public var formatVersion: Int
    /// 이 백업의 UUID 문자열.
    public var backupID: String
    /// 만든 시각.
    public var createdAt: Date
    /// 만든 앱 버전(예: `2.1.0`).
    public var appVersion: String
    /// 무엇을 담았는가 — 선택 백업의 자리(정책 §9-2). 2.1 은 둘 다 true 다.
    public var scope: BackupScope
    /// 행 · 초안 · blob 의 수. 읽을 때 실제 수와 맞아야 한다.
    public var counts: BackupCounts
    /// blob 목록. 읽을 때 실제 크기 · 해시가 맞아야 한다.
    public var blobs: [BackupBlobEntry]

    /// manifest 를 만든다.
    public init(
        formatVersion: Int = BackupFormat.formatVersion,
        backupID: String,
        createdAt: Date,
        appVersion: String,
        scope: BackupScope,
        counts: BackupCounts,
        blobs: [BackupBlobEntry]
    ) {
        self.formatVersion = formatVersion
        self.backupID = backupID
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.scope = scope
        self.counts = counts
        self.blobs = blobs
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, backupID, createdAt, appVersion, scope, counts, blobs
    }

    /// 형식 버전을 **먼저** 읽는다 — 다른 버전은 나머지 모양이 달라도 `unsupportedFormat` 으로 거부한다(디코딩 실패로 보이지 않게).
    /// 모르는 키는 무시한다.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .formatVersion)
        guard version == BackupFormat.formatVersion else {
            throw BackupFormatError.unsupportedFormat(formatVersion: version)
        }
        self.formatVersion = version
        self.backupID = try container.decode(String.self, forKey: .backupID)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.appVersion = try container.decode(String.self, forKey: .appVersion)
        self.scope = try container.decode(BackupScope.self, forKey: .scope)
        self.counts = try container.decode(BackupCounts.self, forKey: .counts)
        self.blobs = try container.decode([BackupBlobEntry].self, forKey: .blobs)
    }
}

/// 백업이 담은 범위 (설계 §2-3).
public struct BackupScope: Codable, Equatable, Sendable {
    /// `BibleDrawing` 행을 담았는가.
    public var rows: Bool
    /// 저장소에 반영되지 않은 초안을 담았는가.
    public var drafts: Bool

    /// 범위를 만든다.
    public init(rows: Bool, drafts: Bool) {
        self.rows = rows
        self.drafts = drafts
    }
}

/// manifest 의 수 — 읽을 때 items · blobs 의 실제 수와 맞아야 한다 (설계 §2-3).
public struct BackupCounts: Codable, Equatable, Sendable {
    /// `kind = "row"` 항목 수.
    public var rows: Int
    /// `kind = "draft"` 항목 수.
    public var drafts: Int
    /// manifest `blobs` 의 수.
    public var blobs: Int

    /// 수를 만든다.
    public init(rows: Int, drafts: Int, blobs: Int) {
        self.rows = rows
        self.drafts = drafts
        self.blobs = blobs
    }
}

/// blob 하나 (설계 §2-7). `name` 과 `sha256` 은 같은 값(바이트의 소문자 SHA-256 hex 64자)이다.
public struct BackupBlobEntry: Codable, Equatable, Sendable {
    /// 아카이브 경로 `blobs/<name>` 의 이름.
    public var name: String
    /// 바이트 수.
    public var size: Int
    /// 바이트의 소문자 SHA-256 hex 64자.
    public var sha256: String

    /// 값을 그대로 지정해 만든다(디코딩 · 시험).
    public init(name: String, size: Int, sha256: String) {
        self.name = name
        self.size = size
        self.sha256 = sha256
    }

    /// 바이트에서 이름 · 크기 · 해시를 만든다 — 내보내기가 blob 을 쓸 때의 단일 진입점.
    /// - Parameter bytes: blob 원본 바이트.
    public init(bytes: Data) {
        let digest = BackupFormat.sha256Hex(bytes)
        self.init(name: digest, size: bytes.count, sha256: digest)
    }
}
