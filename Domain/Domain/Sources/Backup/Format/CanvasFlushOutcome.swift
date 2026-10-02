//
//  CanvasFlushOutcome.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 백업 전 캔버스 flush 의 결과 (설계 §5-2 — 정책 §6-1 1단계).
///
/// 필사 화면(`ChapterCanvasFeature`)과 설정(`BackupExportFeature`)이 함께 쓰므로 Domain 에 둔다 — Feature 끼리 import 하지 않고
/// `AppCoordinatorFeature` 가 중계한다. `.durable` 이 아니면 내보내기를 시작하지 않는다.
public enum CanvasFlushOutcome: Codable, Equatable, Hashable, Sendable {
    /// 마지막 revision 까지 이 기기에 내구성 있게 남았다 — 저장소로 갈 것은 저장소에, 그 밖은 초안에. 필사 화면이 없을 때도 이것이다.
    case durable
    /// 초안 · 저장이 실패해 재시도 중이다(`saveRetryCount`).
    case failed(retryCount: Int)
    /// 시간 안에 정해지지 않았다(캔버스 5초 · 설정 10초).
    case timedOut
}
