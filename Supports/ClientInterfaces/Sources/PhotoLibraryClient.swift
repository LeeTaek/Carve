//
//  PhotoLibraryClient.swift
//  ClientInterfaces
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

/// 사진 보관함에 이미지를 추가한 결과.
public enum PhotoLibraryAddOutcome: Sendable, Equatable {
    /// 사진 보관함에 추가했다.
    case added
    /// 사진 추가 권한이 꺼져 있다(거부 · 제한). 사용자가 설정에서 켜야 한다.
    case permissionDenied
}

/// 사진 보관함에 이미지를 추가한다(절 이미지 저장 — 시안 G1 · G2).
///
/// **추가 전용 권한**만 쓴다(2026-09-15 결정). 보관함을 읽지 않으므로 앨범을 만들지 않고 최근 항목에 들어간다.
/// - Photos 구현은 App 타겟에서 한다.
public protocol PhotoLibraryClient: Sendable {
    /// 이미지를 사진 보관함에 추가한다. 권한을 아직 묻지 않았으면 먼저 묻는다.
    /// - Parameter imageData: PNG 이미지 데이터.
    /// - Returns: 추가했는지, 권한이 꺼져 있는지.
    func addImage(_ imageData: Data) async throws -> PhotoLibraryAddOutcome
}

private enum PhotoLibraryClientKey: DependencyKey {
    static let liveValue: any PhotoLibraryClient = UnimplementedPhotoLibraryClient()
    static let testValue: any PhotoLibraryClient = UnimplementedPhotoLibraryClient()
}

public extension DependencyValues {
    /// 사진 보관함 추가.
    var photoLibraryClient: any PhotoLibraryClient {
        get { self[PhotoLibraryClientKey.self] }
        set { self[PhotoLibraryClientKey.self] = newValue }
    }
}

/// 주입하지 않았을 때 — 저장한 척하지 않고 실패로 알린다.
private struct UnimplementedPhotoLibraryClient: PhotoLibraryClient {
    struct NotConfigured: Error {}

    func addImage(_ imageData: Data) async throws -> PhotoLibraryAddOutcome {
        throw NotConfigured()
    }
}
