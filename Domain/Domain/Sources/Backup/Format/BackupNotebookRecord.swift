//
//  BackupNotebookRecord.swift
//  Domain
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 백업 형식 2 의 필사책 목록 하나 — `DrawingNotebook` 레코드의 필드를 **원본 그대로** 담는다(2.2 「회차별 필사책」).
///
/// - 예약 필드(`kind` · `scopeData` · `linkData`)도 읽지도 해석하지도 않고 그대로 옮긴다(설계 `docs/notebook-design.md` §5-2).
/// - `status` 는 열거형이 아니라 저장된 문자열 그대로다 — 모르는 값을 버리지 않는다(혼재 버전 규칙 ④). 화면은 `NotebookStatus(stored:)` 로 읽는다.
/// - 목록은 `manifest.json` 의 `notebooks` 키에 든다(`BackupManifest.notebooks`). 따로 파일을 두지 않는 까닭은 `BackupManifest` 주석.
/// - 같은 필사책의 레코드가 저장소에 둘 이상이면(동기화 중복) 내보내기는 `isNewer(than:)` 로 고른 하나만 담는다.
public struct BackupNotebookRecord: Codable, Equatable, Sendable {
    /// `NotebookID.rawValue` 원문 — `"default"` 또는 소문자 16진 32자리. 형식이 아니면 불러오기가 이 레코드를 건너뛴다(`notebookID` 가 nil).
    public var id: String
    /// 사용자가 붙인 이름. nil 은 메타데이터에 이름이 없다는 뜻이다(옮기지 않는 사용자 입력).
    public var name: String?
    /// `NotebookStatus.rawValue` 원문(`active` · `completed`). 모르는 값도 그대로 둔다.
    public var status: String?
    /// 만든 시각.
    public var createdAt: Date?
    /// 이름 · 상태를 바꾼 시각 — 같은 필사책이면 이 값이 늦은 쪽이 이긴다.
    public var updatedAt: Date?
    /// 완료를 표시한 시각. 완료가 아니면 nil.
    public var completedAt: Date?
    /// 필사책 종류(1차는 늘 `"personal"`) — 그대로 옮긴다.
    public var kind: String?
    /// 예약 — 말씀 범위 JSON. 해석하지 않고 그대로 옮긴다.
    public var scopeData: String?
    /// 예약 — 그룹 · 챌린지 연결 JSON. 해석하지 않고 그대로 옮긴다.
    public var linkData: String?

    /// 값을 그대로 지정해 만든다.
    public init(
        id: String,
        name: String?,
        status: String?,
        createdAt: Date?,
        updatedAt: Date?,
        completedAt: Date?,
        kind: String?,
        scopeData: String?,
        linkData: String?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.kind = kind
        self.scopeData = scopeData
        self.linkData = linkData
    }

    /// 레코드가 가리키는 필사책. `id` 가 `NotebookID` 형식이 아니면 nil.
    public var notebookID: NotebookID? {
        NotebookID(rawValue: id)
    }

    /// 역할: 같은 필사책의 두 레코드 중 이 레코드가 이기는가 — 저장소 읽기(`SwiftDataNotebookRepository`)와 같은 규칙.
    /// 입력 · 출력: 다른 레코드 → `updatedAt` 이 늦으면 true(nil 은 가장 이른 시각), 같으면 `name` 사전순 앞(nil 은 빈 이름)이면 true.
    /// 부작용: 없음.
    public func isNewer(than other: BackupNotebookRecord) -> Bool {
        let mine = updatedAt ?? .distantPast
        let theirs = other.updatedAt ?? .distantPast
        if mine != theirs { return mine > theirs }
        return (name ?? "") < (other.name ?? "")
    }

    /// 역할: 레코드를 필사책마다 하나로 줄인다 — 같은 ID 가 둘 이상이면 `isNewer(than:)` 로 이기는 하나.
    /// 입력 · 출력: 레코드 목록 → `NotebookID` 형식인 것만, 필사책마다 하나, 기본 필사책 먼저 · 나머지는 `id` 순.
    /// 부작용: 없음.
    public static func latestPerNotebook(_ records: [BackupNotebookRecord]) -> [BackupNotebookRecord] {
        var latest: [NotebookID: BackupNotebookRecord] = [:]
        for record in records {
            guard let notebook = record.notebookID else { continue }
            if let kept = latest[notebook], !record.isNewer(than: kept) { continue }
            latest[notebook] = record
        }
        return latest.values.sorted { lhs, rhs in
            NotebookID.backupOrder(lhs.notebookID ?? .default, rhs.notebookID ?? .default)
        }
    }
}

extension NotebookID {
    /// 백업의 필사책 순서 — 기본 필사책 먼저, 나머지는 `rawValue` 순.
    static func backupOrder(_ lhs: NotebookID, _ rhs: NotebookID) -> Bool {
        if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
        return lhs.rawValue < rhs.rawValue
    }
}
