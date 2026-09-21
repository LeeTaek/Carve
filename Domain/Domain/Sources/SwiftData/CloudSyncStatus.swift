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
public enum CloudSyncFailure: Hashable, Sendable {
    /// iCloud 계정이 없거나 제한됐다. 네트워크 문제가 아니다.
    case accountUnavailable
    /// iCloud 계정 상태를 **확인하지 못했다**(조회 오류 · 일시적 불가). 계정이 없다는 뜻이 아니다.
    case accountCheckFailed
    /// import 가 **오류로** 끝났다. 원격 변경을 받지 못했다는 뜻이다.
    case importFailed
    /// export 가 **오류로** 끝났다. 내 변경이 서버에 올라가지 못했다는 뜻이다.
    case exportFailed
    /// 동기화 준비(setup)가 오류로 끝났다. 받기 · 올리기가 모두 멈췄을 수 있다.
    case setupFailed
    /// 그 밖. 원인을 특정하지 못했다.
    case unknown
}

/// 앱이 도는 동안 계속 갱신되는 동기화 활동.
///
/// `CloudSyncState` 와 **다른 축**이다. 그쪽은 시작 화면이 초기 import 를 기다린 결과이고,
/// 이 값은 그 뒤로도 이어지는 실제 주고받음이다. 시작 화면이 끝났다고 동기화가 끝난 것이 아니므로
/// 설정 화면은 이 값을 본다 (정책 §4-1).
public struct CloudSyncActivity: Hashable, Sendable {
    /// 지금 진행 중인 작업이 있는가.
    ///
    /// - Note: 이벤트가 시작·종료 짝을 이룬다는 보장이 없어 **마지막 이벤트 기준**으로만 판단한다.
    ///         "확실히 돌고 있다" 가 아니라 "마지막으로 본 이벤트가 진행 중이었다" 로 읽어야 한다.
    public var isRunning: Bool
    /// 마지막으로 import 가 성공한 시각. 없으면 이 실행에서 한 번도 받아 본 적이 없다.
    public var lastImportSuccess: Date?
    /// 마지막으로 export 가 성공한 시각. 없으면 이 실행에서 한 번도 올려 본 적이 없다.
    public var lastExportSuccess: Date?
    /// 아직 해결되지 않은 실패. **종류마다 따로** 들고, 같은 종류가 성공해야 풀린다.
    ///
    /// 이전 구현은 마지막 실패 하나만 들어서 "export 실패 → import 실패 → import 성공" 이면 export 실패가 사라졌다 —
    /// 내 변경은 여전히 올라가지 못했는데 성공 기록만 보였다. setup 실패는 setup 이 성공해도 풀리지 않았다.
    public var unresolvedFailures: Set<CloudSyncFailure>

    public init(
        isRunning: Bool = false,
        lastImportSuccess: Date? = nil,
        lastExportSuccess: Date? = nil,
        unresolvedFailures: Set<CloudSyncFailure> = []
    ) {
        self.isRunning = isRunning
        self.lastImportSuccess = lastImportSuccess
        self.lastExportSuccess = lastExportSuccess
        self.unresolvedFailures = unresolvedFailures
    }

    /// 화면에 보여 줄 요약.
    public enum Summary: Hashable, Sendable {
        /// 이번 실행에서 아직 주고받은 기록이 없다. **동기화되지 않았다는 뜻이 아니다.**
        case noRecord
        /// 지금 주고받는 중이다.
        case running
        /// 해결되지 않은 실패가 남아 있다. **전부** 든다 — 하나만 보이면 나머지가 해결된 것처럼 읽힌다.
        /// 순서는 `displayOrder` 다.
        case failed([CloudSyncFailure])
        /// 성공 기록만 있다. 받은 적 · 올린 적이 없으면 nil.
        case succeeded(lastImport: Date?, lastExport: Date?)
    }

    /// 실패를 보여 줄 순서. 범위가 넓은 것부터 — setup 실패는 받기 · 올리기를 모두 막고,
    /// 올리지 못한 것은 이 기기에만 있는 필사라 받지 못한 것보다 앞에 둔다.
    public static let displayOrder: [CloudSyncFailure] = [
        .setupFailed, .exportFailed, .importFailed, .accountUnavailable, .accountCheckFailed, .unknown
    ]

    /// 지금 보여 줄 요약. **실패가 가장 먼저다** — 다른 종류가 성공했어도 남은 실패는 해결되지 않았다.
    public var summary: Summary {
        if !unresolvedFailures.isEmpty {
            return .failed(Self.displayOrder.filter(unresolvedFailures.contains))
        }
        if isRunning { return .running }
        if lastImportSuccess == nil && lastExportSuccess == nil { return .noRecord }
        return .succeeded(lastImport: lastImportSuccess, lastExport: lastExportSuccess)
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

        // 같은 종류의 성공만 그 실패를 푼다. 다른 종류의 성공은 남은 실패와 무관하다.
        switch (event.kind, event.succeeded) {
        case (.cloudImport, true):
            next.lastImportSuccess = date
            next.unresolvedFailures.remove(.importFailed)
        case (.cloudImport, false):
            next.unresolvedFailures.insert(.importFailed)
        case (.cloudExport, true):
            next.lastExportSuccess = date
            next.unresolvedFailures.remove(.exportFailed)
        case (.cloudExport, false):
            next.unresolvedFailures.insert(.exportFailed)
        case (.setup, true):
            next.unresolvedFailures.remove(.setupFailed)
        case (.setup, false):
            // 원인(계정 · 권한 · 스키마)은 이벤트만으로 특정할 수 없다.
            next.unresolvedFailures.insert(.setupFailed)
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
