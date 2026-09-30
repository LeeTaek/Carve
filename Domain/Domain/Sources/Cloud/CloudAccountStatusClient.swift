//
//  CloudAccountStatusClient.swift
//  Domain
//
//  iCloud 계정 사용 가능 여부 조회 (정책 §4-1).
//

import CloudKit
import Foundation

import Dependencies

/// 이 기기에서 iCloud 를 쓸 수 있는지.
///
/// - Important: **조회하기 전에는 `checking` 이다.** 확인하지 않은 상태를 "연결됨" 으로 표시하지 않는다 —
///              이전 설정 화면은 계정을 한 번도 조회하지 않으면서 토글을 켜진 채로 보여 줬다.
public enum CloudAccountAvailability: Equatable, Sendable {
    /// 아직 확인 중이다.
    case checking
    /// 계정이 있고 쓸 수 있다.
    case available
    /// iCloud 에 로그인돼 있지 않다.
    case noAccount
    /// 기기 관리 정책 등으로 제한됐다.
    case restricted
    /// 확인하지 못했다(네트워크·일시 오류). **없다는 뜻이 아니다.**
    case unknown

    /// 동기화가 실제로 이뤄질 수 있는 상태인가.
    public var canSync: Bool { self == .available }
}

/// 계정 상태를 조회한다. 화면이 CloudKit 을 직접 알지 않게 하는 경계다.
public protocol CloudAccountStatusClient: Sendable {
    /// 지금 계정 상태. 조회에 실패하면 `unknown` 이며 `noAccount` 와 구분한다.
    func availability() async -> CloudAccountAvailability
}

/// 앱이 실제로 쓰는 구현. **기본 컨테이너가 아니라 주입된 컨테이너**를 조회한다 (정책 §4-1).
public struct CloudKitAccountStatusClient: CloudAccountStatusClient {
    public init() { }

    public func availability() async -> CloudAccountAvailability {
        @Dependency(\.containerId) var containerId
        let container = containerId.id.isEmpty ? CKContainer.default() : CKContainer(identifier: containerId.id)
        do {
            return Self.availability(for: try await container.accountStatus())
        } catch {
            // 조회 자체가 실패했다. 계정이 없다고 단정하지 않는다.
            return .unknown
        }
    }

    /// CloudKit 계정 상태를 화면이 쓰는 값으로 옮긴다.
    static func availability(for status: CKAccountStatus) -> CloudAccountAvailability {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .couldNotDetermine: .unknown
        case .temporarilyUnavailable: .unknown
        @unknown default: .unknown
        }
    }
}

private enum CloudAccountStatusClientKey: DependencyKey {
    static let liveValue: any CloudAccountStatusClient = CloudKitAccountStatusClient()
    /// 테스트는 확인 전 상태로 시작한다. 조회 결과가 필요하면 각 테스트가 주입한다.
    static let testValue: any CloudAccountStatusClient = StubCloudAccountStatusClient(.checking)
    static let previewValue: any CloudAccountStatusClient = StubCloudAccountStatusClient(.available)
}

public extension DependencyValues {
    /// iCloud 계정 사용 가능 여부.
    var cloudAccountStatus: any CloudAccountStatusClient {
        get { self[CloudAccountStatusClientKey.self] }
        set { self[CloudAccountStatusClientKey.self] = newValue }
    }
}

/// 고정된 값을 돌려주는 구현. 테스트·프리뷰용이다.
public struct StubCloudAccountStatusClient: CloudAccountStatusClient {
    private let value: CloudAccountAvailability

    public init(_ value: CloudAccountAvailability) {
        self.value = value
    }

    public func availability() async -> CloudAccountAvailability { value }
}
