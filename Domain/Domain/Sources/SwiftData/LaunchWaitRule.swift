//
//  LaunchWaitRule.swift
//  Domain
//
//  시작 화면의 선택형 대기 — 초기 복원일 때만 iCloud 를 기다리고, 처음부터 「먼저 시작하기」 를 둔다 (정책 §3 · §3-1,
//  2026-09-21 후속 리뷰 P0-3 · 사용자 결정).
//

import Foundation

/// 이 실행의 시작 화면이 기다리는 방식 (정책 §3 표).
public enum LaunchWaitMode: Equatable, Sendable {
    /// 로컬 저장소가 준비되면 곧바로 들어간다 — 이 기기에 이미 필사가 있거나 이 설치에서 앞서 들어간 적이 있다. 동기화는 앱 안에서 계속 본다.
    /// 로컬에 보여 줄 것이 이미 있으니 기다릴 까닭이 없다.
    case normal
    /// 초기 복원 — 새로 깔았거나 다시 깐 기기에서 로컬이 비었다. iCloud 의 필사를 기다리되 **처음부터 「먼저 시작하기」** 를 둔다.
    case initialRestore
}

/// 초기 복원이 어떻게 끝났는지 — 이 설치에서 한 번 정해지면 다음 실행부터 긴 대기로 돌아가지 않는다(§3-1). 초기 안내를 마쳤는지 · 대기를
/// 건너뛰었는지 · import 성공을 봤는지를 구분한다.
public enum InitialRestoreOutcome: String, Codable, Sendable {
    /// import 가 성공으로 끝나 들어갔다.
    case importSucceeded
    /// 기다리다 「먼저 시작하기」 로 들어갔다 — 기존 필사는 도착하는 대로 열린 장에 반영한다.
    case startedFirst
    /// iCloud 를 쓸 수 없는 까닭(계정 없음 · 확인 실패 · import 실패)을 알린 뒤 들어갔다.
    case startedWithoutICloud
}

/// 초기 복원 대기의 안내 단계 — **안내만 바꾸고 들어가지 않는다**(20초 · 60초, 사용자 결정 2026-09-21). 강제 한도는 두지 않는다 —
/// 「계속 기다리기」 는 따로 버튼 없이 이 화면에 머무는 것이다.
public enum LaunchWaitStage: Int, Comparable, Sendable {
    case checking
    /// 20초 — 시간이 걸리고 있다.
    case slow
    /// 60초 — 오래 걸릴 수 있다.
    case verySlow

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 시작 화면의 선택형 대기 규칙. 순수 함수라 시험으로 고정한다 — App 모듈에는 시험 타깃이 없다.
public enum LaunchWaitRule {
    /// 안내를 "시간이 걸리고 있어요" 로 바꾸는 때.
    public static let slowAfter: Duration = .seconds(20)
    /// 안내를 "오래 걸릴 수 있어요" 로 바꾸는 때.
    public static let verySlowAfter: Duration = .seconds(60)

    /// 이 실행의 대기 방식.
    ///
    /// **로컬이 비었다는 것만으로 신규 사용자라 보지 않는다**(정책 §3-2) — 앞서 들어간 적이 있거나(`hasEnteredBefore`) 초기 복원을 이미
    /// 마친 설치(`outcome`)는 일반 실행이다. 기존 사용자의 앱 업데이트는 로컬에 필사가 있어 일반 실행이다. 로컬을 읽지 못했으면(nil) 초기 복원으로
    /// 본다 — 기다리는 쪽도 처음부터 「먼저 시작하기」 가 있다.
    public static func mode(outcome: InitialRestoreOutcome?, hasEnteredBefore: Bool, hasLocalDrawings: Bool?) -> LaunchWaitMode {
        if outcome != nil || hasEnteredBefore || hasLocalDrawings == true { return .normal }
        return .initialRestore
    }

    /// 시작 화면이 할 일.
    ///
    /// | 상태 | 대기 방식을 아직 모름 | 일반 | 초기 복원 | 초기 복원 · 먼저 시작 |
    /// |---|---|---|---|---|
    /// | `idle` · `syncing` · `stillWaiting` · `failed` | 머문다 | 들어간다 | **머문다**(20초 · 60초에 안내만 바뀜) | 들어간다 |
    /// | `syncCompleted` | 머문다 | 들어간다 | 들어간다 | 들어간다 |
    /// | `migration` | 머문다 | 머문다 | 머문다 | 머문다 |
    /// | 마이그레이션 결론 · `storeUnavailable` | 재실행 요구 · 막는다(`launchRoute` 그대로) | ← | ← | ← |
    public static func route(
        _ state: PersistentCloudKitContainer.CloudSyncState,
        mode: LaunchWaitMode?,
        startedFirst: Bool
    ) -> LaunchRoute {
        switch state.launchRoute {
        case .restartRequired, .blocked:
            // 저장소를 쓸 수 없거나 V1 전용 컨테이너다 — 먼저 시작해도 들어가지 않는다(테스트 계획 MIG-F1).
            return state.launchRoute
        case .stay, .enterWriting:
            break
        }
        // 연결 보류 — 기다릴 초기 복원이 없다. 대기 방식과 무관하게 들어간다(정책 §12-6 C14 ③).
        if case .connectionHeld = state { return .enterWriting }
        guard state != .migration, let mode else { return .stay }
        switch mode {
        case .normal:
            return .enterWriting
        case .initialRestore:
            return state == .syncCompleted || startedFirst ? .enterWriting : .stay
        }
    }

    /// 「먼저 시작하기」 를 보이는가 — 초기 복원 대기 중이고, 막히거나 재실행을 요구하거나 마이그레이션 중이 아니다. 처음부터 보인다.
    public static func offersStartFirst(_ state: PersistentCloudKitContainer.CloudSyncState, mode: LaunchWaitMode?) -> Bool {
        guard mode == .initialRestore else { return false }
        switch state {
        case .idle, .syncing, .stillWaiting, .failed: return true
        case .syncCompleted, .migration, .migrationCompleted, .migrationEndedWithoutImport, .storeUnavailable, .connectionHeld: return false
        }
    }

    /// 들어갈 때 남길 초기 복원의 결과. 초기 복원이 아니었거나 들어가지 않으면 nil.
    public static func outcome(
        entering state: PersistentCloudKitContainer.CloudSyncState,
        mode: LaunchWaitMode?,
        startedFirst: Bool
    ) -> InitialRestoreOutcome? {
        guard mode == .initialRestore, route(state, mode: mode, startedFirst: startedFirst) == .enterWriting else { return nil }
        // 연결 보류로 들어간 것은 초기 복원의 결과가 아니다 — 남기지 않는다. 보류가 풀린 실행이 초기 복원을 한다.
        if case .connectionHeld = state { return nil }
        if state == .syncCompleted { return .importSucceeded }
        if case .failed = state { return .startedWithoutICloud }
        return .startedFirst
    }
}
