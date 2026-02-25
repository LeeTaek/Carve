//
//  AnalyticsEvents.swift
//  ClientInterfaces
//
//  Created by 이택성 on 2/24/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

// MARK: - Analytics event names

/// GA4 event name constants.
public enum AnalyticsEventName {
    public static let errorShown = "error_shown"
    public static let featureEntry = "feature_entry"
    public static let featureComplete = "feature_complete"
}

// MARK: - Event parameters
/// GA4에서 공통으로 사용할 Feature 이름.
public enum AnalyticsFeatureName: String, Sendable, Equatable {
    case app = "App"
    case carve = "Carve"
    case settings = "Settings"
    case chart = "Chart"
    case domain = "Domain"
    case infra = "Infra"
    case buildCI = "BuildCI"
    case unknown = "Unknown"
}

/// - Note:
///   - Prefix는 가능한 한 `area:` 라벨/모듈과 1:1 매핑
///   - 숫자는 카테고리 내에서 증가(001, 002, ...)
public enum AnalyticsErrorId: String, Sendable, Equatable {
    // MARK: - SwiftData / Persistence
    /// ModelContainer 생성 실패
    case swiftDataModelContainerCreateFailed = "SWIFTDATA_001"
    /// Fetch/Insert/Update 실패(공통)
    case swiftDataOperationFailed = "SWIFTDATA_002"
    
    // MARK: - Drawing / Database
    /// verse 단위 필사 업데이트 실패
    case drawingUpdateDrawingsFailed = "DRAWING_001"
    /// isPresent 업데이트 실패
    case drawingUpdatePresentFailed = "DRAWING_002"
    /// page 단위 필사 upsert 실패
    case drawingUpsertPageFailed = "DRAWING_003"

    // MARK: - Canvas / PencilKit
    /// PKCanvas 관련 작업 실패(공통)
    case canvasOperationFailed = "CANVAS_001"
    /// 렌더링/스냅샷 생성 실패
    case canvasRenderFailed = "CANVAS_002"
    case canvasDrawingDecodeFailed = "CANVAS_003"

    // MARK: - Sync (옵션: 사용 중이라면)
    /// 동기화 시작 실패
    case syncStartFailed = "SYNC_001"
    /// 동기화 완료 실패
    case syncCompleteFailed = "SYNC_002"

    // MARK: - Infra
    /// Analytics 전송 실패(구현체 내부에서 필요 시)
    case analyticsSendFailed = "INFRA_001"
    /// 광고 로딩 실패(필요 시)
    case adLoadFailed = "INFRA_002"
}

// MARK: - AnalyticsClient helpers
public extension AnalyticsClient {
    /// 사용자에게 에러(또는 치명적 실패)를 노출한 상황을 기록.
    func trackErrorShown(
        _ errorId: AnalyticsErrorId,
        feature: AnalyticsFeatureName,
        context: String,
        message: String? = nil,
        extra: [String: AnalyticsValue] = [:]
    ) {
        var parameters: [String: AnalyticsValue] = [
            "error_id": .string(errorId.rawValue),
            "feature_name": .string(feature.rawValue),
            "context": .string(context)
        ]

        if let message {
            parameters["message"] = .string(message)
        }

        // extra 파라미터는 동일 키가 들어오면 extra를 우선.
        for (key, value) in extra {
            parameters[key] = value
        }

        track(AnalyticsEventName.errorShown, parameters: parameters)
    }

    /// 기능 진입 기록(선택).
    func trackFeatureEntry(
        _ feature: AnalyticsFeatureName,
        extra: [String: AnalyticsValue] = [:]
    ) {
        var parameters: [String: AnalyticsValue] = [
            "feature_name": .string(feature.rawValue)
        ]

        for (key, value) in extra {
            parameters[key] = value
        }

        track(AnalyticsEventName.featureEntry, parameters: parameters)
    }

    /// 기능 완료 기록(선택).
    func trackFeatureComplete(
        _ feature: AnalyticsFeatureName,
        success: Bool,
        extra: [String: AnalyticsValue] = [:]
    ) {
        var parameters: [String: AnalyticsValue] = [
            "feature_name": .string(feature.rawValue),
            "success": .bool(success)
        ]

        for (key, value) in extra {
            parameters[key] = value
        }

        track(AnalyticsEventName.featureComplete, parameters: parameters)
    }
}

