//
//  LaunchRoute.swift
//  Domain
//
//  시작 화면의 진입 판정 — 동기화 상태를 화면 행동으로 옮기는 규칙만 담는다 (정책 §3 표 4행 · 테스트 계획 MIG-F1).
//

import Foundation

/// 시작 화면이 상태를 보고 정하는 다음 행동.
///
/// 판정을 `LaunchProgressFeature` 가 아니라 여기 두는 이유 — App 모듈에는 테스트 타깃이 없다. 진입 여부는
/// "정상 저장이 불가능한 채 편집 화면에 들어가는가" 를 가르는 판정이라 테스트로 고정해야 한다.
public enum LaunchRoute: Equatable, Sendable {
    /// 아직 결론이 없다. 시작 화면에 머문다.
    case stay
    /// 필사 화면으로 들어간다.
    case enterWriting
    /// 재실행해야 이어진다. 이번 실행의 저장소(V1 전용 컨테이너)로는 필사를 저장할 수 없다.
    case restartRequired
    /// 로컬 저장소를 쓸 수 없다. 안내만 하고 들어가지 않는다.
    case blocked(LocalStoreFailure)
}

public extension PersistentCloudKitContainer.CloudSyncState {
    /// 이 상태에서 시작 화면이 할 일.
    ///
    /// | 상태 | 행동 |
    /// |---|---|
    /// | `idle` · `syncing` · `migration` | 머문다 |
    /// | `syncCompleted` · `stillWaiting` · `failed` | 들어간다 — 로컬 저장소는 앱 스키마로 열려 있다 |
    /// | `migrationCompleted` · `migrationEndedWithoutImport` | 재실행을 요구한다 |
    /// | `storeUnavailable` | 막는다 |
    ///
    /// - Important: 이전 구현은 마이그레이션 모드에서도 계정 없음 · 확인 실패 · import 실패 · 시간 초과가 `failed` · `stillWaiting`
    ///              으로 끝나 V1 전용 컨테이너를 쥔 채 필사 화면에 들어갔다. 그 컨테이너에서는 필사 조회가 비고, 저장은 오류 없이
    ///              끝나지만 다시 읽히지 않는다(테스트 계획 §5-1 MIG-F1). 이제 마이그레이션 모드의 결론은 들어가는 상태로 끝나지 않는다.
    var launchRoute: LaunchRoute {
        switch self {
        case .idle, .syncing, .migration: .stay
        case .syncCompleted, .stillWaiting, .failed: .enterWriting
        case .migrationCompleted, .migrationEndedWithoutImport: .restartRequired
        case .storeUnavailable(let failure): .blocked(failure)
        }
    }
}
