//
//  CloudSyncStatus.swift
//  Domain
//
//  동기화 상태 판정 — 이벤트를 상태로 옮기는 규칙만 담는다 (정책 §4-1).
//

import Foundation

/// CloudKit 동기화 이벤트 한 건에서 **판정에 필요한 값만** 추린 것.
///
/// `NSPersistentCloudKitContainer.Event` 는 테스트에서 만들 수 없다. 그래서 경계에서 이 타입으로 바꾸고,
/// 판정 규칙은 이 값만 보게 한다. 그래야 "실패한 import 를 완료로 봤다" 같은 회귀를 테스트로 잡을 수 있다.
public struct CloudSyncEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case setup
        case cloudImport
        case cloudExport
    }

    public let kind: Kind
    /// 이벤트가 끝났는가 (`endDate != nil`).
    public let ended: Bool
    /// 끝난 이벤트가 **성공**이었는가. 진행 중이면 의미 없다.
    public let succeeded: Bool

    public init(kind: Kind, ended: Bool, succeeded: Bool) {
        self.kind = kind
        self.ended = ended
        self.succeeded = succeeded
    }
}

/// 동기화가 왜 멈췄는지. `failed` 하나로 뭉치면 화면이 원인과 무관한 안내를 하게 된다.
public enum CloudSyncFailure: Equatable, Sendable {
    /// iCloud 계정이 없거나 제한됐다. 네트워크 문제가 아니다.
    case accountUnavailable
    /// import 가 **오류로** 끝났다.
    case importFailed
    /// 그 밖. 원인을 특정하지 못했다.
    case unknown
}

/// 이벤트를 상태로 옮기는 규칙. 순수 함수라 테스트로 고정한다.
///
/// - Important: **끝났다는 것과 성공했다는 것은 다르다.** 이전 구현은 `endDate != nil` 과 `type == .import`
///              만 보고 완료로 판정해서, 오류로 끝난 import 도 "동기화 완료" 로 표시했다.
public enum CloudSyncStateRule {
    /// 기다리던 초기 import 가 **성공으로** 끝났는가.
    public static func isAwaitedImportSuccess(_ event: CloudSyncEvent) -> Bool {
        event.kind == .cloudImport && event.ended && event.succeeded
    }

    /// import 가 **실패로** 끝났는가. 진행 중인 이벤트는 실패가 아니다.
    public static func isImportFailure(_ event: CloudSyncEvent) -> Bool {
        event.kind == .cloudImport && event.ended && !event.succeeded
    }

    /// 이 이벤트가 대기를 끝낼 근거가 되는가 — 성공이든 실패든 **결론이 난 import** 다.
    public static func concludesWaiting(_ event: CloudSyncEvent) -> Bool {
        isAwaitedImportSuccess(event) || isImportFailure(event)
    }
}
