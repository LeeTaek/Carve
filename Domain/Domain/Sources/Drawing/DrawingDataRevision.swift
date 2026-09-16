//
//  DrawingDataRevision.swift
//  Domain
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Sharing

/// 필사 데이터가 **밖에서 통째로 바뀐** 횟수 (설정의 「모든 필사 데이터 삭제」).
///
/// 설정 화면과 필사 화면은 서로를 모른다. 둘을 잇는 값을 한곳에 두고, 지운 쪽은 `bump()`,
/// 보는 쪽은 `@Shared(.inMemory(DrawingDataRevision.key))` 로 읽는다 — `canUndo` 와 같은 관용구다.
///
/// 앱 실행 동안만 유지하면 된다. 앱을 다시 켜면 어차피 DB 에서 처음부터 합성한다.
public enum DrawingDataRevision {
    public static let key = "drawingDataRevision"

    /// 세대를 하나 올린다. 열려 있는 장이 이 값을 보고 미저장분을 버린 뒤 다시 조회한다.
    ///
    /// 값을 상태에 담지 않고 여기서 직접 올리는 이유는 `CloudSettingsFeature.State` 가 `Hashable` 이라
    /// `@Shared` 프로퍼티를 넣으면 그 합성이 깨지기 때문이다.
    public static func bump() {
        @Shared(.inMemory(key)) var revision: Int = 0
        $revision.withLock { $0 += 1 }
    }
}
