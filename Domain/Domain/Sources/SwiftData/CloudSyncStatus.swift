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
    /// import 가 **오류로** 끝났다. 원격 변경을 받지 못했다는 뜻이다.
    case importFailed
    /// export 가 **오류로** 끝났다. 내 변경이 서버에 올라가지 못했다는 뜻이다.
    case exportFailed
    /// 그 밖. 원인을 특정하지 못했다.
    case unknown
}

/// 앱이 도는 동안 계속 갱신되는 동기화 활동.
///
/// `CloudSyncState` 와 **다른 축**이다. 그쪽은 시작 화면이 초기 import 를 기다린 결과이고,
/// 이 값은 그 뒤로도 이어지는 실제 주고받음이다. 시작 화면이 끝났다고 동기화가 끝난 것이 아니므로
/// 설정 화면은 이 값을 본다 (정책 §4-1).
public struct CloudSyncActivity: Equatable, Sendable {
    /// 지금 진행 중인 작업이 있는가.
    ///
    /// - Note: 이벤트가 시작·종료 짝을 이룬다는 보장이 없어 **마지막 이벤트 기준**으로만 판단한다.
    ///         "확실히 돌고 있다" 가 아니라 "마지막으로 본 이벤트가 진행 중이었다" 로 읽어야 한다.
    public var isRunning: Bool
    /// 마지막으로 import 가 성공한 시각. 없으면 이 실행에서 한 번도 받아 본 적이 없다.
    public var lastImportSuccess: Date?
    /// 마지막으로 export 가 성공한 시각. 없으면 이 실행에서 한 번도 올려 본 적이 없다.
    public var lastExportSuccess: Date?
    /// 마지막으로 확인된 오류. 같은 종류가 성공하면 지운다.
    public var lastFailure: CloudSyncFailure?

    public init(
        isRunning: Bool = false,
        lastImportSuccess: Date? = nil,
        lastExportSuccess: Date? = nil,
        lastFailure: CloudSyncFailure? = nil
    ) {
        self.isRunning = isRunning
        self.lastImportSuccess = lastImportSuccess
        self.lastExportSuccess = lastExportSuccess
        self.lastFailure = lastFailure
    }

    /// 이벤트 하나를 반영한 새 값. 순수 함수라 테스트로 고정한다.
    ///
    /// - Parameters:
    ///   - event: 방금 도착한 이벤트.
    ///   - date: 그 이벤트가 끝난 것으로 볼 시각.
    public func applying(_ event: CloudSyncEvent, at date: Date) -> CloudSyncActivity {
        var next = self
        guard event.ended else {
            // 시작 이벤트다. 성공·실패 기록은 건드리지 않는다.
            next.isRunning = true
            return next
        }
        next.isRunning = false

        switch (event.kind, event.succeeded) {
        case (.cloudImport, true):
            next.lastImportSuccess = date
            if next.lastFailure == .importFailed { next.lastFailure = nil }
        case (.cloudImport, false):
            next.lastFailure = .importFailed
        case (.cloudExport, true):
            next.lastExportSuccess = date
            if next.lastFailure == .exportFailed { next.lastFailure = nil }
        case (.cloudExport, false):
            next.lastFailure = .exportFailed
        case (.setup, true):
            break
        case (.setup, false):
            // setup 실패는 원인을 특정할 수 없다. 계정 문제일 수도, 권한일 수도 있다.
            next.lastFailure = .unknown
        }
        return next
    }
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
