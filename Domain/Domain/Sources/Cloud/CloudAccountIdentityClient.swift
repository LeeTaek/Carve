//
//  CloudAccountIdentityClient.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CloudKit
import Dependencies
import Foundation

/// 지금 iCloud 계정이 **누구인지** 조회한 결과 (정책 §12-6 계정 범위).
///
/// 계정 상태(`CloudAccountAvailability`)는 계정이 있는지만 알려 준다. 계정이 바뀌었는지 가리려면 식별 값이 필요하다.
public enum CloudAccountIdentity: Equatable, Sendable {
    /// 이 컨테이너의 사용자 레코드 이름. **로그 · 파일 · 문서에 그대로 남기지 않는다** — `AccountScope` 로 해시해서 쓴다.
    case identified(userRecordName: String)
    /// iCloud 에 로그인돼 있지 않다 — 이 기기에만 저장한다.
    case noAccount
    /// 확인하지 못했다(네트워크 · 제한 · 일시 오류). **없다는 뜻이 아니다.**
    case unavailable
}

public protocol CloudAccountIdentityClient: Sendable {
    func currentIdentity() async -> CloudAccountIdentity
}

/// 앱이 쓰는 구현. 계정 상태를 먼저 보고, 쓸 수 있을 때만 사용자 레코드 ID 를 묻는다.
///
/// `FileManager.ubiquityIdentityToken` 은 쓰지 않는다 — iCloud Drive 를 끄면 CloudKit 이 동작해도 nil 이라 계정 식별로 쓸 수 없다.
public struct CloudKitAccountIdentityClient: CloudAccountIdentityClient {
    private let containerID: String?

    /// - Parameter containerID: 조회할 CloudKit 컨테이너. 앱 시작처럼 의존성 문맥 밖에서 부르는 곳은 **반드시 넘긴다** —
    ///   생략하면 호출할 때의 `containerId` 의존성을 읽는데, 문맥 밖에서는 기본 컨테이너를 보게 되고 사용자 레코드 이름은
    ///   컨테이너마다 다르다.
    public init(containerID: String? = nil) {
        self.containerID = containerID
    }

    public func currentIdentity() async -> CloudAccountIdentity {
        @Dependency(\.containerId) var containerId
        let identifier = containerID ?? containerId.id
        let container = identifier.isEmpty ? CKContainer.default() : CKContainer(identifier: identifier)
        do {
            switch try await container.accountStatus() {
            case .available:
                return .identified(userRecordName: try await container.userRecordID().recordName)
            case .noAccount:
                return .noAccount
            case .restricted, .couldNotDetermine, .temporarilyUnavailable:
                return .unavailable
            @unknown default:
                return .unavailable
            }
        } catch {
            // 조회 실패는 "계정 없음" 이 아니다.
            return .unavailable
        }
    }
}

public struct StubCloudAccountIdentityClient: CloudAccountIdentityClient {
    private let value: CloudAccountIdentity

    public init(_ value: CloudAccountIdentity) {
        self.value = value
    }

    public func currentIdentity() async -> CloudAccountIdentity { value }
}

private enum CloudAccountIdentityClientKey: DependencyKey {
    static let liveValue: any CloudAccountIdentityClient = CloudKitAccountIdentityClient()
    /// 테스트는 확인하지 못한 상태로 시작한다 — 서버 작업을 막는 쪽이 기본이다. 필요하면 각 테스트가 주입한다.
    static let testValue: any CloudAccountIdentityClient = StubCloudAccountIdentityClient(.unavailable)
}

public extension DependencyValues {
    /// 지금 iCloud 계정의 식별.
    var cloudAccountIdentity: any CloudAccountIdentityClient {
        get { self[CloudAccountIdentityClientKey.self] }
        set { self[CloudAccountIdentityClientKey.self] = newValue }
    }
}
