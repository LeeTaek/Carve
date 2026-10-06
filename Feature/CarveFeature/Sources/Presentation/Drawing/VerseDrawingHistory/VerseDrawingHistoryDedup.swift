//
//  VerseDrawingHistoryDedup.swift
//  FeatureCarve
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain

/// 이전 필사 기록 목록에서 **같은 내용의 행을 하나로 보이는** 규칙 (정책 §7-3 「수신 후 동일 버전을 하나로 취급」).
///
/// 두 기기가 오프라인으로 같은 백업을 불러오면 기기마다 `rowUUID` 를 새로 발급해 넣으므로, 연결 뒤 한 절에 같은 내용의 행이 둘 생긴다
/// (`docs/backup-import-design.md` §7). 그 행들을 **목록에서만** 하나로 보인다 — 저장소의 행은 지우지 않는다(파괴적인 중복 정리는
/// 정책 §7-3 대로 참조 보존 검증 뒤 따로 다룬다).
///
/// - 같은 내용 = 같은 `VerseDrawingSnapshot.contentFingerprint`(`VerseContentFingerprint` — `lineData` · `drawingVersion` · 레이아웃 메타데이터).
///   스냅샷은 메타데이터를 풀어 들고 있지만 지문은 메타데이터를 키 정렬로 다시 인코딩해 만들므로, 원본 `layoutMetadataData` 로 만든 지문
///   (`BackupRowRecord.contentFingerprint`)과 같다. 풀리지 않는 메타데이터는 스냅샷에서 nil 이라 그런 행끼리는 메타데이터 없이 견준다 —
///   캔버스도 그 행을 메타데이터 없이 그리므로 보이는 것은 같다.
/// - 묶음마다 남기는 행은 대표 규칙(`DrawingRepresentativeRule`)으로 고른다 — `isPresent` 행이 먼저, 그다음 `updateDate` 가 가장 늦은 것,
///   같으면 행 키 사전순(작은 쪽). 그래서 캔버스에 보이는 대표 행은 획이 있는 한 늘 목록에 남고, 회차 고르기도 남긴 행으로 한다.
/// - 순서는 받은 그대로다. 묶인 행들은 남긴 행 자리에 하나로 보인다.
enum VerseDrawingHistoryDedup {
    /// 같은 내용의 행을 하나씩만 남긴 목록을 만든다.
    /// - Parameter rows: 한 절의 행들(저장소 조회 순서 — `updateDate` 최신순). 지문이 없는 행(비운 행)은 묶지 않고 그대로 둔다.
    /// - Returns: 내용마다 한 행. 순서는 `rows` 그대로다. 부작용 없음.
    static func visibleRows(_ rows: [VerseDrawingSnapshot]) -> [VerseDrawingSnapshot] {
        var groups: [String: [Int]] = [:]
        for (index, row) in rows.enumerated() {
            guard let fingerprint = row.contentFingerprint else { continue }
            groups[fingerprint, default: []].append(index)
        }
        var hidden: Set<Int> = []
        for indices in groups.values where indices.count > 1 {
            let kept = DrawingRepresentativeRule.pick(indices.map { rows[$0] })
            // 값까지 똑같은 행이 겹쳐 와도 하나만 남도록 첫 자리 하나를 고른다.
            guard let keptIndex = indices.first(where: { rows[$0] == kept }) else { continue }
            hidden.formUnion(indices.filter { $0 != keptIndex })
        }
        return rows.indices.filter { !hidden.contains($0) }.map { rows[$0] }
    }
}
