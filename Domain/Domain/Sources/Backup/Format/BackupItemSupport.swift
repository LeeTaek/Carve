//
//  BackupItemSupport.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 항목 하나를 이 앱이 해석할 수 없는 이유 (설계 §5-1 `unsupported`). 파일은 거부하지 않고 그 항목만 건너뛰고 사유별 수로 알린다.
public enum BackupUnsupportedReason: String, Codable, Hashable, Sendable, CaseIterable {
    /// 번역본이 nil 도 아니고 `Translation` 의 값(`NKRV` · `KJV` · `BSB`)도 아니다(예: `"ESV"`).
    case unknownTranslation
    /// 권 코드가 `BibleBookCode` 에 없다.
    case unknownBook
    /// 장이 `1...권.lastChapter` 밖이거나 절이 1 미만이다. 절의 상한은 본문을 읽어야 해 보지 않는다.
    case outOfRange
    /// `drawingVersion` 이 nil · 1 · 2 · 3 밖이다.
    case unknownDrawingVersion
    /// `drawingVersion` 3 이고 잉크가 있으며 메타데이터 blob 이 **있는데** `DrawingLayoutMetadata.decode` 로 풀리지 않는다(뒤 버전의
    /// `metadataSchemaVersion` 일 수 있다 — 정책 §6-2). 메타데이터 blob 이 없는 v3 잉크 항목은 지원한다.
    case undecodableMetadata
}

/// 항목별 지원 판정 (설계 §5-1 — 판정 순서의 첫 단계).
///
/// **비운 항목(잉크 없음)은 지원 밖이 아니다** — 판정기(`BackupImportPlanner`)가 비운 항목 규칙으로 다룬다. 그래서 메타데이터 해석은
/// 잉크가 있는 v3 항목에만 요구한다. 그중에서도 메타데이터 blob 이 **없는** v3 잉크 항목은 지원한다 — 내보내기가 원본 그대로 담은 행이고
/// `DrawingCodec` 이 이미 첫 밑줄(`storageOrigin`) 기준으로 보여 주는 상태라, 건너뛰면 필기를 잃는다.
///
/// 한계: 절 번호는 1 이상인지만 본다. 그 장의 마지막 절은 본문(`BibleText`)을 읽어야 알 수 있어 이 판정(파일 · 본문을 모르는 순수 규칙)에서 보지 않는다.
///
/// **알 수 없는 필사책(형식 2)** — 절 키의 필사책 토큰이 `NotebookID` 형식이 아닌 항목은 그 항목만 건너뛴다(`hasUnknownNotebook`).
/// 사유 열거형(`BackupUnsupportedReason`)에 넣지 않고 따로 센다(`BackupImportPreview.unknownNotebook`) — 설정 화면이 그 열거형을 빠짐없이
/// `switch` 하고 있어 경우를 더하면 화면 모듈이 컴파일되지 않는다. 사유 문구를 화면에 더할 때(t2c) 열거형으로 옮길 수 있다.
/// 그런 항목은 어느 필사책 장에도 놓지 않는다(`BackupImportPlanner.page(of:)` 가 nil) — 판정 · 복원 쓰기에 들지 않아 기본 필사책에 섞일 수 없다.
public enum BackupItemSupport {
    /// 이 앱이 아는 좌표 형식(nil 은 따로 허용한다 — `DrawingCodec` 은 nil · 1 을 같은 legacy 로, 2 · 3 을 각자 해석한다).
    public static let knownDrawingVersions: Set<Int> = [1, 2, 3]

    /// 항목을 해석할 수 없는 이유.
    /// - Parameters:
    ///   - item: 검증을 마친 항목.
    ///   - blobDirectory: `blobs/` 폴더 — v3 잉크 항목의 메타데이터 blob 을 읽는다.
    /// - Returns: 해석할 수 없으면 첫 번째 이유(번역본 → 권 → 범위 → 좌표 형식 → 메타데이터 순), 지원하면 nil. 부작용 없음(파일을 읽기만 한다).
    public static func reason(_ item: BackupItem, blobDirectory: URL) -> BackupUnsupportedReason? {
        reason(item) { name in
            try? Data(contentsOf: BackupPayload.blobURL(named: name, in: blobDirectory))
        }
    }

    /// 항목의 필사책 토큰이 `NotebookID` 형식이 아닌가(「알 수 없는 필사책」). 토큰이 없으면(기본 필사책) false.
    /// - Parameter item: 검증을 마친 항목.
    /// - Returns: 건너뛸 항목이면 true. 부작용 없음.
    public static func hasUnknownNotebook(_ item: BackupItem) -> Bool {
        item.verse.notebookID == nil
    }

    /// 항목을 해석할 수 없는 이유 — 메타데이터 바이트를 읽는 방법을 받는다(필요할 때만 부른다).
    static func reason(_ item: BackupItem, metadataBytes: (String) -> Data?) -> BackupUnsupportedReason? {
        if let translation = item.verse.translation, Translation(rawValue: translation) == nil {
            return .unknownTranslation
        }
        guard let book = BibleBookCode(rawValue: item.verse.book) else { return .unknownBook }
        guard (1...book.title.lastChapter).contains(item.verse.chapter), item.verse.verse >= 1 else { return .outOfRange }
        if let version = item.drawingVersion, !knownDrawingVersions.contains(version) {
            return .unknownDrawingVersion
        }
        if item.drawingVersion == 3, item.hasInk, let metadataBlob = item.metadataBlob {
            // 읽지 못한 blob 도 풀리지 않는 것과 같다.
            guard DrawingLayoutMetadata.decode(blob: metadataBytes(metadataBlob)) != nil else { return .undecodableMetadata }
        }
        return nil
    }
}
