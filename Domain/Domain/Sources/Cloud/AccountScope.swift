//
//  AccountScope.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import CryptoKit
import Foundation

/// 계정 범위 — 저장과 작업이 어느 iCloud 계정에 속하는지 (정책 §12-6 용어).
///
/// **키 = SHA-256(컨테이너 ID ‖ 사용자 레코드 이름) 앞 16바이트.** 사용자 레코드 이름은 컨테이너마다 다르므로 컨테이너 ID 를
/// 함께 넣는다(dev · 운영 컨테이너가 섞이지 않는다). 식별 값을 그대로 쓰지 않고 해시한다 — 파일 이름 · 로그에 계정 식별자가
/// 남지 않게 하려는 것이다.
public struct AccountScope: Hashable, Codable, Sendable {
    public let key: String

    public init(key: String) {
        self.key = key
    }

    /// 계정 식별 값에서 범위 키를 만든다. 같은 값이면 언제나 같은 키다.
    public static func make(fromAccountIdentity identity: String) -> AccountScope {
        let digest = SHA256.hash(data: Data("carve.accountScope/1|\(identity)".utf8))
        return AccountScope(key: "acct-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined())
    }

    /// 앱이 쓰는 방식 — 컨테이너 ID 와 사용자 레코드 이름.
    public static func make(containerID: String, userRecordName: String) -> AccountScope {
        make(fromAccountIdentity: "\(containerID)|\(userRecordName)")
    }

    /// iCloud 에 로그인하지 않은 동안 남긴 로컬 보존 묶음. **로그인해도 어느 계정으로도 자동으로 옮기지 않는다.**
    public static let localOnly = AccountScope(key: "acct-local")
    /// 계정을 확인하지 못한 동안 남긴 로컬 보존 묶음. 출처 계정을 증명할 수 없으므로 **자동으로 귀속하지 않는다.**
    public static let unverified = AccountScope(key: "acct-unverified")
}

/// 서버에 영향을 주는 작업(서버 정리 · 삭제 작업 · K 갱신 · 버전 확정)을 시작할 때 받는 표.
///
/// 확인 세대를 함께 든다. 작업은 서버 단계마다 `AccountScopeProvider.isCurrent(_:)` 로 표가 아직 유효한지 다시 확인한다 —
/// 그 사이 계정 변경 알림이나 재확인이 있었으면 멈춘다.
public struct AccountServerWorkToken: Equatable, Sendable {
    public let scope: AccountScope
    public let generation: UInt64
}

/// 이번 실행에서 계정 범위를 얼마나 확신하는지.
public enum AccountScopeState: Equatable, Sendable {
    /// 이번 확인 세대에서 사용자 레코드 이름을 얻었다.
    case confirmed(AccountScope)
    /// iCloud 에 로그인돼 있지 않다. **서버 작업은 하지 않는다** — 이전 계정의 저장소가 남아 있을 수 있어, 로컬 삭제가
    /// 무엇에 적용되는지는 전체 삭제 연결에서 따로 정한다.
    case noAccount
    /// 확인 중이거나 확인하지 못했다. `lastConfirmed` 는 **참고 정보일 뿐** 저장소 내용의 소유를 정하는 근거가 아니다 —
    /// 앱을 끈 사이 시스템에서 계정을 바꿨을 수 있다.
    case unconfirmed(lastConfirmed: AccountScope?)

    /// 로컬 보존(복구 사본 · 초안 · 격리본)에 붙일 범위. **로컬 보존은 막지 않는다.**
    /// 출처를 증명하지 못하는 동안 만든 것은 계정에 붙이지 않고 따로 묶는다.
    public var scopeForLocalPreservation: AccountScope {
        switch self {
        case .confirmed(let scope): scope
        case .noAccount: .localOnly
        case .unconfirmed: .unverified
        }
    }

    /// 서버 작업에 쓸 범위. **확인된 계정만.**
    public var scopeForServerWork: AccountScope? {
        switch self {
        case .confirmed(let scope): scope
        case .noAccount, .unconfirmed: nil
        }
    }
}

/// 조회 결과로 이번 실행의 상태를 정한다. 순수 함수라 표로 시험한다.
public enum AccountScopeResolver {
    public static func resolve(
        _ identity: CloudAccountIdentity,
        containerID: String,
        lastConfirmed: AccountScope?
    ) -> AccountScopeState {
        switch identity {
        case .identified(let name): .confirmed(.make(containerID: containerID, userRecordName: name))
        case .noAccount: .noAccount
        case .unavailable: .unconfirmed(lastConfirmed: lastConfirmed)
        }
    }
}

/// 앱이 쥐는 계정 범위.
///
/// - **재확인하는 동안에는 서버 작업을 잠근다.** 조회를 시작할 때 상태를 "확인 중" 으로 돌리고 확인 세대를 올린다.
/// - **늦게 온 조회 결과는 버린다.** 조회를 기다리는 사이 다른 확인이 시작됐으면(세대가 바뀌었으면) 그 결과로 상태를 덮지 않는다.
///   actor 는 `await` 사이의 교차 실행을 막지 않으므로 세대로 가른다.
/// - 확인 전 · 로그인 안 함 동안 남긴 로컬 보존은 **어느 계정으로도 자동으로 옮기지 않는다.**
public actor AccountScopeProvider {
    private let identity: any CloudAccountIdentityClient
    private let containerID: String
    private let stateStore: FileEraseStateStore
    private var generation: UInt64 = 0
    public private(set) var state: AccountScopeState

    public init(identity: any CloudAccountIdentityClient, containerID: String, stateStore: FileEraseStateStore) {
        self.identity = identity
        self.containerID = containerID
        self.stateStore = stateStore
        self.state = .unconfirmed(lastConfirmed: (try? stateStore.lastConfirmedScope()) ?? nil)
    }

    /// 계정이 바뀌었을 수 있다(계정 변경 알림). **즉시** 서버 작업을 잠그고 진행 중인 작업의 표를 무효로 만든다.
    /// 다시 확인하려면 `refresh()` 를 부른다.
    public func invalidate() {
        generation &+= 1
        state = .unconfirmed(lastConfirmed: lastConfirmedHint())
    }

    /// 계정을 다시 확인한다. 기다리는 동안 더 새로운 확인이 시작되면 이 결과는 버리고 그때의 상태를 돌려준다.
    @discardableResult
    public func refresh() async -> AccountScopeState {
        invalidate()
        let requested = generation
        let result = await identity.currentIdentity()
        guard requested == generation else {
            Log.debug("계정 범위 — 늦게 온 조회 결과를 버린다")
            return state
        }
        let next = AccountScopeResolver.resolve(result, containerID: containerID, lastConfirmed: lastConfirmedHint())
        if case .confirmed(let scope) = next {
            do {
                try stateStore.rememberConfirmedScope(scope)
            } catch {
                Log.error("계정 범위 — 확인한 범위를 기억하지 못했다", "\(error)")
            }
        }
        state = next
        return next
    }

    /// 서버 작업을 시작할 때 받는 표. 확인된 계정일 때만 준다.
    public func serverWorkToken() -> AccountServerWorkToken? {
        guard case .confirmed(let scope) = state else { return nil }
        return AccountServerWorkToken(scope: scope, generation: generation)
    }

    /// 표가 아직 유효한가 — 같은 확인 세대이고 같은 계정이다. 서버 단계마다 확인한다.
    public func isCurrent(_ token: AccountServerWorkToken) -> Bool {
        guard case .confirmed(let scope) = state else { return false }
        return token.generation == generation && token.scope == scope
    }

    private func lastConfirmedHint() -> AccountScope? {
        (try? stateStore.lastConfirmedScope()) ?? nil
    }
}
